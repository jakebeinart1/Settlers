import CatanEngine
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct OnlineStore {
    private let url: URL
    // Holding the descriptor excludes a second writer even after a crash/restart.
    private let lock: FileHandle

    init(directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let lockPath = directory.appendingPathComponent("authority.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw OnlineError.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw OnlineError.unavailable }
        lock = handle
        url = directory.appendingPathComponent("authority-v1.json")
    }

    func load() throws -> OnlineDatabase {
        guard FileManager.default.fileExists(atPath: url.path) else { return OnlineDatabase() }
        let database = try JSONDecoder().decode(OnlineDatabase.self, from: Data(contentsOf: url))
        guard database.version == OnlineDatabase.currentVersion else { throw OnlineError.unavailable }
        return database
    }

    /// An action and its alert outbox become durable together. Replacing a
    /// same-directory snapshot means a killed process leaves one complete revision.
    func save(_ database: OnlineDatabase) throws {
        let data = try JSONEncoder().encode(database)
        let staging = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        let descriptor = open(staging.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw OnlineError.unavailable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { _ = unlink(staging.path) }
        try file.write(contentsOf: data)
        try file.synchronize()
        try file.close()
        guard rename(staging.path, url.path) == 0 else { throw OnlineError.unavailable }
    }
}

struct OnlineDatabase: Codable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var accounts: [UUID: StoredOnlineAccount] = [:]
    var rooms: [UUID: StoredOnlineRoom] = [:]
    var outbox: [UUID: StoredOnlinePush] = [:]
    var lastServiceAt: Date?
}

struct StoredOnlineAccount: Codable, Sendable {
    let name: String
    let bearerDigest: String
    var devices: Set<OnlineDevice> = []
    var mutedRooms: Set<UUID> = []
}

struct OnlineDevice: Codable, Hashable, Sendable {
    let token: String
    let environment: OnlinePushEnvironment
}

struct StoredOnlinePush: Codable, Sendable {
    let id: UUID
    let accountID: UUID
    let matchID: UUID
    let decisionID: UUID
    let device: OnlineDevice
    var nextAttempt: Date
    var attempts = 0
    var expiresAt: Date
    var delivered = false

    var delivery: OnlinePush {
        OnlinePush(id: id, matchID: matchID, decisionID: decisionID, token: device.token,
                   environment: device.environment, expiresAt: expiresAt)
    }
}

struct StoredOnlineSeat: Codable, Sendable {
    var role: OnlineSeatRole
    var accountID: UUID?
    var civilization: String?
    var ready = false

    func view(for account: UUID, names: [UUID: StoredOnlineAccount]) -> OnlineSeat {
        let name: String?
        switch role {
        case .open: name = nil
        case .human: name = accountID.flatMap { names[$0]?.name } ?? "Former player"
        case .classicAI: name = "Classic AI"
        case .expertAI: name = "Expert AI"
        }
        return OnlineSeat(role: role, name: name, civilization: civilization,
                          ready: ready || role.isBot, isYou: accountID == account)
    }
}

struct StoredOnlineCommand: Codable, Sendable {
    let accountID: UUID
    let command: OnlineCommand
}

struct OnlineDecisionScope: Codable, Equatable, Sendable {
    let turn: Int
    let phase: String
}

struct StoredOnlineDecision: Codable, Sendable {
    let action: OnlinePendingAction
    let scope: OnlineDecisionScope
    let openedAt: Date

    func shiftingDeadline(by seconds: TimeInterval) -> StoredOnlineDecision {
        StoredOnlineDecision(action: OnlinePendingAction(id: action.id, seat: action.seat, kind: action.kind,
            deadline: action.deadline?.addingTimeInterval(seconds)), scope: scope, openedAt: openedAt)
    }
}

struct OnlineTurnClock: Codable, Sendable {
    let generation: Int
    var remaining: TimeInterval
    var resumedAt: Date?

    mutating func pause(at date: Date) {
        guard let resumedAt else { return }
        remaining = max(0, remaining - max(0, date.timeIntervalSince(resumedAt)))
        self.resumedAt = nil
    }
}

struct StoredOnlineRoom: Codable, Sendable {
    let id: UUID
    let code: String
    let createdAt: Date
    var hostID: UUID?
    var configuration: OnlineConfiguration
    var seats: [StoredOnlineSeat]
    var status: OnlineMatchStatus = .lobby
    var revision = 0
    var lobbyRevision = 0
    var gameplay: OnlineGameplay?
    var decisions: [StoredOnlineDecision] = []
    var receipts: [UUID: StoredOnlineCommand] = [:]
    var turnClock: OnlineTurnClock?

    func seat(for account: UUID) throws -> PlayerID {
        guard let index = seats.firstIndex(where: { $0.accountID == account }) else {
            throw OnlineError.notFound
        }
        return PlayerID(index: index)
    }

    func seatsView(for account: UUID, names: [UUID: StoredOnlineAccount]) -> [OnlineSeat] {
        seats.map { $0.view(for: account, names: names) }
    }

    mutating func reconcileDecisions(at date: Date) {
        guard let gameplay, gameplay.winner == nil, status == .playing else {
            decisions = []
            turnClock = nil
            return
        }
        let kind = gameplay.deadlineKind
        let scope = OnlineDecisionScope(turn: gameplay.turnGeneration, phase: gameplay.actionScope)
        let deadline = nextDeadline(kind: kind, generation: scope.turn, at: date)
        decisions = gameplay.actors.map { seat in
            if let pending = decisions.first(where: { $0.scope == scope && $0.action.seat == seat }) {
                return pending
            }
            let action = OnlinePendingAction(id: UUID(), seat: seat, kind: kind, deadline: deadline)
            return StoredOnlineDecision(action: action, scope: scope, openedAt: date)
        }
    }

    private mutating func nextDeadline(
        kind: OnlineDeadlineKind, generation: Int, at date: Date
    ) -> Date? {
        if turnClock?.generation != generation { turnClock = nil }
        guard kind == .turn, let turnSeconds = kind.seconds(in: configuration.pace) else {
            turnClock?.pause(at: date)
            return kind.seconds(in: configuration.pace).map { date.addingTimeInterval($0) }
        }
        var clock = turnClock ?? OnlineTurnClock(generation: generation, remaining: turnSeconds)
        if clock.resumedAt == nil { clock.resumedAt = date }
        turnClock = clock
        return clock.resumedAt?.addingTimeInterval(clock.remaining)
    }
}
