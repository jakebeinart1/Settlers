import Foundation
import CatanEngine

/// Persists a single in-progress `GameState` to disk as JSON, under the app's
/// Application Support directory. Used to resume a game across app launches.
public struct GameStore: Sendable {
    public static let shared = GameStore()

    let fileURL: URL

    init(fileURL: URL? = nil) {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? baseURL.appendingPathComponent("catan_save.json")
    }

    /// What was on disk.
    ///
    /// `load()` used to return `GameState?`, which collapsed two very
    /// different situations into the same `nil`: "this player has never
    /// started a game" and "this player has a game in progress and we just
    /// failed to read it". The caller then did the same thing in both cases -
    /// silently start a fresh game - so a save the app could not decode
    /// vanished with no message at all. That is not hypothetical: before
    /// `GameState` gained a tolerant decoder, adding any non-optional field
    /// destroyed every save in the field, and nobody could have noticed from
    /// the app's behaviour.
    public enum LoadResult: Sendable {
        case none
        case loaded(GameState)
        /// A save file exists but could not be decoded. The file is left on
        /// disk so it can still be recovered or inspected.
        case unreadable
    }

    /// Encodes and writes `state` to disk, creating the containing directory if needed.
    /// Throws if the directory cannot be created, encoding fails, or the write fails.
    public func save(_ state: GameState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Reads the saved game, distinguishing "nothing saved" from "saved but
    /// unreadable". Never throws - a bad save must not stop the app launching.
    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: fileURL) else { return .none }
        guard let state = try? JSONDecoder().decode(GameState.self, from: data) else { return .unreadable }
        return .loaded(state)
    }

    /// Whether a save file exists at all, without decoding it.
    ///
    /// The main menu asks this on every render to decide whether to offer
    /// "Resume Game". It used to answer by running `load() != nil`, i.e. a
    /// full read and `JSONDecoder` pass over a 17-40 KB state, on the main
    /// thread, every time the menu's body was evaluated - to produce a boolean.
    public func hasSave() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Removes the save file, if present.
    public func clear() throws {
        guard hasSave() else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
