import Foundation
import Testing
@testable import CatanEngine

private struct NavalAcceptPolicy: Policy {
    let id = "naval-accept-checkpoint"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove { observation.legalMoves[0] }
}

struct NavalTradeCheckpointTests {
    @Test func externalProposalQueuesAndExternalConsumptionClearsResponse() throws {
        var session = try fixture()
        let player = session.state.players[0].id
        let offer = TradeOffer(from: player, give: [.brick: 1], want: [.grain: 1])
        _ = try session.applyExternal(.proposeTrade(offer), by: player)
        #expect(session.checkpoint.queuedTradeResponse?.seat == session.state.players[1].id)
        try coldValidate(session)
        _ = try session.applyExternal(.respondToTrade(offerID: offer.id, accept: false), by: session.state.players[2].id)
        #expect(session.checkpoint.queuedTradeResponse == nil)
        try coldValidate(session)
    }

    @Test func externalBankSpendRefreshesCachedObservationWithoutRandomDraws() throws {
        var session = try fixture()
        let player = session.state.players[0].id
        let offer = TradeOffer(from: player, give: [.brick: 1], want: [.grain: 1])
        _ = try session.applyExternal(.proposeTrade(offer), by: player)
        let before = session.checkpoint
        let rate = Trading.bestRate(for: .ore, player: player, state: session.state)
        _ = try session.applyExternal(.bankTrade(give: [.ore: rate], get: [.wool: 1]), by: player)
        #expect(session.checkpoint.queuedTradeResponse?.observation != before.queuedTradeResponse?.observation)
        #expect(session.checkpoint.policyRNG == before.policyRNG)
        #expect(session.policyEvaluationCount == before.policyEvaluationCount + 1)
        try coldValidate(session)
        _ = try session.step()
        try coldValidate(session)
    }

    @Test func externalEndTurnCancelsCachedReply() throws {
        var session = try fixture()
        let player = session.state.players[0].id
        let offer = TradeOffer(from: player, give: [.brick: 1], want: [.grain: 1])
        _ = try session.applyExternal(.proposeTrade(offer), by: player)
        _ = try session.applyExternal(.endTurn, by: player)
        #expect(session.checkpoint.queuedTradeResponse == nil)
        try coldValidate(session)
    }

    private func fixture() throws -> GameSession {
        var state = try NavalTestSupport.ready()
        NavalTestSupport.fund([.brick: 1, .ore: 4], in: &state)
        NavalTestSupport.fund([.grain: 1], player: 1, in: &state)
        let policy: [PlayerID: any Policy] = [state.players[1].id: NavalAcceptPolicy(), state.players[2].id: NavalAcceptPolicy(), state.players[3].id: NavalAcceptPolicy()]
        return GameSession(state: state, policies: policy, policySeed: 123)
    }

    private func coldValidate(_ session: GameSession) throws {
        try session.checkpoint.validate()
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(session.checkpoint))
        try checkpoint.validate()
        #expect(checkpoint == session.checkpoint)
        _ = try GameSession(checkpoint: checkpoint, policies: session.policies)
    }
}
