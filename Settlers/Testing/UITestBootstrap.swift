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
        } catch {
            preconditionFailure("Could not reset UI-test persistence: \(error)")
        }
        GameStatsStore.shared.clear()
        clearGameLogs()
        PlayerNameStore.shared.save("UI Tester")
        #endif
    }

    #if DEBUG
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
