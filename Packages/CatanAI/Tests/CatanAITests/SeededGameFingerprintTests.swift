import Testing
import CatanEngine
@testable import CatanAI

/// Pins the exact move sequence a seeded self-play game produces.
///
/// ## What this is really guarding
/// Not the moves themselves - it is that the game is reproducible **across
/// processes**, which is the property every measurement of the bots depends
/// on. Without it you cannot replay a recorded game, cannot A/B a heuristic
/// change, and cannot bisect a failing simulation.
///
/// The obvious way to check reproducibility - play the same seed twice and
/// compare - is not enough, and believing it was is how this stayed broken.
/// Swift seeds `Set` and `Dictionary` iteration order **once per process**, so
/// two runs inside one test process agree with each other while disagreeing
/// with tomorrow's run. Four separate places let that ordering reach a
/// decision:
///
///   - `RobberHeuristics.verticesTouching` filtered a `Set` and then *summed a
///     Double* over the result. Floating-point addition is not associative, so
///     the same corners added in a different order differed in the last bit -
///     enough to flip `max(by:)` between two tiles meant to tie.
///   - `BuildPlanner.expansionTarget` picked its best vertex by strict `>`
///     while walking a `Set`, and `PlacementHeuristics.score` takes only a few
///     discrete values, so ties were the common case rather than a rare one.
///     That choice reaches every road score and then the tie pool that
///     consumes the RNG, so one flipped tie desynchronises the rest of the game.
///   - `DevCardHeuristics` flat-mapped a dictionary for Year of Plenty's two
///     cards and picked its Monopoly target with `max(by:)` over a `Set`.
///   - `SetupPhase.unroadedSettlement` took `.first` of a `Set`.
///
/// Because the hash seed is fresh in every test process, a regression in any
/// of them shows up here as a failing (not merely flaky) test most of the time.
///
/// ## If this test fails
/// Either the bots genuinely changed - in which case re-record the constants
/// below in the same commit that changed them, and say so in the message - or
/// ordering has leaked back in. To tell which: run the same seed in several
/// separate processes. If they disagree with *each other*, it is ordering.
private let expectedFingerprints: [UInt64: String] = [
    1: "7cc7aee7b0c9c4d9",
    42: "30f84fa73e61c1d7",
    7: "b338b8f0b41989bb",
    1234: "a4085aa0b3710e51",
    99: "526167e40f10ea2a",
]

/// Whoever may act, or `nil` at game over.
private func actingPlayer(_ state: GameState) -> PlayerID? {
    switch state.phase {
    case .setupForward(let i), .setupBackward(let i),
         .rollDice(let i), .mainTurn(let i), .movingRobber(let i):
        return state.players[i].id
    case .discarding(let pending):
        return pending.sorted().first
    case .gameOver:
        return nil
    }
}

/// A move rendering whose dictionary payloads are in a fixed order - a
/// `[Resource: Int]` prints its keys in a per-process order, which would make
/// this fingerprint unstable for reasons unrelated to play.
private func canonical(_ move: GameMove) -> String {
    func table(_ amounts: [Resource: Int]) -> String {
        Resource.allCases
            .compactMap { resource in amounts[resource].map { "\(resource)=\($0)" } }
            .joined(separator: ",")
    }
    switch move {
    case .discard(let amounts):
        return "discard[\(table(amounts))]"
    case .bankTrade(let give, let get):
        return "bankTrade[\(table(give))->\(table(get))]"
    case .proposeTrade(let offer):
        return "proposeTrade[p\(offer.from.index):\(table(offer.give))->\(table(offer.want))]"
    default:
        return "\(move)"
    }
}

/// FNV-1a. Not cryptographic - it only has to change when the sequence does.
private func fingerprint(_ moves: [String]) -> String {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for move in moves {
        for byte in move.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }
    return String(format: "%016llx", hash)
}

private func playSeededGame(seed: UInt64) -> (fingerprint: String, moves: Int, winner: PlayerID?) {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
    let bots = [
        Bot(personality: .balanced), Bot(personality: .aggressive),
        Bot(personality: .cautious), Bot(personality: .balanced),
    ]
    // The bot's own tie-breaks are seeded too, via the `rng:` overload used
    // below. `Bot.decide(for:player:)` - the overload WITHOUT an rng - builds
    // a fresh `SystemRandomNumberGenerator` on every call, so it can never be
    // reproducible and a measurement harness must never use it.
    var botRNG = RandomSource(seed: seed &* 31 &+ 7)
    var trace: [String] = []

    for _ in 0..<3000 {
        if case .gameOver(let winner) = state.phase {
            return (fingerprint(trace), trace.count, winner)
        }
        guard let actor = actingPlayer(state) else { break }
        let move = bots[actor.index].decide(for: state, player: actor, rng: &botRNG)
        trace.append("P\(actor.index):\(canonical(move))")
        try! RulesEngine.apply(move, by: actor, to: &state)
    }
    return (fingerprint(trace), trace.count, nil)
}

@Test func seededSelfPlayReproducesExactly() {
    for (seed, expected) in expectedFingerprints.sorted(by: { $0.key < $1.key }) {
        let result = playSeededGame(seed: seed)
        let detail = "seed \(seed): expected \(expected), got \(result.fingerprint) "
            + "(\(result.moves) moves, winner \(result.winner.map { "P\($0.index)" } ?? "none"))"
        #expect(result.fingerprint == expected, "\(detail)")
    }
}

@Test func replayingTheSameSeedInThisProcessAlsoMatches() {
    // Weaker than the pinned constants above - two runs in one process share a
    // hash seed - but it separates "the bots changed" from "ordering leaked
    // back in" when the test above fails.
    // One seed, not all five: each game is a full self-play run of several
    // hundred moves, and this check is diagnostic rather than the guarantee.
    let seed: UInt64 = 42
    #expect(playSeededGame(seed: seed).fingerprint == playSeededGame(seed: seed).fingerprint,
            "seed \(seed) is not even self-consistent within one process")
}
