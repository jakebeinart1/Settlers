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
    let model = GameViewModel()
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
@Test func everySeatButTheOneAtTheDeviceIsAnOpponent() {
    // The hand-hiding property itself: `BotHUDRow` renders everyone except
    // `humanPlayer` as a chip, and a chip shows hand SIZE only. So the set of
    // seats whose hands are concealed must be every seat but the current one -
    // including the other humans.
    let model = hotSeatGame(humans: [0, 1, 2, 3], phaseSeat: 0)
    let concealed = model.state.players.map(\.id).filter { $0 != model.humanPlayer }
    #expect(concealed.count == 3)
    #expect(!concealed.contains(model.humanPlayer))
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

@MainActor
@Test func aThreeSeatHotSeatGameWorks() {
    let model = hotSeatGame(humans: [0, 1], seats: 3, phaseSeat: 1)
    #expect(model.state.players.count == 3)
    #expect(model.needsHandoff)
    model.claimDeviceForSeatOwedATurn()
    #expect(model.humanPlayer.index == 1)
}
