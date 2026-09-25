import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

/// Jake, 2026-09-25: "from the game over menu, the buttons do the same thing.
/// New game should be the same as restart game. Main menu should take you to
/// main menu." The screen's only button was titled New Game and cleared the
/// match back to the menu, so it never started a game.
@Suite(.serialized) struct GameOverActionsTests {

    @MainActor
    private func finishedGame(in root: URL, defaults: UserDefaults) -> GameViewModel {
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        let model = GameViewModel(
            gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
            civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
            matchSetupStore: setupStore,
            gameLogStore: GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 10),
            gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
        )
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .greece)
        setup.randomizeSeatOrder = false
        model.startNewGame(setup: setup)
        model.qaPlayToEnd()
        return model
    }

    @MainActor
    @Test func newGameRestartsTheFinishedTable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GameOverActions.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "GameOverActions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = finishedGame(in: root, defaults: defaults)
        guard case .gameOver = model.state.phase else {
            Issue.record("fixture did not reach game over")
            return
        }
        let finished = try #require(model.checkpointDocument?.activeMatch?.setup)
        let finishedLog = model.currentGameLogID

        #expect(model.restartCompletedMatch())

        guard case .setupForward = model.state.phase else {
            Issue.record("expected a fresh game, got \(model.state.phase)")
            return
        }
        let restarted = try #require(model.checkpointDocument?.activeMatch?.setup)
        #expect(restarted.seats.map(\.civilization) == finished.seats.map(\.civilization))
        #expect(restarted.seats.map(\.isHuman) == finished.seats.map(\.isHuman))
        #expect(model.currentGameLogID != finishedLog)
        #expect(model.statistics.gamesPlayed == 1, "the finished game's completion must survive the restart")
    }
}
