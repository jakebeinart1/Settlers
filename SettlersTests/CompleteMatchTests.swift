import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@Suite struct CompleteMatchTests {
    @MainActor
    @Test func appDrivenCompleteMatchPersistsReplayableLogAndSoloStats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompleteMatchTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "CompleteMatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        let gameStore = GameStore(fileURL: root.appendingPathComponent("save.json"))
        let logStore = GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2)
        let statsStore = GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
        let model = GameViewModel(
            gameStore: gameStore,
            civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
            matchSetupStore: setupStore,
            gameLogStore: logStore,
            gameStatsStore: statsStore
        )
        let initialState = model.state

        model.qaPlayToEnd()

        guard case .gameOver(let winner) = model.state.phase else {
            Issue.record("complete-match path stopped before game over")
            return
        }
        let summaries = try logStore.summaries()
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        let detail = try logStore.detail(for: summary)
        #expect(summary.isComplete)
        #expect(summary.winner == winner)
        #expect(summary.moveCount > 100)
        #expect(try logStore.activeGameID() == nil)
        let stats = statsStore.load()
        #expect(stats.gamesPlayed == 1)
        #expect(stats.gamesWon == (winner == model.humanPlayer ? 1 : 0))
        #expect(stats.totalFinalVP == min(
            model.state.victoryPoints(for: model.humanPlayer), model.state.victoryPointTarget))
        #expect(stats.totalDurationSeconds.isFinite)
        #expect(stats.totalDurationSeconds > 0)

        var replay = initialState
        for event in detail.events {
            try RulesEngine.apply(event.move, by: event.player, to: &replay)
        }
        #expect(replay == model.state)
    }
}
