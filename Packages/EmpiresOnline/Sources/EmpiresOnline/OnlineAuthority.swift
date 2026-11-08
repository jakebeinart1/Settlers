import CatanEngine
import Crypto
import Foundation

/// Owns every active match and serializes commands, deadlines and notifications
/// over a single durable writer. Neither player clients nor HTTP handlers can
/// supply their own seat, random seed, or clock.
public actor OnlineAuthority {
    let store: OnlineStore
    var database: OnlineDatabase
    let clock: @Sendable () -> Date

    public init(directory: URL, clock: @escaping @Sendable () -> Date = { Date() }) throws {
        let store = try OnlineStore(directory: directory)
        var database = try store.load()
        let now = clock()
        database.pauseDeadlinesForOutage(at: now)
        database.lastServiceAt = now
        try store.save(database)
        self.store = store
        self.database = database
        self.clock = clock
    }

    public func handle(_ request: OnlineRequest, bearer: String?) throws -> OnlineResponse {
        let date = clock()
        if case .createAccount(let name) = request {
            return try update(at: date) { try $0.createAccount(name: name) }
        }
        let account = try database.authenticate(bearer)
        switch request {
        case .profile:
            return .account(OnlineAccount(id: account, name: database.accounts[account]!.name, bearer: nil))
        case .list:
            return .games(database.games(for: account))
        case .view(let matchID):
            return .match(try database.view(matchID, for: account, at: date))
        default:
            return try update(at: date) { try $0.handleChange(request, account: account, at: date) }
        }
    }

    /// Work on a value copy until persistence succeeds. A failed write cannot
    /// publish a new revision, consume a receipt, or lose an owed alert.
    func update<Result>(
        at date: Date, _ change: (inout OnlineDatabase) throws -> Result
    ) throws -> Result {
        var next = database
        next.pauseDeadlinesForOutage(at: date)
        let result = try change(&next)
        next.lastServiceAt = date
        try store.save(next)
        database = next
        return result
    }
}

extension OnlineDatabase {
    mutating func createAccount(name: String) throws -> OnlineResponse {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...24).contains(trimmed.count), trimmed.utf8.count <= 96,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw OnlineError.invalidRequest
        }
        let id = UUID()
        let bearer = UUID().uuidString + UUID().uuidString
        accounts[id] = StoredOnlineAccount(name: trimmed, bearerDigest: Self.digest(bearer))
        return .account(OnlineAccount(id: id, name: trimmed, bearer: bearer))
    }

    func authenticate(_ bearer: String?) throws -> UUID {
        guard let bearer, bearer.utf8.count == 72 else { throw OnlineError.unauthorized }
        let digest = Self.digest(bearer)
        guard let account = accounts.first(where: { $0.value.bearerDigest == digest })?.key else {
            throw OnlineError.unauthorized
        }
        return account
    }

    private static func digest(_ bearer: String) -> String {
        Data(SHA256.hash(data: Data(bearer.utf8))).base64EncodedString()
    }

    func view(
        _ id: UUID, for account: UUID, at date: Date, acknowledgedCommandID: UUID? = nil
    ) throws -> OnlineMatchView {
        guard let room = rooms[id] else { throw OnlineError.notFound }
        let viewer = try room.seat(for: account)
        return OnlineMatchView(id: id, code: room.code, configuration: room.configuration,
            seats: room.seatsView(for: account, names: accounts), host: room.hostID == account,
            viewer: viewer, revision: room.revision, lobbyRevision: room.lobbyRevision, gameplay: room.gameplay?.view(for: viewer),
            pending: room.decisions.map(\.action), serverTime: date,
            isMuted: accounts[account]?.mutedRooms.contains(id) == true, status: room.status,
            acknowledgedCommandID: acknowledgedCommandID)
    }

    func games(for account: UUID) -> [OnlineGameSummary] {
        rooms.values.sorted { $0.createdAt > $1.createdAt }.compactMap { room in
            guard let seat = try? room.seat(for: account) else { return nil }
            let seats = room.seatsView(for: account, names: accounts)
            let turn = room.gameplay?.turnOwner
            return OnlineGameSummary(id: room.id, title: room.configuration.mode.displayName,
                status: room.status, pace: room.configuration.pace,
                needsYou: room.decisions.contains { $0.action.seat == seat },
                turnName: turn.flatMap { seats[$0.index].name })
        }
    }

    mutating func handleChange(
        _ request: OnlineRequest, account: UUID, at date: Date
    ) throws -> OnlineResponse {
        switch request {
        case .createRoom(let configuration, let civilization):
            return try createRoom(configuration, civilization: civilization, account: account, at: date)
        case .join(let code, let civilization):
            return try join(code: code, civilization: civilization, account: account, at: date)
        case .configure(let id, let configuration, let revision):
            return try configure(id, configuration: configuration, revision: revision, account: account, at: date)
        case .ready(let id, let ready, let revision):
            return try readyRoom(id, ready: ready, revision: revision, account: account, at: date)
        case .start(let id, let revision): return try startRoom(id, revision: revision, account: account, at: date)
        case .submit(let id, let command): return try submit(command, in: id, account: account, at: date)
        case .leave(let id): return try leave(id, account: account, at: date)
        case .deleteAccount: return try deleteAccount(account, at: date)
        case .mute(let id, let muted): return try mute(id, account: account, muted: muted, at: date)
        case .registerDevice(let installationID, let token, let environment):
            return try register(OnlineDevice(installationID: installationID, token: token, environment: environment),
                                for: account, at: date)
        case .unregisterDevice(let installationID):
            return unregister(installationID, for: account)
        default: throw OnlineError.invalidRequest
        }
    }
}

private extension OnlineDatabase {
    mutating func submit(
        _ command: OnlineCommand, in id: UUID, account: UUID, at date: Date
    ) throws -> OnlineResponse {
        guard var room = rooms[id] else { throw OnlineError.notFound }
        let seat = try room.seat(for: account)
        if let prior = room.receipts[command.id] {
            guard prior.accountID == account, prior.command == command else { throw OnlineError.conflict }
            return .match(try view(id, for: account, at: date, acknowledgedCommandID: command.id))
        }
        try room.apply(command, by: seat, at: date)
        room.receipts[command.id] = StoredOnlineCommand(accountID: account, command: command)
        setRoom(room, at: date)
        return .match(try view(id, for: account, at: date, acknowledgedCommandID: command.id))
    }
}

extension StoredOnlineRoom {
    mutating func apply(_ command: OnlineCommand, by seat: PlayerID, at date: Date) throws {
        guard status == .playing, var gameplay else { throw OnlineError.conflict }
        guard let pending = decisions.first(where: { $0.action.seat == seat })?.action else {
            throw OnlineError.forbidden
        }
        let independent = gameplay.acceptsIndependentResponses && command.revision < revision
        guard command.revision >= 0, command.revision == revision || independent,
              pending.id == command.decisionID, pending.deadline.map({ date < $0 }) ?? true else {
            throw OnlineError.conflict
        }
        do {
            try gameplay.apply(command.move, by: seat)
        } catch is OnlineGameplayError {
            throw OnlineError.invalidRequest
        }
        commit(gameplay, at: date)
    }

    mutating func commit(_ gameplay: OnlineGameplay, at date: Date) {
        self.gameplay = gameplay
        if gameplay.winner != nil { status = .finished }
        revision += 1
        reconcileDecisions(at: date)
    }
}
