import Foundation
import Testing
@testable import CatanEngine

private struct CheckpointPolicy: Policy {
    let id = "checkpoint-random-legal"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves.randomElement(using: &rng)!
    }
}

@Test func serializedSessionKeepsTheAlreadySampledTradeResponse() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 971)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = [.brick: 1]
    state.players[1].resources = [.grain: 1]
    state.bank[.brick, default: 0] -= 1
    state.bank[.grain, default: 0] -= 1
    let policies = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, CheckpointPolicy() as any Policy) })
    var original = GameSession(state: state, policies: policies, policySeed: 817)
    let offer = TradeOffer(from: PlayerID(index: 0), give: [.brick: 1], want: [.grain: 1])
    _ = try original.commit(seat: PlayerID(index: 0), move: .proposeTrade(offer))
    let bytes = try JSONEncoder().encode(original.checkpoint)
    let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: bytes)
    var resumed = try GameSession(checkpoint: checkpoint, policies: policies)
    let originalDecision = original.decideNextDetailed()
    let resumedDecision = resumed.decideNextDetailed()
    let expected = try #require(originalDecision)
    let actual = try #require(resumedDecision)
    #expect(expected.move == actual.move)
    #expect(expected.seat == actual.seat)
    #expect(expected.evaluationIndex == actual.evaluationIndex)
    #expect(expected.observation.state == actual.observation.state)
    #expect(original.policyRNG == resumed.policyRNG)
    #expect(original.policyEvaluationCount == resumed.policyEvaluationCount)
}

@Test func serializedSessionRejectsChangingThePolicyRoster() throws {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 971)
    let session = GameSession(state: state, policies: [PlayerID(index: 0): CheckpointPolicy()], policySeed: 817)
    #expect(throws: GameSession.CheckpointError.self) {
        try GameSession(checkpoint: session.checkpoint, policies: [:])
    }
}

@Test func serializedSessionResumesTheSameDecisionsWithoutRestartingPolicyRandomness() throws {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 971)
    let policies = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, CheckpointPolicy() as any Policy) })
    var original = GameSession(state: state, policies: policies, policySeed: 817)
    for _ in 0..<30 { _ = try #require(try original.step()) }
    let bytes = try JSONEncoder().encode(original.checkpoint)
    let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: bytes)
    var resumed = try GameSession(checkpoint: checkpoint, policies: policies)

    for _ in 0..<50 {
        let expected = try original.step()
        let actual = try resumed.step()
        #expect(expected?.actor == actual?.actor)
        #expect(expected?.move == actual?.move)
        #expect(original.state == resumed.state)
        #expect(original.policyRNG == resumed.policyRNG)
        #expect(original.policyEvaluationCount == resumed.policyEvaluationCount)
    }
}
