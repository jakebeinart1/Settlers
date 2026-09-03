import Testing
@testable import CatanEngine

/// Pins `GamePhase`'s seat accessors.
///
/// Worth testing despite being a switch: six hand-written copies of this exact
/// unpacking existed in the app layer and they did not agree. The Build button
/// had no copy at all and stayed enabled through setup; the board's `.mainTurn`
/// highlight arms omitted the seat check their setup counterparts have. One
/// accessor is only an improvement if it is right.

@Test func everyPhaseWithASeatReportsIt() {
    let cases: [(GamePhase, Int)] = [
        (.setupForward(playerIndex: 0), 0),
        (.setupBackward(playerIndex: 3), 3),
        (.rollDice(playerIndex: 1), 1),
        (.mainTurn(playerIndex: 2), 2),
        (.movingRobber(playerIndex: 3), 3),
    ]
    for (phase, expected) in cases {
        #expect(phase.awaitingSeatIndex == expected, "\(phase)")
    }
}

@Test func phasesNoSingleSeatOwnsReportNobody() {
    // `.discarding` is genuinely multi-seat - everyone over seven cards owes
    // one - and `.gameOver` waits on nobody. Returning a seat for either would
    // be inventing an answer, which is how seat 0 kept getting guessed.
    #expect(GamePhase.discarding(pending: [PlayerID(index: 1), PlayerID(index: 2)]).awaitingSeatIndex == nil)
    #expect(GamePhase.discarding(pending: []).awaitingSeatIndex == nil)
    #expect(GamePhase.gameOver(winner: PlayerID(index: 0)).awaitingSeatIndex == nil)
}

@Test func onlyMainTurnCountsAsAPlayableTurnForThatSeat() {
    // The distinction the Build button needs: setup is seat 2's turn, but seat
    // 2 may not build during it - only place. Answering "is it my turn" when
    // the question is "may I build" is what left Build lit through setup.
    #expect(GamePhase.mainTurn(playerIndex: 2).isMainTurn(of: 2))
    #expect(!GamePhase.mainTurn(playerIndex: 2).isMainTurn(of: 3))
    #expect(!GamePhase.setupForward(playerIndex: 2).isMainTurn(of: 2))
    #expect(!GamePhase.setupBackward(playerIndex: 2).isMainTurn(of: 2))
    #expect(!GamePhase.rollDice(playerIndex: 2).isMainTurn(of: 2))
    #expect(!GamePhase.movingRobber(playerIndex: 2).isMainTurn(of: 2))
    #expect(!GamePhase.gameOver(winner: PlayerID(index: 2)).isMainTurn(of: 2))
}

@Test func theAccessorAgreesWithTheSessionsOwnNotionOfWhoActs() throws {
    // The accessor must not become a second, drifting source of truth for the
    // same question `GameSession.nextActor()` already answers.
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3)
    var session = GameSession(state: state, policies: [:], policySeed: 1)

    for _ in 0..<40 {
        guard let seat = state.phase.awaitingSeatIndex else { break }
        guard case .awaitingExternalSeat(let actor) = session.nextActor() else { break }
        #expect(actor.index == seat, "phase \(state.phase) names seat \(seat), session names \(actor.index)")
        guard let move = RulesEngine.legalMoves(for: state, seat: actor).first else { break }
        try RulesEngine.apply(move, by: actor, to: &state)
        session.replace(state: state)
    }
}
