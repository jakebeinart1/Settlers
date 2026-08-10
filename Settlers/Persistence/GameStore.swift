import Foundation
import CatanEngine

/// Persists a single in-progress `GameState` to disk as JSON, under the app's
/// Application Support directory. Used to resume a game across app launches.
public struct GameStore: Sendable {
    public static let shared = GameStore()

    private let fileURL: URL

    private init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = baseURL.appendingPathComponent("catan_save.json")
    }

    /// Encodes and writes `state` to disk, creating the containing directory if needed.
    /// Throws if the directory cannot be created, encoding fails, or the write fails.
    public func save(_ state: GameState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Reads and decodes the saved `GameState`, if any. Returns `nil` (never throws)
    /// when there is no save file or it fails to decode — a missing or corrupt/outdated
    /// save should never crash app launch.
    public func load() -> GameState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: data)
    }

    /// Removes the save file, if present.
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
