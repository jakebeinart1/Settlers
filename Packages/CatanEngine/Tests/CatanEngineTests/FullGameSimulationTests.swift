import Testing
@testable import CatanEngine

@Test func randomLegalPlayReachesGameOverWithoutErrors() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 7))
    var rng = SeededGenerator(seed: 7)
    var iterations = 0
    while true {
        if case .gameOver = state.phase { break }
        iterations += 1
        #expect(iterations < 20_000, "game did not terminate")
        if iterations >= 20_000 { break }
        let moves = RulesEngine.legalMoves(for: state)
        #expect(!moves.isEmpty, "no legal moves in phase \(state.phase)")

        // `.discarding` is the one phase where several players can act
        // concurrently and `legalMoves` returns the union of every pending
        // player's legal `.discard` combinations (see RulesEngine.swift). A
        // `GameMove.discard` payload carries no player identity - by design,
        // matching every other move type, where the actor is always supplied
        // separately via `apply(_:by:)` - so a move picked at random from
        // that merged list isn't necessarily legal for an arbitrarily-picked
        // pending player. Pick the acting player first, then restrict the
        // random choice to moves that are actually legal for them.
        let player: PlayerID
        let candidateMoves: [GameMove]
        if case .discarding(let pending) = state.phase {
            player = pending.sorted().randomElement(using: &rng)!
            let hand = state.players[player.index].resources
            let count = Robber.discardCount(for: state.players[player.index])
            candidateMoves = moves.filter { move in
                guard case .discard(let discarded) = move else { return false }
                guard discarded.values.reduce(0, +) == count else { return false }
                return discarded.allSatisfy { resource, amount in (hand[resource] ?? 0) >= amount }
            }
        } else {
            player = activePlayer(state.phase)
            candidateMoves = moves
        }
        #expect(!candidateMoves.isEmpty, "no legal moves for acting player in phase \(state.phase)")
        guard let move = candidateMoves.randomElement(using: &rng) else { break }
        try! RulesEngine.apply(move, by: player, to: &state)
    }
}

private func activePlayer(_ phase: GamePhase) -> PlayerID {
    switch phase {
    case .setupForward(let i), .setupBackward(let i), .rollDice(let i), .mainTurn(let i), .movingRobber(let i):
        return PlayerID(index: i)
    case .discarding(let pending): return pending.first!
    case .gameOver: fatalError("game over")
    }
}

/// Deterministic RNG so this test is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
