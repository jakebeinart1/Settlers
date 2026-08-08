import Testing
@testable import CatanEngine

@Test func tenVictoryPointsEndsGame() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    for v in state.board.onBoardVertices.sorted().prefix(5) {
        state.players[0].settlements.insert(v)
    }
    // 5 settlements = 5 VP, not enough; add longest road + largest army bonuses to reach 10 for this test
    state.longestRoadPlayer = PlayerID(index: 0)
    state.largestArmyPlayer = PlayerID(index: 0)
    state.players[0].devCards = [.victoryPoint, .victoryPoint, .victoryPoint]
    WinCondition.checkForWinner(&state)
    if case .gameOver(let winner) = state.phase {
        #expect(winner == PlayerID(index: 0))
    } else {
        Issue.record("expected gameOver")
    }
}

@Test func belowTenVictoryPointsDoesNotEndGame() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    for v in state.board.onBoardVertices.sorted().prefix(4) {
        state.players[0].settlements.insert(v)
    }
    WinCondition.checkForWinner(&state)
    #expect(state.phase == .setupForward(playerIndex: 0))
}

@Test func victoryPointsMatchesGameStateComputation() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let vertices = state.board.onBoardVertices.sorted()
    state.players[0].settlements.insert(vertices[0])
    state.players[0].cities.insert(vertices[1])
    state.largestArmyPlayer = PlayerID(index: 0)
    #expect(WinCondition.victoryPoints(for: PlayerID(index: 0), in: state) == state.victoryPoints(for: PlayerID(index: 0)))
    #expect(WinCondition.victoryPoints(for: PlayerID(index: 0), in: state) == 5)
}

@Test func checkForWinnerIsNoOpOnceGameIsAlreadyOver() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .gameOver(winner: PlayerID(index: 2))
    state.players[0].devCards = [.victoryPoint, .victoryPoint, .victoryPoint, .victoryPoint, .victoryPoint,
                                  .victoryPoint, .victoryPoint, .victoryPoint, .victoryPoint, .victoryPoint]
    WinCondition.checkForWinner(&state)
    if case .gameOver(let winner) = state.phase {
        #expect(winner == PlayerID(index: 2))
    } else {
        Issue.record("expected gameOver to remain unchanged")
    }
}
