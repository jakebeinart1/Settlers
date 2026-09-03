import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor @Suite struct CheckpointExportTests {
    @Test func exportedSummaryUsesAuthoritativeForegroundDuration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let logs = GameLogStore(directoryURL: root, maxKeptLogs: 2)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 470)
        state.phase = .gameOver(winner: PlayerID(index: 0))
        let setup = MatchSetup(seats: state.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: true, name: "P\(player.id.index)",
                            civilization: Civilization.allCases[player.id.index])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
        var match = MatchCheckpoint(
            id: UUID(), initialState: state, setup: setup,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        try match.recordElapsedTime(42)

        let url = try logs.export(checkpoint: match)

        #expect(try logs.detail(for: url).summary.duration == 42)
    }

    @Test func retentionNeverEvictsProtectedRecordings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let logs = GameLogStore(directoryURL: root, maxKeptLogs: 1)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup(seats: state.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: true, name: "P\(player.id.index)",
                            civilization: Civilization.allCases[player.id.index])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
        var matches: [MatchCheckpoint] = []
        for index in 0..<3 {
            let match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
            let file = try logs.export(checkpoint: match)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))],
                                                  ofItemAtPath: file.path)
            matches.append(match)
        }
        try logs.pruneExportedRecordings(protecting: [matches[0].id])
        let kept = Set(try logs.summaries().map(\.gameID))
        #expect(kept == [matches[0].id, matches[2].id])
    }

    @Test func failedExportKeepsTheQueuedRecordingUntilAcknowledged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup(seats: state.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: true, name: "P\(player.id.index)",
                            civilization: Civilization.allCases[player.id.index])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
        let match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
        let initial = MatchCheckpointDocument(activeMatch: match)
        try store.commit(initial, replacingRevision: nil)
        let queued = try initial.replacingActiveMatch(with: nil)
        try store.commit(queued, replacingRevision: 0)
        let blockedPath = root.appendingPathComponent("not-a-directory")
        try Data("block export".utf8).write(to: blockedPath)
        let blockedLogs = GameLogStore(directoryURL: blockedPath, maxKeptLogs: 2)
        #expect(throws: (any Error).self) { try blockedLogs.export(checkpoint: match) }
        #expect(try store.load()?.pendingExports[match.id] == match)

        let logs = GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2)
        let url = try logs.export(checkpoint: match)
        let acknowledged = try queued.acknowledgingExport(of: match)
        try store.commit(acknowledged, replacingRevision: queued.revision)
        #expect(try store.load()?.pendingExports.isEmpty == true)
        #expect(try logs.detail(for: url).summary.gameID == match.id)
        #expect(throws: MatchCheckpointStore.StoreError.self) { try acknowledged.acknowledgingExport(of: match) }
    }

    @Test func retryReplacesATruncatedArchiveWithoutDuplicatingMoves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let logs = GameLogStore(directoryURL: root, maxKeptLogs: 2)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup(seats: state.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: true, name: "P\(player.id.index)",
                            civilization: Civilization.allCases[player.id.index])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
        var match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        let actor = PlayerID(index: 0)
        let move = try #require(RulesEngine.legalMoves(for: state, seat: actor).first)
        try match.apply(move, by: actor)
        let url = try logs.export(checkpoint: match)
        let original = try Data(contentsOf: url)
        try (original + Data("{\"kind\":".utf8)).write(to: url)

        #expect(try logs.export(checkpoint: match) == url)
        #expect(try Data(contentsOf: url) == original)
        let detail = try logs.detail(for: url)
        #expect(detail.summary.gameID == match.id)
        #expect(detail.events.count == 1)
        #expect(detail.events[0].move == move)
        #expect(detail.roster.humanNames[0] == "P0")
        #expect(!detail.isComplete)
        var replay = detail.initialState
        for event in detail.events { try RulesEngine.apply(event.move, by: event.player, to: &replay) }
        #expect(replay == match.state)
    }
}
