import Foundation

/// Process-level setup reserved for native UI tests.
///
///
/// UI tests run against the app's real container, so a previous test, manual
/// simulator session, or failed run can otherwise change which screen appears
/// at launch. Reset is a separate argument from `-ui-testing`: the cold-resume
/// test launches once with reset, then relaunches without it to prove the save
/// survives a genuine process boundary.
enum UITestBootstrap {
    static func resetPersistentStateIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        #if DEBUG
        guard arguments.contains("-ui-testing-reset") else { return }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        do {
            try GameStore.shared.clear()
            try CivilizationAssignmentStore.shared.clear()
            let checkpointURL = GameStore.shared.fileURL.deletingLastPathComponent()
                .appendingPathComponent("match_checkpoint.json")
            if FileManager.default.fileExists(atPath: checkpointURL.path) {
                try FileManager.default.removeItem(at: checkpointURL)
            }
        } catch {
            preconditionFailure("Could not reset UI-test persistence: \(error)")
        }
        GameStatsStore.shared.clear()
        clearGameLogs()
        // Ratings, per-game stats and locally trained ghosts outlived a reset
        // until 2026-09-25: a leaderboard test then saw a player with four
        // rated games where its fixture seeds three, and Expert's starting
        // 1229 would drift once any leftover game rated it. Specific paths
        // only - the ratings file shares Application Support with the rest.
        let ratings = RatingStore.shared.directory
        for url in [ratings.appendingPathComponent("ratings.json"), ratings.appendingPathComponent("ratings.corrupt.json"),
                    SeatStatsStore.shared.directory, GhostStore.shared.localDirectory] {
            removeIfPresent(url)
        }
        PlayerNameStore.shared.save("UI Tester")
        if arguments.contains("-ui-testing-corrupt-save") {
            writeCorruptSave()
        }
        #endif
    }

    #if DEBUG
    /// Only called behind reset, so a no-reset relaunch tests the existing
    /// unreadable file rather than silently replacing it with another fixture.
    private static func writeCorruptSave() {
        let fileURL = GameStore.shared.fileURL
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0xFF, 0xFE, 0x00]).write(to: fileURL, options: .atomic)
        } catch {
            preconditionFailure("Could not seed unreadable UI-test save: \(error)")
        }
    }

    private static func removeIfPresent(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch where (error as NSError).code == NSFileNoSuchFileError {
            // Nothing recorded yet.
        } catch {
            preconditionFailure("Could not reset UI-test ghost data at \(url.lastPathComponent): \(error)")
        }
    }

    private static func clearGameLogs() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logs = documents.appendingPathComponent("GameLogs", isDirectory: true)
        do {
            try FileManager.default.removeItem(at: logs)
        } catch where (error as NSError).code == NSFileNoSuchFileError {
            // A fresh test container has no archive yet.
        } catch {
            preconditionFailure("Could not reset UI-test game logs: \(error)")
        }
    }
    #endif
}
