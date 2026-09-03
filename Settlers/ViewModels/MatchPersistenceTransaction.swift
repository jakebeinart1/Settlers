import Foundation

private enum FileSnapshot {
    case absent
    case data(Data)
}

private struct MatchPersistenceSnapshots {
    let game: FileSnapshot
    let civilizations: FileSnapshot
    let prefill: Data?
    let active: Data?
}

extension GameViewModel {
    @discardableResult
    func persist(_ match: PreparedMatch, configuredAs setup: MatchSetup) -> Bool {
        let snapshots: MatchPersistenceSnapshots
        do {
            snapshots = try persistenceSnapshots()
        } catch {
            persistenceErrorMessage = "The existing save could not be read, so it was not replaced."
            return false
        }

        do {
            try preserveRecoverySnapshot(snapshots)
        } catch {
            persistenceErrorMessage = "A recovery copy could not be saved. Your original game was not replaced."
            return false
        }

        do {
            try write(match, configuredAs: setup)
            persistenceErrorMessage = nil
            return true
        } catch {
            rollback(snapshots, originalError: error)
            return false
        }
    }

    /// The legacy new-game entry point must obey the same preservation rule.
    func preserveRecoveryBeforeLegacyReplacement() -> Bool {
        guard savedGameAvailability.recoveryMessage != nil else { return true }
        do {
            try preserveRecoverySnapshot(persistenceSnapshots())
            return true
        } catch {
            persistenceErrorMessage = "A recovery copy could not be saved. Your original game was not replaced."
            return false
        }
    }

    /// Raw bytes, not decoded/re-encoded values: the damaged data is precisely
    /// what recovery needs. The completion note is written last. Any failure
    /// aborts replacement; an incomplete backup never licenses an overwrite.
    private func preserveRecoverySnapshot(_ snapshots: MatchPersistenceSnapshots) throws {
        guard let reason = savedGameAvailability.recoveryMessage else { return }
        let activeLog = try snapshot(of: gameLogStore.activeGameIDURL)
        let directory = gameStore.fileURL.deletingLastPathComponent()
            .appendingPathComponent("Recovery").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try restore(snapshots.game, to: directory.appendingPathComponent("save.json"))
        try restore(snapshots.civilizations, to: directory.appendingPathComponent("civilizations.json"))
        if let data = snapshots.prefill {
            try data.write(to: directory.appendingPathComponent("configured-match.json"), options: .atomic)
        }
        if let data = snapshots.active {
            try data.write(to: directory.appendingPathComponent("active-match.json"), options: .atomic)
        }
        try restore(activeLog, to: directory.appendingPathComponent("active-game-id"))
        try Data(String(humanSeatStore.load().index).utf8).write(
            to: directory.appendingPathComponent("legacy-human-seat.txt"), options: .atomic)
        try preserveRecordings(in: directory)
        try Data(reason.utf8).write(to: directory.appendingPathComponent("complete.txt"), options: .atomic)
    }

    /// Retention pruning may later evict the original log. Keep raw recordings
    /// beside the recovery state so its saved log pointer remains useful.
    private func preserveRecordings(in archive: URL) throws {
        let files = try gameLogStore.logFiles()
        guard !files.isEmpty else { return }
        let directory = archive.appendingPathComponent("recordings")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            try Data(contentsOf: file).write(
                to: directory.appendingPathComponent(file.lastPathComponent), options: .atomic)
        }
    }

    private func write(_ match: PreparedMatch, configuredAs setup: MatchSetup) throws {
        let realised = Self.realisedMatch(
            chairs: match.chairs,
            civilizations: match.civilizations,
            opponentProfiles: match.opponentProfiles,
            from: setup
        )
        try matchSetupStore.save(setup)
        try civilizationStore.save(match.civilizations)
        try matchSetupStore.saveActiveMatch(realised)
        try gameStore.save(match.state)
        humanSeatStore.save(match.humanSeats.sorted().first!)
    }

    private func persistenceSnapshots() throws -> MatchPersistenceSnapshots {
        MatchPersistenceSnapshots(
            game: try snapshot(of: gameStore.fileURL),
            civilizations: try snapshot(of: civilizationStore.fileURL),
            prefill: matchSetupStore.data(forActiveMatch: false),
            active: matchSetupStore.data(forActiveMatch: true)
        )
    }

    private func snapshot(of url: URL) throws -> FileSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        return .data(try Data(contentsOf: url))
    }

    private func rollback(_ snapshots: MatchPersistenceSnapshots, originalError: Error) {
        do {
            try restore(snapshots.game, to: gameStore.fileURL)
            try restore(snapshots.civilizations, to: civilizationStore.fileURL)
            matchSetupStore.restore(snapshots.prefill, forActiveMatch: false)
            matchSetupStore.restore(snapshots.active, forActiveMatch: true)
            persistenceErrorMessage = "The new game could not be saved. Your previous saved game is still available."
        } catch {
            persistenceErrorMessage = "The new game could not be saved, and the previous save could not be restored: "
                + "\(originalError.localizedDescription); \(error.localizedDescription)"
        }
    }

    private func restore(_ snapshot: FileSnapshot, to url: URL) throws {
        switch snapshot {
        case .data(let data):
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        case .absent:
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}
