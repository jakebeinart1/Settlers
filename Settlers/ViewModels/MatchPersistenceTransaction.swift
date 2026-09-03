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
            try write(match, configuredAs: setup)
            persistenceErrorMessage = nil
            return true
        } catch {
            rollback(snapshots, originalError: error)
            return false
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
        HumanSeatStore.shared.save(match.humanSeats.sorted().first!)
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
