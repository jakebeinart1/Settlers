import CatanEngine
import Foundation

extension OnlineAuthority {
    /// The host runs this on its own interval. A client's polls and connection
    /// state never determine whether a bot can play or a deadline expires.
    public func tick() throws {
        let now = clock()
        guard database.shouldTick(at: now) else { return }
        let blockedRoom = try update(at: now) { $0.advance(at: now) }
        if blockedRoom { throw OnlineError.unavailable }
    }

    public func pendingPushes() -> [OnlinePush] {
        let now = clock()
        let database = database
        return database.outbox.values.lazy
            .filter { !$0.delivered && $0.nextAttempt <= now && $0.expiresAt > now && database.canDeliver($0)
                && database.accounts[$0.accountID]?.mutedRooms.contains($0.matchID) != true }
            .sorted { $0.nextAttempt < $1.nextAttempt }
            .prefix(32)
            .map(\.delivery)
    }

    public func resolvePush(id: UUID, result: OnlinePushResult) throws {
        guard database.outbox[id] != nil else { return }
        let date = clock()
        try update(at: date) { $0.resolvePush(id: id, result: result, at: date) }
    }
}

extension OnlineDatabase {
    private static let heartbeatInterval: TimeInterval = 10
    private static let outageThreshold: TimeInterval = 20
    private static let alertLifetime: TimeInterval = 12 * 60 * 60

    func shouldTick(at date: Date) -> Bool {
        guard let lastServiceAt, date.timeIntervalSince(lastServiceAt) < Self.heartbeatInterval else {
            return true
        }
        return rooms.values.contains { $0.isLobbyExpired(at: date) || $0.nextScheduledDecision(at: date) != nil }
    }

    mutating func pauseDeadlinesForOutage(at date: Date) {
        guard let lastServiceAt else { return }
        let gap = date.timeIntervalSince(lastServiceAt)
        guard gap > Self.outageThreshold else { return }
        for id in Array(rooms.keys) {
            guard var room = rooms[id], room.status == .playing else { continue }
            room.decisions = room.decisions.map { $0.shiftingDeadline(by: gap) }
            if let resumed = room.turnClock?.resumedAt {
                room.turnClock?.resumedAt = resumed.addingTimeInterval(gap)
            }
            rooms[id] = room
        }
        for (id, var push) in outbox {
            push.expiresAt = push.expiresAt.addingTimeInterval(gap)
            outbox[id] = push
        }
    }

    /// A failed room stays recoverable, but cannot roll back another room's
    /// committed progress. The caller surfaces scheduler degradation.
    mutating func advance(at date: Date) -> Bool {
        var blockedRoom = false
        for id in rooms.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard var room = rooms[id] else { continue }
            do {
                if try room.expireLobby(at: date) || room.advanceScheduledDecision(at: date) {
                    setRoom(room, at: date)
                }
            } catch {
                blockedRoom = true
            }
        }
        outbox = outbox.filter { $0.value.expiresAt > date || $0.value.delivered }
        return blockedRoom
    }

    mutating func setRoom(_ room: StoredOnlineRoom, at date: Date) {
        rooms[room.id] = room
        let currentDecisions = Set(room.decisions.map { $0.action.id })
        outbox = outbox.filter {
            $0.value.matchID != room.id || (currentDecisions.contains($0.value.decisionID) && canDeliver($0.value))
        }
        for decision in room.decisions {
            guard let account = room.seats[decision.action.seat.index].accountID else { continue }
            enqueue(decision, in: room.id, for: account, at: date)
        }
    }

    func canDeliver(_ push: StoredOnlinePush) -> Bool {
        guard let account = accounts[push.accountID], account.devices.contains(push.device),
              let room = rooms[push.matchID], room.status == .playing else { return false }
        return room.decisions.contains {
            $0.action.id == push.decisionID && room.seats[$0.action.seat.index].accountID == push.accountID
        }
    }

    private mutating func enqueue(_ decision: StoredOnlineDecision, in room: UUID, for id: UUID, at date: Date) {
        guard let account = accounts[id] else { return }
        let action = decision.action
        guard action.kind != .trade else { return }
        let expiry = action.deadline ?? decision.openedAt.addingTimeInterval(Self.alertLifetime)
        guard expiry > date else { return }
        for device in account.devices {
            let exists = outbox.values.contains {
                $0.matchID == room && $0.accountID == id && $0.decisionID == action.id && $0.device == device
            }
            if exists { continue }
            let key = UUID()
            outbox[key] = StoredOnlinePush(id: key, accountID: id, matchID: room, decisionID: action.id,
                device: device, nextAttempt: date, expiresAt: expiry)
        }
    }

    mutating func mute(_ id: UUID, account: UUID, muted: Bool, at date: Date) throws -> OnlineResponse {
        let current = try view(id, for: account, at: date)
        if muted {
            accounts[account]?.mutedRooms.insert(id)
        } else {
            accounts[account]?.mutedRooms.remove(id)
        }
        return .match(try view(current.id, for: account, at: date))
    }

    mutating func register(_ device: OnlineDevice, for id: UUID, at date: Date) throws -> OnlineResponse {
        guard (32...512).contains(device.token.utf8.count), device.token.utf8.count.isMultiple(of: 2),
              device.token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let account = accounts[id] else { throw OnlineError.invalidRequest }
        guard !account.devices.contains(device) else { return .ok }
        replaceDeviceRegistration(with: device)
        guard (accounts[id]?.devices.count ?? 0) < 8 else { throw OnlineError.conflict }
        accounts[id]?.devices.insert(device)
        for room in rooms.values {
            guard let seat = try? room.seat(for: id) else { continue }
            for decision in room.decisions where decision.action.seat == seat {
                enqueue(decision, in: room.id, for: id, at: date)
            }
        }
        return .ok
    }

    private mutating func replaceDeviceRegistration(with device: OnlineDevice) {
        for (accountID, account) in accounts {
            let retired = account.devices.filter {
                $0.installationID == device.installationID
                    || ($0.token == device.token && $0.environment == device.environment)
            }
            guard !retired.isEmpty else { continue }
            accounts[accountID]?.devices.subtract(retired)
            outbox = outbox.filter { $0.value.accountID != accountID || !retired.contains($0.value.device) }
        }
    }

    mutating func unregister(_ installationID: UUID, for id: UUID) -> OnlineResponse {
        accounts[id]?.devices = accounts[id]?.devices.filter { $0.installationID != installationID } ?? []
        outbox = outbox.filter { $0.value.accountID != id || $0.value.device.installationID != installationID }
        return .ok
    }

    mutating func resolvePush(id: UUID, result: OnlinePushResult, at date: Date) {
        guard var push = outbox[id], canDeliver(push) else { return }
        switch result {
        case .sent:
            push.delivered = true
            outbox[id] = push
        case .retry:
            push.attempts += 1
            push.nextAttempt = date.addingTimeInterval(min(900, pow(2, Double(min(10, push.attempts))) * 5))
            outbox[id] = push
        case .invalidToken:
            accounts[push.accountID]?.devices.remove(push.device)
            outbox = outbox.filter { $0.value.accountID != push.accountID || $0.value.device != push.device }
        }
    }
}

extension StoredOnlineRoom {
    func isLobbyExpired(at date: Date) -> Bool {
        status == .lobby && date.timeIntervalSince(createdAt) >= OnlineDatabase.lobbyLifetime
    }

    mutating func expireLobby(at date: Date) -> Bool {
        guard isLobbyExpired(at: date) else { return false }
        status = .cancelled
        revision += 1
        return true
    }

    func nextScheduledDecision(at date: Date) -> OnlinePendingAction? {
        guard status == .playing else { return nil }
        return decisions.lazy.map(\.action).first {
            seats[$0.seat.index].role.isBot || ($0.deadline.map { $0 <= date } ?? false)
        }
    }

    mutating func advanceScheduledDecision(at date: Date) throws -> Bool {
        guard let action = nextScheduledDecision(at: date), var gameplay else { return false }
        if seats[action.seat.index].role.isBot {
            try gameplay.advanceBot(for: action.seat)
        } else {
            try gameplay.resolveTimeout(for: action.seat)
        }
        commit(gameplay, at: date)
        return true
    }
}
