import Testing
import CatanEngine
@testable import Settlers

/// Covers the signal the bot loop stops on.
///
/// The reported symptom was an offer "flashing" - visible for about a second
/// and gone. The card is a live projection of `state.pendingTradeOffers`, the
/// proposing bot took its next action about a second later, and `endTurn`
/// clears every pending offer. So the fix is not a longer timer on the card;
/// it is that the bots must not move while the human has a decision open, and
/// `openIncomingOffer` is what the loop reads to know that.
///
/// Getting this predicate wrong fails in one of two expensive ways: too eager
/// and the game freezes with a card the human cannot act on, too lax and the
/// flash comes back.

@MainActor
/// `botHolds` is deliberately separate from `botOffers`: an offer promising
/// cards the proposer no longer has is exactly the stale case, and collapsing
/// the two into one parameter makes that case impossible to express.
private func gameAwaitingAnswer(humanHolds: [Resource: Int],
                                botHolds: [Resource: Int],
                                botOffers: [Resource: Int],
                                botWants: [Resource: Int]) -> GameViewModel {
    let model = GameViewModel()
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5)
    state.phase = .mainTurn(playerIndex: 1)
    state.players[0].resources = humanHolds
    state.players[1].resources = botHolds
    state.pendingTradeOffers = [TradeOffer(from: state.players[1].id, give: botOffers, want: botWants)]
    model.replaceStateForTesting(state, humanSeat: state.players[0].id)
    return model
}

@MainActor
@Test func anOfferTheHumanCanHonourStopsTheBots() {
    let model = gameAwaitingAnswer(humanHolds: [.grain: 2], botHolds: [.ore: 1],
                                   botOffers: [.ore: 1], botWants: [.grain: 1])
    #expect(model.openIncomingOffer != nil, "a live, affordable offer must hold the loop")
}

@MainActor
@Test func anOfferTheHumanCannotPayForDoesNotStopTheBots() {
    // The too-eager failure: holding the loop for an offer the human cannot
    // accept freezes the game behind a card that can never be answered.
    let model = gameAwaitingAnswer(humanHolds: [:], botHolds: [.ore: 1],
                                   botOffers: [.ore: 1], botWants: [.grain: 1])
    #expect(model.openIncomingOffer == nil, "an unaffordable offer must not hold the loop")
}

@MainActor
@Test func anOfferTheProposerCanNoLongerBackDoesNotStopTheBots() {
    // The proposer can spend what it offered before the human answers.
    // The bot promised an ore and has since spent it.
    let model = gameAwaitingAnswer(humanHolds: [.grain: 2], botHolds: [:],
                                   botOffers: [.ore: 1], botWants: [.grain: 1])
    #expect(model.openIncomingOffer == nil, "an offer the proposer cannot honour must not hold the loop")
}

@MainActor
@Test func theHumansOwnProposalDoesNotStopTheBots() {
    // A human-proposed offer is resolved by the bots, not by the human - and
    // holding the loop for it would deadlock, since the loop is what answers.
    let model = GameViewModel()
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 6)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = [.grain: 2]
    state.players[1].resources = [.ore: 2]
    state.pendingTradeOffers = [TradeOffer(from: state.players[0].id, give: [.grain: 1], want: [.ore: 1])]
    model.replaceStateForTesting(state, humanSeat: state.players[0].id)
    #expect(model.openIncomingOffer == nil, "the human's own proposal must not hold the loop")
}

@MainActor
@Test func nothingPendingLeavesTheBotsAlone() {
    let model = GameViewModel()
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
    model.replaceStateForTesting(state, humanSeat: state.players[0].id)
    #expect(model.openIncomingOffer == nil)
}

// MARK: - The second signal the loop stops on

/// Spec B3.4: the game must not advance behind `InGameSettingsView` while the
/// player is reading it. Before this, opening the in-game menu during a bot
/// turn left the bots playing on behind it, and the player came back to a
/// position they had never seen reached.
///
/// A bot seat is to act here (`.mainTurn(playerIndex: 1)` with the human at
/// seat 0, so `GameSession.nextActor()` answers `.seat`), which is what makes
/// "nothing happened" mean something: the loop had work and declined to do it.
/// It returns before its first `Task.sleep`, so this costs no wall-clock time,
/// applies no move, and - deliberately, per this suite's sibling
/// `PersistenceTests` caveat - writes neither the save file nor the game log.
@MainActor
@Test func anOpenSettingsSurfaceStopsTheBots() async {
    let model = GameViewModel()
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 11)
    state.phase = .mainTurn(playerIndex: 1)
    model.replaceStateForTesting(state, humanSeat: state.players[0].id)
    #expect(model.state.phase == .mainTurn(playerIndex: 1), "a bot seat is up, so the loop has work")

    model.isSettingsSurfaceOpen = true
    await model.runBotTurnIfNeeded()

    #expect(model.state.phase == .mainTurn(playerIndex: 1),
            "the bot loop must take no action while the settings surface is open")
}

/// The flag has to default to off, or the very first bot turn of every game
/// would never run.
@MainActor
@Test func theSettingsSurfaceStartsClosed() {
    #expect(GameViewModel().isSettingsSurfaceOpen == false)
}
