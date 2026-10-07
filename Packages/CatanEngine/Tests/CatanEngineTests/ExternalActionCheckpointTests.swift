import Foundation
import Testing
@testable import CatanEngine

struct ExternalActionCheckpointTests {
    @Test(arguments: [GameMode.classic, .naval])
    func validHumanActionsBeyondAutomatedCapColdResume(mode: GameMode) throws {
        let state = mode == .naval ? try NavalTestSupport.ready() : GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let session = GameSession(state: state, policies: [:], policySeed: 1)
        let data = try JSONEncoder().encode(session.checkpoint)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["currentTurnSeat"] = ["index": 0]
        object["actionsThisTurn"] = GameSession.actionLimit(in: state) + 1
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONSerialization.data(withJSONObject: object))
        var resumed = try GameSession(checkpoint: checkpoint, policies: [:])
        let move = try #require(RulesEngine.legalMoves(for: resumed.state).first)
        _ = try resumed.applyExternal(move, by: resumed.state.players[0].id)
        try resumed.checkpoint.validate()
    }

    @Test func duplicateOfferIDIsExcludedRejectedAndNeverMutates() throws {
        var state = try NavalTestSupport.ready()
        NavalTestSupport.fund([.brick: 3], in: &state)
        let owner = state.players[0].id
        let offer = TradeOffer.enumerated(from: owner, give: [.brick: 1], want: [.grain: 1])
        try RulesEngine.apply(.proposeTrade(offer), by: owner, to: &state)
        #expect(!RulesEngine.legalMoves(for: state).contains(.proposeTrade(offer)))
        #expect(!RulesEngine.isPermittedComposedProposal(.proposeTrade(offer), by: owner, in: state, legal: RulesEngine.legalMoves(for: state)))
        let before = state
        #expect(throws: MoveError.invalidTradeTarget) { try RulesEngine.apply(.proposeTrade(offer), by: owner, to: &state) }
        #expect(state == before)
        let distinct = TradeOffer(from: owner, give: offer.give, want: offer.want)
        try RulesEngine.apply(.proposeTrade(distinct), by: owner, to: &state)
        #expect(state.pendingTradeOffers.count == 2)
    }

    @Test(arguments: [1, 2])
    func legacyDuplicateOffersStillReplayUnderRecordedRules(version: Int) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 9)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 2]
        let owner = state.players[0].id
        let offer = TradeOffer.enumerated(from: owner, give: [.brick: 1], want: [.grain: 1])
        try RulesEngine.replay(.proposeTrade(offer), by: owner, rulesVersion: version, to: &state)
        try RulesEngine.replay(.proposeTrade(offer), by: owner, rulesVersion: version, to: &state)
        #expect(state.pendingTradeOffers.count == 2)
    }
}
