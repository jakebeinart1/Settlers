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
/// Re-recorded 2026-08-30 because the bots genuinely changed: trade proposals
/// widened from strictly one-card-for-one-card to quantities up to two per
/// side, and the heuristic now composes lopsided offers. Over fifteen games
/// the proposal mix went from 1,110 one-for-ones and nothing else to 761
/// one-for-ones, 342 two-for-ones and a handful of two-for-twos. The anchor
/// measurement was re-run alongside: still 40/40 against random play, so the
/// change did not break the bot.
private let expectedFingerprints: [UInt64: String] = [
    1: "01a87510183024b1",
    42: "581a271393456bdb",
    7: "30c7b2b825a1fe37",
    1234: "fa459410ec3e6873",
    99: "08ab96a81621227f",
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
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
    let seatPolicies: [any Policy] = [
        HeuristicPolicy(personality: .balanced, id: "heuristic-balanced"),
        HeuristicPolicy(personality: .aggressive, id: "heuristic-aggressive"),
        HeuristicPolicy(personality: .cautious, id: "heuristic-cautious"),
        HeuristicPolicy(personality: .balanced, id: "heuristic-balanced"),
    ]
    var seats: [PlayerID: any Policy] = [:]
    for (index, policy) in seatPolicies.enumerated() { seats[state.players[index].id] = policy }

    // Driven through `GameSession`, not by calling the bots directly.
    // This test and the `sim` harness both used to run private loops, so the
    // sequence pinned here was one no player ever actually experienced: it saw
    // the unscoped action list and had no runaway backstop, while the app had
    // both. A fingerprint of a loop nobody plays does not protect the game.
    //
    // `GameSession` seeds its own policy RNG from `policySeed`; the value below
    // is the same derivation the harness uses so the two play identical games.
    var session = GameSession(state: state, policies: seats, policySeed: seed &* 31 &+ 7)
    var trace: [String] = []

    for _ in 0..<3000 {
        guard case .seat = session.nextActor() else { break }
        guard let step = try! session.step() else { break }
        trace.append("P\(step.actor.index):\(canonical(step.move))")
    }

    var winner: PlayerID?
    if case .gameOver(let who) = session.state.phase { winner = who }
    return (fingerprint(trace), trace.count, winner)
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
