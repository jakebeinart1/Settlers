import Foundation

/// Running personal stats across every completed game - shown on
/// `MainMenuView`. A single small JSON value holding totals (not a
/// per-game record - that's `GameLogStore`'s job), so this file stays a
/// constant size no matter how many games get played.
public struct GameStats: Codable, Sendable, Equatable {
    public var gamesPlayed = 0
    public var gamesWon = 0
    public var totalFinalVP = 0
    public var totalDurationSeconds: Double = 0

    public init(gamesPlayed: Int = 0, gamesWon: Int = 0, totalFinalVP: Int = 0, totalDurationSeconds: Double = 0) {
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.totalFinalVP = totalFinalVP
        self.totalDurationSeconds = totalDurationSeconds
    }

    public var winRate: Double {
        gamesPlayed == 0 ? 0 : Double(gamesWon) / Double(gamesPlayed)
    }

    public var averageFinalVP: Double {
        gamesPlayed == 0 ? 0 : Double(totalFinalVP) / Double(gamesPlayed)
    }

    public var averageDurationSeconds: Double {
        gamesPlayed == 0 ? 0 : totalDurationSeconds / Double(gamesPlayed)
    }
}

public struct GameStatsStore: Sendable {
    public static let shared = GameStatsStore()

    private let fileURL: URL

    private init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = baseURL.appendingPathComponent("game_stats.json")
    }

    init(fileURL: URL) { self.fileURL = fileURL }

    /// The saved stats, or an empty `GameStats()` (zero games played) if
    /// none has been recorded yet or the file is missing/corrupt.
    public func load() -> GameStats {
        guard let data = try? Data(contentsOf: fileURL) else { return GameStats() }
        return (try? JSONDecoder().decode(GameStats.self, from: data)) ?? GameStats()
    }

    /// Migration must never turn corrupt historical totals into an empty
    /// baseline. Absence is zero; read/decode failures leave migration blocked.
    func loadForMigration() throws -> GameStats {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return GameStats()
        }
        let statistics = try JSONDecoder().decode(GameStats.self, from: data)
        guard statistics.gamesPlayed >= 0, statistics.gamesWon >= 0,
              statistics.gamesWon <= statistics.gamesPlayed, statistics.totalFinalVP >= 0,
              statistics.totalDurationSeconds.isFinite, statistics.totalDurationSeconds >= 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return statistics
    }

    /// Folds one finished game's outcome into the running totals and saves.
    /// Best-effort - swallows write errors, matching every other store in
    /// this file (a lost stats update should never surface as a gameplay
    /// failure).
    public func recordGameEnd(won: Bool, finalVP: Int, duration: TimeInterval) {
        var stats = load()
        stats.gamesPlayed += 1
        if won { stats.gamesWon += 1 }
        stats.totalFinalVP += finalVP
        stats.totalDurationSeconds += duration

        guard let data = try? JSONEncoder().encode(stats) else { return }
        let directoryURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Wipes all recorded stats back to zero - `SettingsView`'s "Reset
    /// Stats" action.
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
