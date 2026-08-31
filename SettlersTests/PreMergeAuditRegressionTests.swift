import Testing
import CatanEngine
@testable import Settlers

/// Regressions for the blockers a pre-merge audit found in this branch.
///
/// Each one shipped through a gate that was green, so each is a case nothing
/// was checking. They are grouped here rather than scattered so the next
/// person can see what this feature's failure modes actually were.

@MainActor
private func hotSeat(humans: Set<Int>, seats: Int = 4, phaseSeat: Int = 0) -> GameViewModel {
    let model = GameViewModel()
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, playerCount: seats)
    state.phase = .mainTurn(playerIndex: phaseSeat)
    model.replaceStateForTesting(state, humanSeats: Set(humans.map { PlayerID(index: $0) }))
    return model
}

// MARK: - B2: an unclaimed device must never draw somebody's hand

@MainActor
@Test func anUnclaimedPhoneIsCoveredEvenDuringABotTurn() {
    // Saves are written after every bot move, so force-quitting mid-bot-turn
    // and relaunching is an ordinary path, not an edge case. Before the fix no
    // cover appeared - a bot phase owes no human a turn - while `humanPlayer`
    // fell back to the lowest human seat and drew that player's full hand to
    // whoever picked the phone up.
    let model = hotSeat(humans: [0, 2], phaseSeat: 1)   // seat 1 is a bot
    model.qaClearSeatAtDeviceForTesting()
    #expect(model.needsHandoff, "nobody is holding the phone; the hand must stay covered")
}

@MainActor
@Test func aSoloGameIsNeverCoveredEvenWithNobodyClaimed() {
    let model = hotSeat(humans: [1], phaseSeat: 1)
    model.qaClearSeatAtDeviceForTesting()
    #expect(!model.needsHandoff, "one player holding their own phone must never be asked to pass it")
}

// MARK: - B3: lifetime statistics belong to a solo player

@MainActor
@Test func aHotSeatGameDoesNotTouchLifetimeStatistics() {
    // `apply` applies every move as the seat holding the phone, so the winner
    // of a hot-seat game IS the phone's owner by construction. Recording it
    // drives a shared device to a permanent 100% win rate.
    let model = hotSeat(humans: [0, 1])
    #expect(model.humanSeats.count == 2)
    #expect(!model.shouldRecordLifetimeStatistics,
            "a shared-device game must not be filed against one person's record")
}

@MainActor
@Test func aSoloGameDoesRecordStatistics() {
    #expect(hotSeat(humans: [0]).shouldRecordLifetimeStatistics)
}

// MARK: - B4: an all-human table has nobody to answer a proposal

@MainActor
@Test func anAllHumanTableOffersNoBotTrade() {
    // `resolveHumanProposedTrade` iterates an empty bot set, so the proposal is
    // answered by nobody and leaves an offer no seat can ever see.
    #expect(!hotSeat(humans: [0, 1, 2, 3]).hasBotSeats)
    #expect(hotSeat(humans: [0, 1, 2]).hasBotSeats)
    #expect(hotSeat(humans: [0]).hasBotSeats)
}

// MARK: - B8: a name typed on the New Game screen must survive a relaunch

@MainActor
@Test func aSoloPlayersNameSurvivesARelaunch() {
    let model = GameViewModel()
    var config = MatchSetup(
        seats: (0..<4).map {
            MatchSetup.Seat(index: $0, isHuman: $0 == 0,
                            name: $0 == 0 ? "Bartholomew" : "",
                            civilization: Civilization.allCases[$0])
        },
        victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
    config.seats[0].name = "Bartholomew"
    model.startNewGame(setup: config)

    #expect(CatanTheme.playerLabel(for: PlayerID(index: 0)) == "Bartholomew",
            "the name typed at setup is the running value; the App Settings default is only a prefill")
}

// MARK: - B3 (second half): the victory-point cap follows the game's target

@MainActor
@Test func anEpicWinIsNotFiledAsATen() {
    let model = GameViewModel()
    let config = MatchSetup(
        seats: (0..<4).map {
            MatchSetup.Seat(index: $0, isHuman: $0 == 0, name: $0 == 0 ? "A" : "",
                            civilization: Civilization.allCases[$0])
        },
        victoryPointTarget: 12, randomizedBoard: false, randomizeSeatOrder: false)
    model.startNewGame(setup: config)
    #expect(model.state.victoryPointTarget == 12,
            "the cap on a recorded score follows this target, not a hardcoded ten")
}
