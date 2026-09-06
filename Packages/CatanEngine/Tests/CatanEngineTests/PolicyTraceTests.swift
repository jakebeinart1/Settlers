import Foundation
import Testing
@testable import CatanEngine

@Suite struct PolicyTraceTests {
    private struct RejectingPolicy: Policy {
        let id = "trace-rejecting"
        func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
            _ = rng.next()
            return observation.legalMoves.first {
                if case .respondToTrade(_, false) = $0 { return true }
                return false
            } ?? observation.legalMoves[0]
        }
    }

    @Test func queuedDiagnosticDecisionIsVisibleBeforeCommitWithoutResampling() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 971)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 1]
        state.players[1].resources = [.grain: 1]
        let policies = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, RejectingPolicy() as any Policy) })
        var session = GameSession(state: state, policies: policies, policySeed: 817)
        #expect(session.queuedPolicyDecision == nil)
        let offer = TradeOffer(from: PlayerID(index: 0), give: [.brick: 1], want: [.grain: 1])
        _ = try session.commit(seat: PlayerID(index: 0), move: .proposeTrade(offer))
        let checkpoint = session.checkpoint
        let queued = try #require(session.queuedPolicyDecision)
        #expect(queued.evaluationIndex == 0)
        #expect(session.lastPolicyDecisions.map(\.evaluationIndex) == [1, 2])
        #expect(session.policyEvaluationCount == 3)
        #expect(session.queuedPolicyDecision == queued)
        #expect(session.checkpoint == checkpoint)
        #expect(session.decideNextDetailed() == queued)
        #expect(session.checkpoint == checkpoint)
        let step = try session.commit(seat: queued.seat, move: queued.move)
        #expect(step.policyTrace == queued.policyTrace)
        #expect(session.queuedPolicyDecision == nil)
        #expect(session.policyEvaluationCount == 3)
    }

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
