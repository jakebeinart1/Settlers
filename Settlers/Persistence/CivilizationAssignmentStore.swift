import Foundation

/// Persists the *current game's* seat -> civilization assignment (4 entries,
/// seat order) to disk as JSON, alongside `GameStore`'s save file. Written
/// once, when `GameViewModel.startNewGame` draws a fresh assignment; read
/// back on relaunch so a resumed game keeps the same bots instead of
/// re-randomizing them every launch. Cleared together with the save.
public struct CivilizationAssignmentStore: Sendable {
    public static let shared = CivilizationAssignmentStore()

    private let fileURL: URL

    private init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = baseURL.appendingPathComponent("catan_civilizations.json")
    }

    public func save(_ assignment: [Civilization]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(assignment)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Reads the saved assignment, if any. Returns `nil` (never throws) for
    /// a missing/corrupt file or one that doesn't have exactly 4 entries -
    /// same "never crash app launch" contract as `GameStore.load()`.
    public func load() -> [Civilization]? {
        guard let data = try? Data(contentsOf: fileURL),
              let assignment = try? JSONDecoder().decode([Civilization].self, from: data),
              assignment.count == 4
        else { return nil }
        return assignment
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
