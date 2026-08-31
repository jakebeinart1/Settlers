import Foundation
import CatanEngine

/// Persists the *current game's* seat -> civilization assignment (one entry per
/// seat, in seat order) to disk as JSON, alongside `GameStore`'s save file. Written
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
    /// a missing/corrupt file or one whose entry count is not a table this app
    /// can seat - same "never crash app launch" contract as `GameStore.load()`.
    ///
    /// The bound was `== 4`, which predates three-player tables. A three-seat
    /// game writes three entries, so every relaunch rejected its own file and
    /// re-drew the lineup - and because the seat colour *is* the civilization's
    /// colour, the whole board changed colour on resume. Checked against
    /// `GameSetup.supportedPlayerCounts` rather than a fresh literal so a
    /// future table size cannot reintroduce it.
    public func load() -> [Civilization]? {
        guard let data = try? Data(contentsOf: fileURL),
              let assignment = try? JSONDecoder().decode([Civilization].self, from: data),
              GameSetup.supportedPlayerCounts.contains(assignment.count)
        else { return nil }
        return assignment
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
