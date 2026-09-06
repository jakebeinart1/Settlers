import Foundation
import Testing
@testable import CatanEngine

@Suite struct PolicyTraceTests {
    private struct ObservedPolicy: Policy {
        let id = "test-neural-v1"
        func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
            preconditionFailure("session must call select once, not resample through decide")
        }
        func select(_ observation: GameObservation, rng: inout RandomSource) -> PolicySelection {
            _ = rng.next()
            return PolicySelection(move: observation.legalMoves[0], source: "neural")
        }
    }

    @Test func traceFollowsExactlyOneDecisionThroughCommit() throws {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 100)
        let seat = PlayerID(index: 0)
        var session = GameSession(state: state, policies: [seat: ObservedPolicy()], policySeed: 31)
        var expected = session.policyRNG
        _ = expected.next()
        let selected = session.decideNextDetailed()
        let decision = try #require(selected)
        #expect(session.policyRNG == expected)
        #expect(decision.policyTrace?.policyID == "test-neural-v1")
        let step = try session.commit(seat: seat, move: decision.move)
        #expect(step.policyTrace == decision.policyTrace)
        #expect(step.policyTrace?.selection.source == "neural")
        #expect(session.policyRNG == expected)
        let roundTrip = try JSONDecoder().decode(PolicyTrace.self, from: JSONEncoder().encode(try #require(step.policyTrace)))
        #expect(roundTrip == step.policyTrace)
    }

    @Test func externalMoveCannotInheritAnUncommittedPolicyLabel() throws {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 101)
        let seat = PlayerID(index: 0)
        var session = GameSession(state: state, policies: [seat: ObservedPolicy()], policySeed: 31)
        let selected = session.decideNextDetailed()
        let decision = try #require(selected)
        let step = try session.applyExternal(decision.move, by: seat)
        #expect(step.policyTrace == nil)
    }

    @Test func oldDecisionWithoutTraceStillDecodes() throws {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 102)
        let seat = PlayerID(index: 0)
        let observation = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        let decision = GameSession.Decision(evaluationIndex: 0, seat: seat, move: observation.legalMoves[0], observation: observation)
        let data = try JSONEncoder().encode(decision)
        let restored = try JSONDecoder().decode(GameSession.Decision.self, from: data)
        #expect(restored.policyTrace == nil)
    }
}
