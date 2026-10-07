import Foundation
import Testing
import CatanEngine
@testable import Settlers

/// Validate the injected selection before expensive native UI runs. A card
/// that Trading can accept may still be outside the bot's policy action mask.
@MainActor
@Suite(.serialized)
struct TradeTapSafetyFixtureTests {
    @Test(arguments: [false, true], [GameMode.classic, .naval])
    func aRealMaskedProposalConservesCardsAndEndsAfterEitherAnswer(bundled: Bool, mode: GameMode) throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var setup = fixture.setup
        setup.mode = mode
        setup.victoryPointTarget = Ruleset.forMode(mode).defaultVictoryPointTarget
        setup.randomizedBoard = mode == .naval
        model.startNewGame(setup: setup)
        model.isBlockingSurfaceOpen = true
        defer { model.isBlockingSurfaceOpen = true }
        let originalSupply = supply(model.state)
        model.qaPrepareBotTradeAfterPause(bundled: bundled)
        #expect(supply(model.state) == originalSupply)
        var session = model.session
        let decision = session.decideNext()
        let chosen = try #require(decision)
        guard case .proposeTrade(let offer) = chosen.move else { Issue.record("Fixture must propose"); return }
        #expect(Trading.bothSidesCanHonour(offer, responder: model.humanPlayer, state: session.state))
        _ = try session.commit(seat: chosen.seat, move: chosen.move)
        try session.checkpoint.validate()
        #expect(session.state.pendingTradeOffers == [offer])
        for accepted in [false, true] {
            try assertAnsweredProposal(session, offer: offer, human: model.humanPlayer,
                                       accepted: accepted, originalSupply: originalSupply)
        }
    }

    private func assertAnsweredProposal(_ proposed: GameSession, offer: TradeOffer, human: PlayerID, accepted: Bool,
                                        originalSupply: [Resource: Int]) throws {
        var answered = proposed
        _ = try answered.applyExternal(.respondToTrade(offerID: offer.id, accept: accepted), by: human)
        #expect(answered.state.pendingTradeOffers.isEmpty)
        #expect(supply(answered.state) == originalSupply)
        #expect(answered.decideNext()?.move == .endTurn,
                "Neither a refusal nor an acceptance may trigger a second synthetic proposal")
        try answered.checkpoint.validate()
    }

    private func supply(_ state: GameState) -> [Resource: Int] {
        Dictionary(uniqueKeysWithValues: Resource.allCases.map { resource in
            (resource, state.bank[resource, default: 0]
                + state.players.reduce(0) { $0 + $1.resources[resource, default: 0] })
        })
    }
}
