import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostPolicyTests {

    private func midGame(seed: UInt64 = 83) -> (GameObservation, PlayerID) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 1, .lumber: 1]
        let me = state.players[0].id
        return (GameObservation(seat: me, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: me)), me)
    }

    /// piKL's promise, at its crudest: a ghost with a strong habit shows it.
    @Test func aStrongHabitDominatesAtHighLambda() {
        let (obs, _) = midGame()
        var person = PersonModel.anchored(at: .forMode(.classic))
        person.theta[StyleFeatures.labels.firstIndex(of: "endTurn")!] = -100
        person.theta[StyleFeatures.labels.firstIndex(of: "buildRoad")!] = 100
        var rng = RandomSource(seed: 1)
        let move = GhostPolicy(person: person, lambda: 1).decide(obs, rng: &rng)
        guard case .buildRoad = move else { Issue.record("expected a road, got \(move)"); return }
    }

    /// At lambda 0 the person does not matter: the ghost is Expert's scorer.
    @Test func lambdaZeroIgnoresThePerson() {
        let (obs, _) = midGame()
        var person = PersonModel.anchored(at: .forMode(.classic))
        person.theta[StyleFeatures.labels.firstIndex(of: "buildRoad")!] = 100
        var rng = RandomSource(seed: 1)
        #expect(GhostPolicy(person: person, lambda: 0).decide(obs, rng: &rng)
            == GhostPolicy(person: .anchored(at: .forMode(.classic)), lambda: 0).decide(obs, rng: &rng))
    }

    /// The engine term keeps the ghost playing: an anchored person at moderate
    /// lambda finishes a real game with only legal moves. This guards against the
    /// 0/40 collapse of the old imitation policy.
    @Test func aGhostFinishesAGame() throws {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: 84), seed: 84)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = EvaluationPolicy() }
        policies[initial.players[0].id] = GhostPolicy(person: .anchored(at: .forMode(.classic)), lambda: 0.5)
        var session = GameSession(state: initial, policies: policies, policySeed: 84)
        _ = try session.run()
        guard case .gameOver = session.state.phase else {
            Issue.record("game did not finish: \(session.state.phase)")
            return
        }
    }
}
