import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor @Suite struct CheckpointMigrationTests {
    @Test func migrationPreservesLegacyStatisticsAndOriginalFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let statsURL = root.appendingPathComponent("stats.json")
        let baseline = GameStats(gamesPlayed: 7, gamesWon: 3, totalFinalVP: 61, totalDurationSeconds: 900)
        let bytes = try JSONEncoder().encode(baseline)
        try bytes.write(to: statsURL)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        let session = GameSession(state: state, policies: [:], policySeed: 99)
        let document = try MatchCheckpointMigration.prepare(
            session: session.checkpoint, setup: setup,
            statistics: GameStatsStore(fileURL: statsURL), activeLog: nil)
        #expect(document.statistics == baseline)
        #expect(document.activeMatch?.state == state)
        #expect(try Data(contentsOf: statsURL) == bytes)
    }

    @Test func corruptStatisticsBlockMigrationWithoutOverwritingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("stats.json")
        let corrupt = Data("damaged statistics".utf8)
        try corrupt.write(to: url)
        #expect(throws: (any Error).self) { _ = try GameStatsStore(fileURL: url).loadForMigration() }
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func aLogAheadOfTheSaveBlocksMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let logs = GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2)
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let actor = PlayerID(index: 0)
        let id = try logs.startNewGame(initialState: initial, roster: .legacy(humanSeat: actor))
        let move = try #require(RulesEngine.legalMoves(for: initial, seat: actor).first)
        try logs.appendMove(gameID: id, player: actor, move: move)
        let file = try #require(try logs.logFiles().first)
        let originalBytes = try Data(contentsOf: file)
        let log = try logs.detail(for: file)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        let oldSession = GameSession(state: initial, policies: [:], policySeed: 99)

        #expect(throws: MatchCheckpointMigration.MigrationError.historyMismatch) {
            try MatchCheckpointMigration.prepare(session: oldSession.checkpoint, setup: setup,
                                                statistics: GameStatsStore(fileURL: root.appendingPathComponent("stats.json")),
                                                activeLog: log)
        }
        #expect(try Data(contentsOf: file) == originalBytes)
    }
}
