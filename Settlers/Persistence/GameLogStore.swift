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

    /// How many of the most recent games' logs to keep.
    ///
    /// Raised from 20 after measuring: a completed game's log is about 78 KB,
    /// so 500 games is under 40 MB - negligible next to the app's own asset
    /// catalogue, and 20 games is far too few to be worth training on or to
    /// investigate a bug reported a few days late.
    private let maxKeptLogs = 500

    private let directoryURL: URL

    private init() {
        // Documents, not Application Support, and deliberately so. Application
        // Support is invisible to the Files app and its container can only be
        // downloaded from a development-signed install - which means the
        // moment this ships to TestFlight, every game a tester plays becomes
        // unreachable, and testers are exactly the population whose games are
        // worth having. Documents plus `UIFileSharingEnabled` makes the logs
        // openable on the device itself, on any build.
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directoryURL = baseURL.appendingPathComponent("GameLogs")
    }

    /// Who was sitting in each seat, recorded once on the `start` line.
    ///
    /// Without this a log is an unlabelled sequence of moves: there is no way
    /// to tell a human's move from a bot's, or which bot personality produced
    /// which decision. Both are the whole premise of learning anything from
    /// the archive, and neither is recoverable after the fact - the human's
    /// seat lives in a single `UserDefaults` integer that the next new game
    /// overwrites.
    public struct SeatRoster: Codable, Sendable, Equatable {
        public let humanSeat: PlayerID
        /// Seat index -> personality name (`balanced` / `aggressive` /
        /// `cautious`), for the bot seats only.
        public let botPersonalities: [Int: String]
        /// Seat index -> civilization name, which drives the bot's voice.
        public let civilizations: [Int: String]

        public init(humanSeat: PlayerID, botPersonalities: [Int: String], civilizations: [Int: String]) {
            self.humanSeat = humanSeat
            self.botPersonalities = botPersonalities
            self.civilizations = civilizations
        }
    }

    private struct Entry: Codable {
        enum Kind: String, Codable { case start, move, end }
        let kind: Kind
        let timestamp: Date
        /// Wire-format version of the LOG, independent of `GameState`'s own
        /// `schemaVersion`. A reader has to be able to tell which shape it is
        /// looking at without decoding the payload first.
        var logSchemaVersion: Int?
        // `start` only:
        var initialState: GameState?
        var roster: SeatRoster?
        /// The app build that produced the log, so games recorded either side
        /// of an engine change are distinguishable rather than silently mixed.
        var appVersion: String?
        // `move` only:
        var player: PlayerID?
        var move: GameMove?
        // `end` only:
        var winner: PlayerID?
    }

    /// Current log wire-format version. Bump when `Entry`'s shape changes in a
    /// way a reader must branch on.
    public static let currentLogSchemaVersion = 1

    /// Starts a new log file for a fresh game and writes its `start` line.
    /// Returns the ID subsequent `appendMove`/`finalizeGame` calls this
    /// session should use. Best-effort: a failure to create the file still
    /// returns an ID (subsequent appends then also silently no-op) rather
    /// than making game creation itself fail over a logging problem.
    public func startNewGame(initialState: GameState, roster: SeatRoster) -> UUID {
        let id = UUID()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        // Prune on start as well as on finish. Pruning only in `finalizeGame`
        // meant an abandoned game never triggered it, so junk accumulated
        // until something actually finished.
        prune()
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let entry = Entry(
            kind: .start,
            timestamp: Date(),
            logSchemaVersion: Self.currentLogSchemaVersion,
            initialState: initialState,
            roster: roster,
            appVersion: version,
            player: nil, move: nil, winner: nil
        )
        write(entry, gameID: id)
        return id
    }

    /// Every log file on disk, newest first. The only read path into the
    /// archive - the store was previously write-only, which meant the logs it
    /// carefully accumulated could not be opened by anything.
    public func logFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { modified($0) > modified($1) }
    }

    /// The directory holding the logs, created if absent. Used by the export
    /// sheet in Settings.
    public func logDirectory() -> URL {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// Appends one applied move to `gameID`'s log file. Best-effort -
    /// swallows write errors, since a missing log entry should never block
    /// real gameplay.
    public func appendMove(gameID: UUID, player: PlayerID, move: GameMove) {
        let entry = Entry(kind: .move, timestamp: Date(), logSchemaVersion: nil,
                          initialState: nil, roster: nil, appVersion: nil,
                          player: player, move: move, winner: nil)
        write(entry, gameID: gameID)
    }

    /// Appends the game-over line for `gameID`, then prunes log files
    /// beyond the most recent `maxKeptLogs` (by file modification date).
    public func finalizeGame(gameID: UUID, winner: PlayerID) {
        let entry = Entry(kind: .end, timestamp: Date(), logSchemaVersion: nil,
                          initialState: nil, roster: nil, appVersion: nil,
                          player: nil, move: nil, winner: winner)
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

        let sorted = files.sorted { modified($0) > modified($1) }
        for stale in sorted.dropFirst(maxKeptLogs) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
