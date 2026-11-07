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
        var match = MatchCheckpoint(
            id: UUID(), initialState: state, setup: sharedSetup(for: state),
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
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        state.phase = .gameOver(winner: PlayerID(index: 0))
        let setup = sharedSetup(for: state)
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
        let match = MatchCheckpoint(id: UUID(), initialState: state, setup: sharedSetup(for: state))
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
        var match = MatchCheckpoint(id: UUID(), initialState: state, setup: sharedSetup(for: state))
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

    @Test func privateExportRetiresLegacyPublicCopyOnlyAfterSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let publicDirectory = root.appendingPathComponent("documents")
        let privateDirectory = root.appendingPathComponent("support")
        let logs = GameLogStore(directoryURL: publicDirectory, maxKeptLogs: 2, privateDirectoryURL: privateDirectory)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let roster = sharedRoster(for: state)
        let id = try logs.startNewGame(initialState: state, roster: roster)
        let soloID = try logs.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
        let legacyURL = try #require(try logs.summary(for: id)?.fileURL)
        let legacyBytes = try Data(contentsOf: legacyURL)
        var match = MatchCheckpoint(id: id, initialState: state, setup: sharedSetup(for: state))
        match.recordAbandonment(at: Date())
        try Data("block private export".utf8).write(to: privateDirectory)
        #expect(throws: (any Error).self) { try logs.export(checkpoint: match) }
        #expect(try Data(contentsOf: legacyURL) == legacyBytes)

        try FileManager.default.removeItem(at: privateDirectory)
        let url = try logs.export(checkpoint: match)
        #expect(url.deletingLastPathComponent().path == privateDirectory.path)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(try logs.summary(for: id) == nil)
        #expect(try logs.summaries().map(\.gameID) == [soloID])
        let privateFiles = try FileManager.default.contentsOfDirectory(at: privateDirectory, includingPropertiesForKeys: nil)
        let quarantined = try #require(privateFiles.first { $0.pathExtension == "quarantined" })
        #expect(try Data(contentsOf: quarantined) == legacyBytes)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)],
                                              ofItemAtPath: url.path)
        let pruning = GameLogStore(directoryURL: publicDirectory, maxKeptLogs: 1, privateDirectoryURL: privateDirectory)
        try pruning.pruneExportedRecordings(protecting: [])
        #expect(try logs.detail(for: url).summary.gameID == id)
    }

    @Test(arguments: ["invalid JSONL line\n", "{\"kind\":"])
    func damagedPublicCopyIsQuarantinedWithItsBytesIntact(_ damagedSuffix: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let logs = GameLogStore(directoryURL: root, maxKeptLogs: 2)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let roster = sharedRoster(for: state)
        let id = try logs.startNewGame(initialState: state, roster: roster)
        let publicURL = try #require(try logs.summary(for: id)?.fileURL)
        let corrupt = try Data(contentsOf: publicURL) + Data(damagedSuffix.utf8)
        try corrupt.write(to: publicURL)
        let match = MatchCheckpoint(id: id, initialState: state, setup: sharedSetup(for: state))

        let privateURL = try logs.export(checkpoint: match)

        let privateFiles = try FileManager.default.contentsOfDirectory(
            at: privateURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let quarantine = try #require(privateFiles.first { $0.pathExtension == "quarantined" })
        #expect(!FileManager.default.fileExists(atPath: publicURL.path))
        #expect(try Data(contentsOf: quarantine) == corrupt)
        #expect(try logs.logFiles().isEmpty)
        #expect(try logs.detail(for: privateURL).summary.gameID == id)
    }

    @Test func incompleteRetryPreservesCompletedPublicArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let publicDirectory = root.appendingPathComponent("documents")
        let privateDirectory = root.appendingPathComponent("support")
        let logs = GameLogStore(directoryURL: publicDirectory, maxKeptLogs: 2, privateDirectoryURL: privateDirectory)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = sharedSetup(for: state)
        let id = UUID()
        let incomplete = MatchCheckpoint(id: id, initialState: state, setup: setup)
        let privateURL = try logs.export(checkpoint: incomplete)
        var finalState = state
        finalState.phase = .gameOver(winner: PlayerID(index: 0))
        let complete = MatchCheckpoint(id: id, initialState: finalState, setup: setup)
        try Data("block public export".utf8).write(to: publicDirectory)
        #expect(throws: (any Error).self) { try logs.export(checkpoint: complete) }
        #expect(FileManager.default.fileExists(atPath: privateURL.path))
        try FileManager.default.removeItem(at: publicDirectory)
        let completedURL = try logs.export(checkpoint: complete)
        let completedBytes = try Data(contentsOf: completedURL)
        #expect(!FileManager.default.fileExists(atPath: privateURL.path))

        #expect(try logs.export(checkpoint: incomplete) == privateURL)
        #expect(try Data(contentsOf: completedURL) == completedBytes)
        #expect(try logs.summary(for: id)?.isComplete == true)
        #expect(try logs.logFiles() == [completedURL])
        #expect(try logs.detail(for: privateURL).isComplete == false)
    }

    @Test func completedSharedExportWaitsForPrivateReceiptAcknowledgement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let logs = GameLogStore(directoryURL: root, maxKeptLogs: 2)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        state.phase = .gameOver(winner: PlayerID(index: 0))
        let match = MatchCheckpoint(id: UUID(), initialState: state, setup: sharedSetup(for: state))
        let held = try logs.export(checkpoint: match, holdingPrivateReceipt: true)
        #expect(try logs.summary(for: match.id) == nil)
        #expect(try logs.detail(for: held).isComplete)

        let released = try logs.export(checkpoint: match)
        #expect(try logs.logFiles() == [released])
        #expect(!FileManager.default.fileExists(atPath: held.path))

        // A previous build could have published this active result too early.
        let publishedBytes = try Data(contentsOf: released)
        #expect(try logs.export(checkpoint: match, holdingPrivateReceipt: true) == held)
        #expect(try logs.logFiles().isEmpty)
        let quarantines = try FileManager.default.contentsOfDirectory(
            at: held.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let earlyCopy = try #require(quarantines.first { $0.pathExtension == "quarantined" })
        #expect(try Data(contentsOf: earlyCopy) == publishedBytes)
    }

    @Test func migrationMovesOnlyKnownUnfinishedSharedOrphans() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let privateDirectory = root.appendingPathComponent("private")
        let logs = GameLogStore(directoryURL: root, maxKeptLogs: 8, privateDirectoryURL: privateDirectory)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let roster = sharedRoster(for: state)
        let orphan = try logs.startNewGame(initialState: state, roster: roster)
        let damaged = try logs.startNewGame(initialState: state, roster: roster)
        let finished = try logs.startNewGame(initialState: state, roster: roster)
        try logs.finalizeGame(gameID: finished, winner: PlayerID(index: 0))
        let solo = try logs.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
        let orphanURL = try #require(try logs.summary(for: orphan)?.fileURL)
        let damagedURL = try #require(try logs.summary(for: damaged)?.fileURL)
        let orphanBytes = try Data(contentsOf: orphanURL)
        let damagedBytes = try Data(contentsOf: damagedURL) + Data("bad line\n".utf8)
        try damagedBytes.write(to: damagedURL)
        let unknownURL = root.appendingPathComponent("\(UUID()).jsonl")
        try Data("no readable header".utf8).write(to: unknownURL)

        try logs.migrateLegacyUnfinishedSharedRecordings()
        try logs.migrateLegacyUnfinishedSharedRecordings()

        let privateFiles = try FileManager.default.contentsOfDirectory(at: privateDirectory, includingPropertiesForKeys: nil)
        let quarantined = try #require(privateFiles.first { $0.pathExtension == "quarantined" })
        #expect(privateFiles.filter { $0.pathExtension == "quarantined" }.count == 1)
        #expect(try Data(contentsOf: quarantined) == damagedBytes)
        #expect(try Data(contentsOf: privateDirectory.appendingPathComponent(orphanURL.lastPathComponent)) == orphanBytes)
        #expect(Set(try logs.summaries().map(\.gameID)) == [finished, solo])
        #expect(try Data(contentsOf: unknownURL) == Data("no readable header".utf8))
    }

    @Test func migrationCannotHideAConcurrentCompletedExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let logs = GameLogStore(directoryURL: root, maxKeptLogs: 2)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let roster = sharedRoster(for: state)
        let id = try logs.startNewGame(initialState: state, roster: roster)
        state.phase = .gameOver(winner: PlayerID(index: 0))
        let complete = MatchCheckpoint(id: id, initialState: state, setup: sharedSetup(for: state))
        async let migration: Void = try logs.migrateLegacyUnfinishedSharedRecordings()
        let completedURL = try logs.export(checkpoint: complete)
        try await migration

        #expect(try logs.summary(for: id)?.isComplete == true)
        #expect(try logs.logFiles() == [completedURL])
    }

    private func sharedRoster(for state: GameState) -> GameLogStore.SeatRoster {
        GameLogStore.SeatRoster(humanSeats: Set(state.players.map(\.id)), humanNames: [:],
                                botPersonalities: [:], civilizations: [:])
    }

    private func sharedSetup(for state: GameState) -> MatchSetup {
        MatchSetup(seats: state.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: true, name: "P\(player.id.index)",
                            civilization: Civilization.allCases[player.id.index])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
    }
}
