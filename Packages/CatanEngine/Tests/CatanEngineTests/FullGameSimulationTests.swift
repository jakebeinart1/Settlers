import Testing
@testable import CatanEngine

@Test func randomLegalPlayReachesGameOverWithoutErrors() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 7))
    var rng = SeededGenerator(seed: 7)
    let winner = playRandomlyToCompletion(&state, rng: &rng, moveLimit: 20_000)
    #expect(winner != nil, "game did not terminate")
}

@Test func anExpandedGamePlaysToTwentyFiveWithoutStalling() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 2_501, shape: .expanded),
                                  seed: 2_501, mode: .expanded)
    var rng = SeededGenerator(seed: 2_501)
    // Raised from the classic 20,000 because a 25-point game on twice the map
    // is legitimately longer. A stall shows up as exhausting this cap.
    let winner = playRandomlyToCompletion(&state, rng: &rng, moveLimit: 60_000)
    #expect(winner != nil, "Expanded game did not finish inside 60,000 moves")
    if let winner {
        #expect(state.victoryPoints(for: winner) >= 25)
    }
    #expect(state.mode == .expanded)
}

@Test func expandedPieceSuppliesAreNeverExceededOverAFullGame() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 2_502, shape: .expanded),
                                  seed: 2_502, mode: .expanded)
    var rng = SeededGenerator(seed: 2_502)
    _ = playRandomlyToCompletion(&state, rng: &rng, moveLimit: 60_000)
    for player in state.players {
        #expect(player.roads.count <= 30)
        #expect(player.settlements.count <= 10)
        #expect(player.cities.count <= 8)
    }
}

/// Uniform random choices run through the production session: offers receive live
/// replies and the bot action backstop prevents an unresolved negotiation from owning
/// the whole simulation. Raw rule application is covered by the focused rule tests.
private func playRandomlyToCompletion(
    _ state: inout GameState, rng: inout SeededGenerator, moveLimit: Int
) -> PlayerID? {
    let policies = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, UniformSimulationPolicy() as any Policy) })
    var session = GameSession(state: state, policies: policies, policySeed: rng.next())
    defer { state = session.state }
    for _ in 0..<moveLimit {
        if case .gameOver(let winner) = session.nextActor() { return winner }
        do {
            guard try session.step() != nil else {
                Issue.record("a fully automated table stopped in \(session.state.phase)")
                return nil
            }
        } catch {
            Issue.record("a legal simulation move failed: \(error)")
            return nil
        }
    }
    return nil
}

private struct UniformSimulationPolicy: Policy {
    let id = "uniform-engine-simulation"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        precondition(!observation.legalMoves.isEmpty, "no legal move for simulation seat \(observation.seat)")
        return observation.legalMoves.randomElement(using: &rng)!
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
