import Foundation
import CatanEngine

/// A compact row in the in-app archive. The URL remains attached so opening a
/// row and sharing its source file are both direct operations.
public struct GameLogSummary: Identifiable, Sendable, Equatable {
    public var id: UUID { gameID }
    public let gameID: UUID
    public let fileURL: URL
    public let startedAt: Date
    public let duration: TimeInterval
    public let playerCount: Int
    public let victoryPointTarget: Int
    public let humanSeats: Set<PlayerID>
    public let winner: PlayerID?
    public let moveCount: Int
    public let civilizations: [Int: String]
    public let isComplete: Bool
}

public struct GameLogEvent: Sendable, Equatable {
    public let timestamp: Date
    public let player: PlayerID
    public let move: GameMove
}

public struct GameLogDetail: Sendable, Equatable {
    public let initialState: GameState
    public let summary: GameLogSummary
    public let roster: GameLogStore.SeatRoster
    public let events: [GameLogEvent]
    public var isComplete: Bool { summary.isComplete }
}

public struct GameLogScan: Sendable, Equatable {
    public struct Failure: Identifiable, Sendable, Equatable {
        public var id: URL { fileURL }
        public let fileURL: URL
        public let message: String
    }

    public let summaries: [GameLogSummary]
    public let failures: [Failure]
}

/// Durable JSONL game archive stored in Documents so TestFlight players can
/// inspect and export it without a development-signed container download.
public struct GameLogStore: Sendable {
    public static let shared = GameLogStore()
    public static let currentLogSchemaVersion = 4

    private let directoryURL: URL
    private let maxKeptLogs: Int

    private init() {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(directoryURL: baseURL.appendingPathComponent("GameLogs"), maxKeptLogs: 500)
    }

    /// Injectable archive location keeps tests away from the simulator's real
    /// logs. The retention limit is injectable so pruning can be tested cheaply.
    init(directoryURL: URL, maxKeptLogs: Int) {
        precondition(maxKeptLogs > 0)
        self.directoryURL = directoryURL
        self.maxKeptLogs = maxKeptLogs
    }

    public enum ReadError: Error, Equatable, LocalizedError {
        case unreadableFile(String)
        case malformedLine(file: String, line: Int)
        case missingStart(String)
        case invalidFileName(String)

        public var errorDescription: String? {
            switch self {
            case .unreadableFile(let file): return "Could not read \(file)."
            case .malformedLine(let file, let line): return "\(file) has invalid data on line \(line)."
            case .missingStart(let file): return "\(file) has no readable starting position."
            case .invalidFileName(let file): return "\(file) does not have a valid game identifier."
            }
        }
    }

    public enum IOError: Error, LocalizedError {
        case operation(String, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .operation(let context, let error): return "\(context): \(error.localizedDescription)"
            }
        }
    }

    /// Who occupied each seat. `humanSeat` remains on the wire for old readers;
    /// `humanSeats` is the v2 truth that can represent hot-seat games.
    public struct SeatRoster: Codable, Sendable, Equatable {
        public let humanSeats: Set<PlayerID>
        public let humanNames: [Int: String]
        public let botProfiles: [Int: String]
        public let botProfileNames: [Int: String]
        public let botPersonalities: [Int: String]
        public let civilizations: [Int: String]

        public init(humanSeats: Set<PlayerID>, humanNames: [Int: String],
                    botProfiles: [Int: String] = [:],
                    botProfileNames: [Int: String] = [:],
                    botPersonalities: [Int: String], civilizations: [Int: String]) {
            precondition(!humanSeats.isEmpty, "a logged game must contain at least one human seat")
            self.humanSeats = humanSeats
            self.humanNames = humanNames
            self.botProfiles = botProfiles
            self.botProfileNames = botProfileNames
            self.botPersonalities = botPersonalities
            self.civilizations = civilizations
        }

        public static func legacy(humanSeat: PlayerID) -> SeatRoster {
            SeatRoster(humanSeats: [humanSeat], humanNames: [:],
                       botProfiles: [:], botProfileNames: [:],
                       botPersonalities: [:], civilizations: [:])
        }

        private enum CodingKeys: String, CodingKey {
            case humanSeat, humanSeats, humanNames, botProfiles, botProfileNames
            case botPersonalities, civilizations
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let seats = try values.decodeIfPresent(Set<PlayerID>.self, forKey: .humanSeats) {
                humanSeats = seats
            } else {
                humanSeats = [try values.decode(PlayerID.self, forKey: .humanSeat)]
            }
            humanNames = try values.decodeIfPresent([Int: String].self, forKey: .humanNames) ?? [:]
            botProfiles = try values.decodeIfPresent([Int: String].self, forKey: .botProfiles) ?? [:]
            botProfileNames = try values.decodeIfPresent([Int: String].self, forKey: .botProfileNames) ?? [:]
            botPersonalities = try values.decode([Int: String].self, forKey: .botPersonalities)
            civilizations = try values.decode([Int: String].self, forKey: .civilizations)
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            let first = humanSeats.min { $0.index < $1.index }
            try values.encode(first, forKey: .humanSeat)
            try values.encode(humanSeats, forKey: .humanSeats)
            try values.encode(humanNames, forKey: .humanNames)
            try values.encode(botProfiles, forKey: .botProfiles)
            try values.encode(botProfileNames, forKey: .botProfileNames)
            try values.encode(botPersonalities, forKey: .botPersonalities)
            try values.encode(civilizations, forKey: .civilizations)
        }
    }

    private struct Entry: Codable {
        enum Kind: String, Codable { case start, move, end }
        let kind: Kind
        let timestamp: Date
        var logSchemaVersion: Int?
        var initialState: GameState?
        var roster: SeatRoster?
        var appVersion: String?
        var player: PlayerID?
        var move: GameMove?
        var winner: PlayerID?
        var elapsedSeconds: TimeInterval?
    }

    public func startNewGame(initialState: GameState, roster: SeatRoster) throws -> UUID {
        let id = UUID()
        try createLogDirectory()
        let entry = Entry(
            kind: .start, timestamp: Date(),
            logSchemaVersion: Self.currentLogSchemaVersion,
            initialState: initialState, roster: roster,
            appVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            player: nil, move: nil, winner: nil)
        try write(entry, gameID: id)
        try setActiveGameID(id)
        try prune()
        return id
    }

    public func appendMove(gameID: UUID, player: PlayerID, move: GameMove) throws {
        try write(Entry(kind: .move, timestamp: Date(), logSchemaVersion: nil,
                    initialState: nil, roster: nil, appVersion: nil,
                    player: player, move: move, winner: nil), gameID: gameID)
    }

    public func finalizeGame(gameID: UUID, winner: PlayerID) throws {
        try write(Entry(kind: .end, timestamp: Date(), logSchemaVersion: nil,
                    initialState: nil, roster: nil, appVersion: nil,
                    player: nil, move: nil, winner: winner), gameID: gameID)
        if try activeGameID() == gameID { try setActiveGameID(nil) }
        try prune()
    }

    /// JSONL is a derived view of committed history. Replace the entire stable
    /// match-ID file atomically: retries cannot duplicate moves or append after
    /// a partial trailing line. Retention runs separately after acknowledgement.
    func export(checkpoint: MatchCheckpoint) throws -> URL {
        try checkpoint.validateHistory()
        let roster = try exportRoster(for: checkpoint.setup)
        var entries = [Entry(kind: .start, timestamp: checkpoint.startedAt,
                             logSchemaVersion: Self.currentLogSchemaVersion,
                             initialState: checkpoint.initialState, roster: roster,
                             elapsedSeconds: checkpoint.elapsedSeconds)]
        entries += checkpoint.moves.map {
            Entry(kind: .move, timestamp: $0.timestamp, player: $0.actor, move: $0.move)
        }
        if case .gameOver(let winner) = checkpoint.state.phase {
            entries.append(Entry(kind: .end,
                                 timestamp: checkpoint.moves.last?.timestamp ?? checkpoint.startedAt,
                                 winner: winner))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for entry in entries { data.append(try encoder.encode(entry)); data.append(0x0A) }
        try createLogDirectory()
        let url = fileURL(for: checkpoint.id)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func exportRoster(for setup: MatchSetup) throws -> SeatRoster {
        guard setup.isStartable, setup.seats.allSatisfy({ $0.civilization != nil }),
              setup.aiSeats.allSatisfy({ $0.opponentProfile?.civilization == $0.civilization }) else {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
        return SeatRoster(
            humanSeats: Set(setup.humanSeats.map { PlayerID(index: $0.index) }),
            humanNames: Dictionary(uniqueKeysWithValues: setup.humanSeats.map { ($0.index, $0.name) }),
            botProfiles: Dictionary(uniqueKeysWithValues: setup.aiSeats.compactMap { seat in
                seat.opponentProfile.map { (seat.index, $0.id) }
            }),
            botProfileNames: Dictionary(uniqueKeysWithValues: setup.aiSeats.compactMap { seat in
                seat.opponentProfile.map { (seat.index, $0.name) }
            }),
            botPersonalities: Dictionary(uniqueKeysWithValues: setup.aiSeats.compactMap { seat in
                seat.opponentProfile.map { (seat.index, $0.strategy.rawValue) }
            }),
            civilizations: Dictionary(uniqueKeysWithValues: setup.seats.compactMap { seat in
                seat.civilization.map { (seat.index, $0.displayName) }
            }))
    }

    public func logFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey])
            return try files.filter { $0.pathExtension == "jsonl" }
                .map { ($0, try modified($0)) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        } catch {
            throw ioError("Could not enumerate game logs", error)
        }
    }

    public func logDirectory() throws -> URL {
        try createLogDirectory()
        return directoryURL
    }

    public func summaries() throws -> [GameLogSummary] {
        try scan().summaries
    }

    public func scan() throws -> GameLogScan {
        var summaries: [GameLogSummary] = []
        var failures: [GameLogScan.Failure] = []
        for file in try logFiles() {
            do {
                summaries.append(try detail(for: file).summary)
            } catch {
                failures.append(.init(fileURL: file, message: error.localizedDescription))
            }
        }
        return GameLogScan(summaries: summaries, failures: failures)
    }

    public func activeGameID() throws -> UUID? {
        let url = activeGameIDURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let value = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = UUID(uuidString: value) else {
                throw ReadError.invalidFileName(url.lastPathComponent)
            }
            return id
        } catch {
            if error is ReadError { throw error }
            throw ioError("Could not read active game-log identifier", error)
        }
    }

    public func abandonActiveGame() throws { try setActiveGameID(nil) }

    public func detail(for summary: GameLogSummary) throws -> GameLogDetail {
        try detail(for: summary.fileURL)
    }

    public func detail(for fileURL: URL) throws -> GameLogDetail {
        let parsed = try entries(in: fileURL)
        guard let start = parsed.entries.first(where: { $0.kind == .start }),
              let initialState = start.initialState,
              let roster = start.roster
        else { throw ReadError.missingStart(fileURL.lastPathComponent) }
        guard let gameID = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent)
        else { throw ReadError.invalidFileName(fileURL.lastPathComponent) }

        let moves = parsed.entries.compactMap { entry -> GameLogEvent? in
            guard entry.kind == .move, let player = entry.player, let move = entry.move else { return nil }
            return GameLogEvent(timestamp: entry.timestamp, player: player, move: move)
        }
        let end = parsed.entries.last(where: { $0.kind == .end })
        let lastTimestamp = end?.timestamp ?? moves.last?.timestamp ?? start.timestamp
        let duration = start.elapsedSeconds ?? max(0, lastTimestamp.timeIntervalSince(start.timestamp))
        let summary = GameLogSummary(
            gameID: gameID, fileURL: fileURL, startedAt: start.timestamp,
            duration: duration,
            playerCount: initialState.players.count,
            victoryPointTarget: initialState.victoryPointTarget,
            humanSeats: roster.humanSeats, winner: end?.winner,
            moveCount: moves.count, civilizations: roster.civilizations,
            isComplete: end != nil && !parsed.ignoredTruncatedLine)
        return GameLogDetail(initialState: initialState, summary: summary, roster: roster, events: moves)
    }

    private func entries(in fileURL: URL) throws -> (entries: [Entry], ignoredTruncatedLine: Bool) {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ReadError.unreadableFile(fileURL.lastPathComponent)
        }
        let parts = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        var entries: [Entry] = []
        var ignoredTruncatedLine = false
        for (offset, part) in parts.enumerated() where !part.isEmpty {
            do {
                entries.append(try JSONDecoder().decode(Entry.self, from: Data(part)))
            } catch {
                if offset == parts.count - 1 && data.last != 0x0A {
                    ignoredTruncatedLine = true
                    break
                }
                throw ReadError.malformedLine(file: fileURL.lastPathComponent, line: offset + 1)
            }
        }
        return (entries, ignoredTruncatedLine)
    }

    private func fileURL(for gameID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(gameID.uuidString).jsonl")
    }

    var activeGameIDURL: URL { directoryURL.appendingPathComponent("active-game-id") }

    private func write(_ entry: Entry, gameID: UUID) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(entry)
        } catch {
            throw ioError("Could not encode game log \(gameID)", error)
        }
        let url = fileURL(for: gameID)
        let line = data + Data("\n".utf8)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: url, options: .atomic)
            }
        } catch {
            throw ioError("Could not write game log \(url.lastPathComponent)", error)
        }
    }

    private func prune() throws {
        try pruneExportedRecordings(protecting: [])
    }

    /// Keep pending/active exports regardless of age. The retention allowance
    /// applies to additional unprotected recordings, so a backlog can exceed
    /// it without losing history that has not been acknowledged durably.
    func pruneExportedRecordings(protecting protectedIDs: Set<UUID>) throws {
        let files = try logFiles().filter { file in
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return false }
            return !protectedIDs.contains(id)
        }
        for stale in files.dropFirst(maxKeptLogs) {
            do {
                try FileManager.default.removeItem(at: stale)
            } catch {
                throw ioError("Could not prune game log \(stale.lastPathComponent)", error)
            }
        }
    }

    private func modified(_ url: URL) throws -> Date {
        do {
            return try url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? .distantPast
        } catch {
            throw ioError("Could not read metadata for \(url.lastPathComponent)", error)
        }
    }

    private func createLogDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw ioError("Could not create game-log directory", error)
        }
    }

    private func setActiveGameID(_ gameID: UUID?) throws {
        do {
            if let gameID {
                try createLogDirectory()
                try Data(gameID.uuidString.utf8).write(to: activeGameIDURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: activeGameIDURL.path) {
                try FileManager.default.removeItem(at: activeGameIDURL)
            }
        } catch {
            throw ioError("Could not update active game-log identifier", error)
        }
    }

    private func ioError(_ context: String, _ error: Error) -> IOError {
        .operation(context, underlying: error)
    }
}
