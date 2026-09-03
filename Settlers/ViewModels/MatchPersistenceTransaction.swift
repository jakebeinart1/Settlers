import Foundation
import CatanEngine

extension GameViewModel {
    /// New Game is one durable table switch. Recovery copies are completed
    /// before replacement, and ordinary legacy files remain untouched.
    func replaceActiveMatch(state: GameState, setup: MatchSetup, session: GameSession) throws {
        var match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        try match.attachSession(session.checkpoint)
        if savedGameAvailability.recoveryMessage != nil {
            let backup = try preserveRecoveryArtifacts(reason: savedGameAvailability.recoveryMessage!)
            if FileManager.default.fileExists(atPath: checkpointStore.fileURL.path) {
                let fresh = try checkpointDocument.map {
                    try MatchCheckpointDocument(recovering: $0, activeMatch: match)
                } ?? MatchCheckpointDocument(activeMatch: match)
                do {
                    try checkpointStore.replaceAfterRecovery(fresh, preservedOriginalAt: backup.appendingPathComponent("checkpoint.json"))
                } catch {
                    guard try checkpointStore.load() == fresh else { throw error }
                }
                checkpointDocument = fresh
                persistenceBlocked = false
                persistenceErrorMessage = nil
                gameLogWarning = "The unreadable checkpoint was backed up exactly. Its history and statistics could not be restored automatically."
                return
            }
        }
        if checkpointDocument == nil {
            try commitDocument(MatchCheckpointMigration.prepare(statistics: gameStatsStore))
        }
        guard let document = checkpointDocument else { preconditionFailure("checkpoint initialization did not produce a document") }
        let duration = max(document.activeMatch?.elapsedSeconds ?? 0, currentGameDuration)
        try commitDocument(document.recordingElapsedTime(duration))
        guard let timedDocument = checkpointDocument else { preconditionFailure("duration commit lost its document") }
        try commitDocument(timedDocument.replacingActiveMatch(with: match))
    }

    /// Raw source bytes, not decoded values: damaged bytes are what recovery
    /// needs. The completion marker is last, and any failure prevents replacement.
    @discardableResult
    func preserveRecoveryArtifacts(reason: String) throws -> URL {
        let directory = checkpointStore.fileURL.deletingLastPathComponent()
            .appendingPathComponent("Recovery").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try preserveFile(gameStore.fileURL, as: "save.json", in: directory)
        try preserveFile(civilizationStore.fileURL, as: "civilizations.json", in: directory)
        try preserveFile(checkpointStore.fileURL, as: "checkpoint.json", in: directory)
        try preserveFile(gameStatsStore.fileURL, as: "statistics.json", in: directory)
        try preserveFile(gameLogStore.activeGameIDURL, as: "active-game-id", in: directory)
        if let data = matchSetupStore.data(forActiveMatch: false) {
            try data.write(to: directory.appendingPathComponent("configured-match.json"), options: .atomic)
        }
        if let data = matchSetupStore.data(forActiveMatch: true) {
            try data.write(to: directory.appendingPathComponent("active-match.json"), options: .atomic)
        }
        try Data(String(humanSeatStore.load().index).utf8).write(
            to: directory.appendingPathComponent("legacy-human-seat.txt"), options: .atomic)
        try preserveRecordings(in: directory)
        try Data(reason.utf8).write(to: directory.appendingPathComponent("complete.txt"), options: .atomic)
        return directory
    }

    private func preserveFile(_ source: URL, as name: String, in directory: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: source) } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private func preserveRecordings(in archive: URL) throws {
        let files = try gameLogStore.logFiles()
        guard !files.isEmpty else { return }
        let directory = archive.appendingPathComponent("recordings")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files { try preserveFile(file, as: file.lastPathComponent, in: directory) }
    }
}
