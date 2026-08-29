import Testing
import Foundation
@testable import CatanEngine

/// Guards the properties that make the engine measurable: a seeded game
/// reproduces exactly, a recorded move list replays to the same outcome, and
/// a save resumes mid-sequence rather than restarting it.
///
/// Before `RandomSource` existed these all failed. Dice were rolled with
/// `Int.random` and robber steals with `randomElement()`, both off the global
/// RNG from inside `RulesEngine.apply`, so:
///   - the same seed produced a different game on every run, which meant no
///     A/B comparison of a bot change could tell signal from noise, and
///   - `GameLogStore`'s trajectories were not replayable at all, despite its
///     own documentation and the logging spec both claiming they were. A
///     recorded 590-move game re-applied against its recorded start state
///     diverged immediately and hard-failed by move 17.

/// Whoever may legally act in `state`, or `nil` once the game is over.
/// `.discarding` names no single actor - any pending player may go - so this
/// picks the lowest seat, which keeps the driver reproducible.
func actingPlayer(_ state: GameState) -> PlayerID? {
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

/// Plays a complete game by picking uniformly among legal moves with an
/// injected generator, so move *selection* is reproducible too and any
/// divergence the tests below catch is the engine's, not the driver's.
private func playSeededGame(boardSeed: UInt64, driverSeed: UInt64)
    -> (start: GameState, moves: [(PlayerID, GameMove)], winner: PlayerID?) {
    let start = GameSetup.newGame(board: BoardGenerator.randomized(seed: boardSeed), seed: boardSeed)
    var state = start
    var driver = RandomSource(seed: driverSeed)
    var moves: [(PlayerID, GameMove)] = []

    for _ in 0..<4000 {
        if case .gameOver(let winner) = state.phase { return (start, moves, winner) }

        guard let actor = actingPlayer(state) else { return (start, moves, nil) }

        let legal = RulesEngine.legalMoves(for: state)
        guard let move = legal.randomElement(using: &driver) else { return (start, moves, nil) }
        moves.append((actor, move))
        do { try RulesEngine.apply(move, by: actor, to: &state) } catch { return (start, moves, nil) }
    }
    return (start, moves, nil)
}

@Test func sameSeedProducesAnIdenticalGame() {
    for seed: UInt64 in [42, 7, 1234] {
        let a = playSeededGame(boardSeed: seed, driverSeed: seed &* 31)
        let b = playSeededGame(boardSeed: seed, driverSeed: seed &* 31)

        #expect(a.moves.count == b.moves.count, "seed \(seed): move counts differ")
        #expect(a.winner == b.winner, "seed \(seed): winners differ")
        let firstDivergence = zip(a.moves, b.moves)
            .enumerated()
            .first { $0.element.0.0 != $0.element.1.0 || $0.element.0.1 != $0.element.1.1 }?
            .offset
        #expect(firstDivergence == nil, "seed \(seed): diverged at move \(firstDivergence ?? -1)")
    }
}

@Test func aRecordedMoveListReplaysToTheSameOutcome() {
    // This is precisely what a `GameLogStore` `.jsonl` holds: the initial
    // state, then the ordered (player, move) pairs.
    for seed: UInt64 in [42, 7, 1234] {
        let recorded = playSeededGame(boardSeed: seed, driverSeed: seed &* 17)
        #expect(recorded.moves.count > 100, "seed \(seed): recorded too few moves to be a useful check")

        // Rebuild the recording's own end state, so the comparison holds
        // whether or not uniform-random play happened to reach a winner.
        var original = recorded.start
        for (player, move) in recorded.moves { try! RulesEngine.apply(move, by: player, to: &original) }

        var replay = recorded.start
        var applied = 0
        for (player, move) in recorded.moves {
            #expect(throws: Never.self, "seed \(seed): replay threw at move \(applied) (\(move))") {
                try RulesEngine.apply(move, by: player, to: &replay)
            }
            applied += 1
        }
        #expect(applied == recorded.moves.count, "seed \(seed): replay stopped early")

        // Everything the dice and the robber steal feed into has to land the
        // same way. Before the RNG moved into `GameState`, replaying a real
        // 590-move log diverged at the first roll and threw by move 17.
        #expect(replay.phase == original.phase, "seed \(seed): replay ended in a different phase")
        #expect(replay.board.robberTile == original.board.robberTile,
                "seed \(seed): the robber ended somewhere else, so a steal or roll differed")
        #expect(replay.bank == original.bank, "seed \(seed): bank differs")
        for player in original.players {
            #expect(replay.players[player.id.index].resources == player.resources,
                    "seed \(seed): player \(player.id.index) holds different cards after replay")
            #expect(replay.players[player.id.index].settlements == player.settlements)
            #expect(replay.players[player.id.index].roads == player.roads)
        }
    }
}

@Test func aSaveResumesTheSameRandomSequenceItWouldHaveHad() {
    let recorded = playSeededGame(boardSeed: 99, driverSeed: 5)
    let cut = recorded.moves.count / 2
    #expect(cut > 0)

    var midGame = recorded.start
    for (player, move) in recorded.moves.prefix(cut) {
        try! RulesEngine.apply(move, by: player, to: &midGame)
    }

    // Round-trip through the same encoding `GameStore` uses, then finish the
    // game from the decoded copy and from the original in parallel.
    let encoded = try! JSONEncoder().encode(midGame)
    var resumed = try! JSONDecoder().decode(GameState.self, from: encoded)
    var uninterrupted = midGame
    for (player, move) in recorded.moves.dropFirst(cut) {
        try! RulesEngine.apply(move, by: player, to: &resumed)
        try! RulesEngine.apply(move, by: player, to: &uninterrupted)
    }

    #expect(resumed.phase == uninterrupted.phase, "a resumed save diverged from an uninterrupted run")
    for player in resumed.players {
        #expect(player.resources == uninterrupted.players[player.id.index].resources)
    }
}

@Test func legalMovesIsAPureFunctionOfTheState() {
    // Two calls over the same state must be equal. They were not: every
    // `.proposeTrade` candidate carried a freshly minted random UUID, so
    // `legalMoves` returned unequal results for identical input - which also
    // rules out hashing a state for a search transposition table.
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 3), seed: 3)
    var driver = RandomSource(seed: 11)

    for _ in 0..<250 {
        if case .gameOver = state.phase { break }
        let first = RulesEngine.legalMoves(for: state)
        let second = RulesEngine.legalMoves(for: state)
        #expect(first == second, "legalMoves returned different results for the same state")

        guard let actor = actingPlayer(state),
              let move = first.randomElement(using: &driver) else { break }
        try! RulesEngine.apply(move, by: actor, to: &state)
    }
}
