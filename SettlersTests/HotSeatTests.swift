import Testing
import CatanEngine
@testable import Settlers

/// Covers multiple humans sharing one device.
///
/// The failure mode here is silent. A hidden-information leak throws nothing,
/// logs nothing and crashes nothing - it just renders one person's hand to
/// another person, and no test fails unless one is written. These are that
/// test.

@MainActor
private func hotSeatGame(humans: Set<Int>, seats: Int = 4, phaseSeat: Int = 0) -> GameViewModel {
    let model = isolatedGameViewModel()
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, playerCount: seats)
    state.phase = .mainTurn(playerIndex: phaseSeat)
    model.replaceStateForTesting(state, humanSeats: Set(humans.map { PlayerID(index: $0) }))
    return model
}

@MainActor
@Test func oneHumanNeverNeedsAHandoff() {
    // The single-human path must not change at all. A cover appearing in a
    // solo game would be a regression visible on the very first turn.
    for seat in 0..<4 {
        let model = hotSeatGame(humans: [seat], phaseSeat: seat)
        #expect(!model.needsHandoff, "solo game at seat \(seat) asked for a handoff")
        #expect(model.humanPlayer.index == seat)
    }
}

@MainActor
@Test func aHandoffIsNeededWhenAnotherHumanIsOwedTheTurn() {
    // Seats 0 and 2 are people; the phone is with seat 0 and the game is
    // waiting on seat 2.
    let model = hotSeatGame(humans: [0, 2], phaseSeat: 2)
    #expect(model.needsHandoff)
    #expect(model.seatOwedATurn?.index == 2)
}

@MainActor
@Test func noHandoffWhenTheSeatOwedIsAlreadyHoldingThePhone() {
    let model = hotSeatGame(humans: [0, 2], phaseSeat: 0)
    #expect(!model.needsHandoff, "the player already holding the phone must not be asked to pass it to themselves")
}

@MainActor
@Test func noHandoffWhileABotIsPlaying() {
    // Seats 0 and 2 are people, seat 1 is a bot and it is seat 1's turn. The
    // cover must not appear mid-bot-turn - there is nobody to pass it to.
    let model = hotSeatGame(humans: [0, 2], phaseSeat: 1)
    #expect(!model.needsHandoff)
    #expect(model.seatOwedATurn == nil)
}

@MainActor
@Test func claimingTheDeviceEndsTheHandoff() {
    let model = hotSeatGame(humans: [0, 2], phaseSeat: 2)
    model.claimDeviceForSeatOwedATurn()
    #expect(!model.needsHandoff)
    #expect(model.seatAtDevice?.index == 2)
    #expect(model.humanPlayer.index == 2, "the hand on screen must be the new player's")
}

@MainActor
@Test func exactlyOneSeatEverShowsItsFullHand() {
    // The app's whole hidden-information boundary, asserted against the
    // function the view actually calls.
    //
    // The previous version of this test was vacuous: it filtered the device
    // seat out of a list and then asserted the list did not contain it. An
    // audit showed that three separate mutations destroying hand-hiding left
    // all 78 tests green, which is the worst possible property for a test to
    // have - it made the most safety-critical behaviour on the branch look
    // covered while covering nothing.
    for humans in [[0], [0, 1], [0, 1, 2], [0, 1, 2, 3]] {
        for device in humans {
            let model = hotSeatGame(humans: Set(humans), phaseSeat: device)
            model.claimDeviceForSeatOwedATurn()
            let shown = BotHUDRow.seatsShowingFullHand(in: model.state, deviceSeat: model.humanPlayer)

            #expect(shown == [model.humanPlayer],
                    "\(humans.count) humans, device at \(device): full hands shown for \(shown.map(\.index).sorted())")
            #expect(shown.count == 1, "more than one hand on screen is a leak")

            // Specifically: no OTHER person's hand, which is the case bots
            // never exercised.
            for other in model.humanSeats where other != model.humanPlayer {
                #expect(!shown.contains(other),
                        "seat \(other.index)'s hand is visible to seat \(model.humanPlayer.index)")
            }
        }
    }
}

@MainActor
@Test func everyOtherSeatIsRenderedAsAnOpponent() {
    // The complement: nobody is silently dropped from the HUD either.
    let model = hotSeatGame(humans: [0, 1, 2, 3], phaseSeat: 0)
    let opponents = BotHUDRow.seatsShownAsOpponents(in: model.state, deviceSeat: model.humanPlayer)
    #expect(opponents.count == model.state.players.count - 1)
    #expect(!opponents.map(\.id).contains(model.humanPlayer))
}

@MainActor
@Test func aFourHumanTableHasNoBots() {
    let model = hotSeatGame(humans: [0, 1, 2, 3])
    #expect(model.humanSeats.count == 4)
    // Every seat is external, so the session must never decide for anyone.
    #expect(model.openIncomingOffer == nil)
}

@MainActor
@Test func humanSeatsAreEnumeratedInAStableOrder() {
    // `humanSeats` is a `Set`, and Swift seeds hash order per process - so
    // anything that enumerates it and reaches a decision differs between
    // launches. This repo has been bitten by that four separate times.
    let model = hotSeatGame(humans: [3, 1, 2])
    #expect(model.sortedHumanSeats.map(\.index) == [1, 2, 3])
}

// MARK: - The discard phase, which has no single seat

/// `replaceStateForTesting` parks the phone with the lowest human seat, which
/// is the state a hot-seat game is in when the 7 is rolled on that seat's turn.
@MainActor
private func discardingGame(humans: Set<Int>, pending: Set<Int>) -> GameViewModel {
    let model = isolatedGameViewModel()
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
    state.phase = .discarding(pending: Set(pending.map { PlayerID(index: $0) }))
    model.replaceStateForTesting(state, humanSeats: Set(humans.map { PlayerID(index: $0) }))
    return model
}

/// `GamePhase.awaitingSeatIndex` answers `nil` for `.discarding`, so a handoff
/// derived from it alone never fired here - and the game deadlocked outright.
/// After a 7, the human holding the phone discarded, the second human stayed
/// pending, no cover appeared, `humanPlayer` never moved, and the discard sheet
/// (gated on `humanPlayer` being pending) simply went away.
@MainActor
@Test func aSecondHumanOwedADiscardIsHandedThePhone() {
    let model = discardingGame(humans: [0, 1], pending: [0, 1])
    // The holder discards first - nobody is asked to pass a phone they still
    // have to use.
    #expect(model.seatOwedATurn?.index == 0)
    #expect(!model.needsHandoff)

    // Seat 0 has now discarded; only seat 1 still owes one.
    var settled = model.state
    settled.phase = .discarding(pending: [PlayerID(index: 1)])
    model.replaceStateForTesting(settled, humanSeats: [PlayerID(index: 0), PlayerID(index: 1)])

    #expect(model.seatOwedATurn?.index == 1, "the remaining discarder must be findable")
    #expect(model.needsHandoff, "the phone has to reach the player who still owes a discard")
    model.claimDeviceForSeatOwedATurn()
    #expect(model.humanPlayer.index == 1, "the discard sheet follows `humanPlayer`, so it must move")
}

@MainActor
@Test func aSubmittedDiscardCannotLeakItsDraftIntoTheNextHumansHandoff() {
    let model = isolatedGameViewModel()
    let first = PlayerID(index: 0)
    let second = PlayerID(index: 1)
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
    state.players[first.index].resources = [.brick: 8]
    state.players[second.index].resources = [.brick: 8]
    state.bank[.brick] = 3
    state.lastDiceRoll = 7
    state.robberMoverIndex = first.index
    state.phase = .discarding(pending: [first, second])
    model.replaceStateForTesting(state, humanSeats: [first, second])

    for _ in 0..<4 { model.selectForDiscard(.brick) }
    #expect(model.submitDiscard())

    #expect(model.discardDraft.counts.isEmpty)
    #expect(!model.isDiscardEditorMinimized)
    #expect(model.needsHandoff)
    #expect(model.seatOwedATurn == second)

    model.claimDeviceForSeatOwedATurn()

    #expect(model.humanPlayer == second)
    #expect(model.currentDiscardObligation?.owner == second)
    #expect(model.discardDraft.counts.isEmpty)
    #expect(!model.isDiscardEditorMinimized)
}

/// A bot owing a discard is the session's problem, not the phone's.
@MainActor
@Test func aBotOwingADiscardAsksForNoHandoff() {
    let model = discardingGame(humans: [0, 1], pending: [2])
    #expect(model.seatOwedATurn == nil)
    #expect(!model.needsHandoff)
}

/// The solo path is untouched: one human is never asked to pass anything.
@MainActor
@Test func aSoloHumanOwingADiscardIsNotAskedToPassThePhone() {
    let model = discardingGame(humans: [0], pending: [0, 2])
    #expect(!model.needsHandoff)
    #expect(model.humanPlayer.index == 0)
}

@MainActor
@Test func aThreeSeatHotSeatGameWorks() {
    let model = hotSeatGame(humans: [0, 1], seats: 3, phaseSeat: 1)
    #expect(model.state.players.count == 3)
    #expect(model.needsHandoff)
    model.claimDeviceForSeatOwedATurn()
    #expect(model.humanPlayer.index == 1)
}
