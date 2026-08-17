import Foundation
import CatanEngine

/// Persists a durable, replayable record of each game to disk as it's
/// played - unlike `GameStore` (a single in-progress save, overwritten
/// every move and cleared on completion), every finished game leaves a
/// standalone file behind under Application Support/GameLogs/. `GameState`
/// and `GameMove` are already `Codable`, so a log is exactly what it takes
/// to replay a game: the initial state plus its ordered move list - no
/// separate reconstruction logic needed.
///
/// One JSON-Lines file per game (`<gameID>.jsonl`): each line is an
/// independently-decodable `Entry`, so a log cut short by a crash mid-game
/// is still readable up to its last complete line, unlike a single JSON
/// array that would be corrupted by a truncated write.
public struct GameLogStore: Sendable {
    public static let shared = GameLogStore()

    /// How many of the most recent games' logs to keep - older ones are
    /// pruned in `finalizeGame` so this directory doesn't grow forever.
    private let maxKeptLogs = 20

    private let directoryURL: URL

    private init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = baseURL.appendingPathComponent("GameLogs")
    }

    private struct Entry: Codable {
        enum Kind: String, Codable { case start, move, end }
        let kind: Kind
        let timestamp: Date
        // `start` only:
        var initialState: GameState?
        // `move` only:
        var player: PlayerID?
        var move: GameMove?
        // `end` only:
        var winner: PlayerID?
    }

    /// Starts a new log file for a fresh game and writes its `start` line.
    /// Returns the ID subsequent `appendMove`/`finalizeGame` calls this
    /// session should use. Best-effort: a failure to create the file still
    /// returns an ID (subsequent appends then also silently no-op) rather
    /// than making game creation itself fail over a logging problem.
    public func startNewGame(initialState: GameState) -> UUID {
        let id = UUID()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let entry = Entry(kind: .start, timestamp: Date(), initialState: initialState, player: nil, move: nil, winner: nil)
        write(entry, gameID: id)
        return id
    }

    /// Appends one applied move to `gameID`'s log file. Best-effort -
    /// swallows write errors, since a missing log entry should never block
    /// real gameplay.
    public func appendMove(gameID: UUID, player: PlayerID, move: GameMove) {
        let entry = Entry(kind: .move, timestamp: Date(), initialState: nil, player: player, move: move, winner: nil)
        write(entry, gameID: gameID)
    }

    /// Appends the game-over line for `gameID`, then prunes log files
    /// beyond the most recent `maxKeptLogs` (by file modification date).
    public func finalizeGame(gameID: UUID, winner: PlayerID) {
        let entry = Entry(kind: .end, timestamp: Date(), initialState: nil, player: nil, move: nil, winner: winner)
        write(entry, gameID: gameID)
        prune()
    }

    private func fileURL(for gameID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(gameID.uuidString).jsonl")
    }

    private func write(_ entry: Entry, gameID: UUID) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let url = fileURL(for: gameID)
        let line = data + Data("\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line)
        } else {
            try? line.write(to: url)
        }
    }

    /// Deletes the oldest log files beyond `maxKeptLogs`, ranked by file
    /// modification date (a game still being appended to is always its
    /// file's most recent write, so a finished game never prunes itself).
    private func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let sorted = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }
        for stale in sorted.dropFirst(maxKeptLogs) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
