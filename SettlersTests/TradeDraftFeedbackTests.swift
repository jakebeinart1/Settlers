import Testing
import CatanEngine
@testable import Settlers

struct TradeDraftFeedbackTests {
    private let human = PlayerID(index: 2)

    @Test func playerOfferUsesInventoryAndNeverBankRates() {
        let draft = feedback(give: [.grain: 1], receive: [.ore: 3], mode: .players)
        #expect(draft.canSubmit)
        #expect(draft.remaining(.grain) == 6)
        #expect(draft.canAdd(.ore, toGive: false))
        #expect(!draft.canAdd(.grain, toGive: false))
        #expect(!draft.message.contains("2:1"))
        #expect(draft.addStep(.grain) == 1)
    }

    @Test func bankPartialBundleAddsOnlyTheRemainderAndRemovesOnlyThePartialStack() {
        let draft = feedback(give: [.grain: 1], receive: [.ore: 1])
        #expect(!draft.canSubmit)
        #expect(draft.addStep(.grain) == 1)
        #expect(draft.removeStep(.grain) == 1)
        #expect(draft.message.contains("1 more Grain"))
        #expect(feedback(give: [.grain: 2], receive: [.ore: 1]).canSubmit)
    }

    @Test func removingPaymentPreservesReceivePileAndExplainsTheShortfall() {
        let draft = feedback(give: [.grain: 2], receive: [.ore: 3])
        #expect(!draft.canSubmit)
        #expect(draft.message.contains("Remove 2"))
        #expect(!draft.canAdd(.ore, toGive: false))
        #expect(draft.receive == [.ore: 3])
    }

    @Test func unspentBankCreditIsActionable() {
        let draft = feedback(give: [.grain: 6], receive: [.ore: 1])
        #expect(!draft.canSubmit)
        #expect(draft.message.contains("Choose 2 more"))
        #expect(draft.canAdd(.ore, toGive: false))
    }

    @Test func depletedStockAndStaleInventoryNeverEnableSubmission() {
        var state = fixture()
        state.bank[.ore] = 0
        let depleted = TradeDraftFeedback(give: [.grain: 2], receive: [.ore: 1], mode: .bank, player: human, state: state)
        #expect(!depleted.canSubmit)
        #expect(!depleted.canAdd(.ore, toGive: false))
        #expect(depleted.message.contains("bank has 0 Ore"))
        state.players[human.index].resources[.grain] = 1
        let stale = TradeDraftFeedback(give: [.grain: 2], receive: [.ore: 1], mode: .players, player: human, state: state)
        #expect(!stale.canSubmit)
        #expect(stale.remaining(.grain) == 0)
        #expect(stale.message.contains("only hold 1 Grain"))
        #expect(stale.give == [.grain: 2], "Feedback must not silently rewrite the player's draft")
    }

    @Test func giveControlsStopAtTheActualHoldingAndTheTurnBoundary() {
        let draft = feedback(give: [.grain: 6], receive: [.ore: 3])
        #expect(draft.canSubmit)
        #expect(!draft.canAdd(.grain, toGive: true))
        var state = fixture()
        state.phase = .mainTurn(playerIndex: 0)
        let otherTurn = TradeDraftFeedback(give: [.grain: 2], receive: [.ore: 1], mode: .bank, player: human, state: state)
        #expect(!otherTurn.canSubmit)
        #expect(!otherTurn.canAdd(.grain, toGive: true))
    }

    @Test func incomingSummaryReversesTheProposersPilesInStableResourceOrder() {
        let offer = TradeOffer(from: PlayerID(index: 0), give: [.wool: 1, .ore: 1, .lumber: 1, .brick: 2], want: [.grain: 3])
        let summary = IncomingTradeSummary(offer: offer)
        #expect(summary.giveText == "You give 3 Grain")
        #expect(summary.receiveText == "You receive 2 Brick, 1 Lumber, 1 Ore, 1 Wool")
        #expect(summary.requiresReview)
        #expect(summary.give == [.grain: 3])
        #expect(summary.receive == offer.give)
    }

    private func feedback(give: [Resource: Int], receive: [Resource: Int], mode: Trading.DraftMode = .bank) -> TradeDraftFeedback {
        TradeDraftFeedback(give: give, receive: receive, mode: mode, player: human, state: fixture())
    }

    private func fixture() -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_308)
        let port = state.board.ports.first { $0.kind == .resource(.grain) }!
        state.players[human.index].settlements.insert(port.vertexA)
        state.players[human.index].resources = [.grain: 7]
        state.bank[.grain, default: 0] -= 7
        state.phase = .mainTurn(playerIndex: human.index)
        return state
    }
}
