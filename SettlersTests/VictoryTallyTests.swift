import Testing
@testable import CatanEngine
@testable import Settlers

@Suite struct VictoryTallyTests {
    /// The counter must land exactly on the score the results screen shows.
    @Test func beatsSumToTheEngineScoreWithEveryBonus() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let winner = PlayerID(index: 2)
        let vertices = state.board.onBoardVertices.sorted()
        let index = try #require(state.players.firstIndex { $0.id == winner })
        state.players[index].settlements = [vertices[0], vertices[10]]
        state.players[index].cities = [vertices[20], vertices[30]]
        state.players[index].roads = Set(state.board.onBoardEdges.sorted().prefix(5))
        state.players[index].devCards = [.victoryPoint, .knight, .victoryPoint]
        state.longestRoadPlayer = winner
        state.largestArmyPlayer = winner
        state.phase = .gameOver(winner: winner)

        let tally = try #require(VictoryTally(state: state))
        #expect(tally.total == state.victoryPoints(for: winner))
        #expect(tally.total == 2 + 4 + 2 + 2 + 2)
        #expect(tally.beats.first?.source == .settlement(vertices[0]))
        #expect(tally.beats.last?.source == .victoryCards(2))
    }

    @Test func noTallyBeforeTheGameEnds() {
        #expect(VictoryTally(state: GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)) == nil)
    }
}
