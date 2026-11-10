import CatanEngine
import Foundation

extension OnlineDatabase {
    private static let civilizations = [
        "medieval", "greece", "egypt", "aztec", "columbia", "rome", "japan", "norse"
    ]
    private static let inviteCharacters = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let lobbyLifetime: TimeInterval = 7 * 24 * 60 * 60

    mutating func createRoom(
        _ configuration: OnlineConfiguration, civilization: String, account: UUID, at date: Date
    ) throws -> OnlineResponse {
        try configuration.validate()
        guard configuration.aiSeats[0] == nil else { throw OnlineError.invalidRequest }
        try validateCivilization(civilization)
        let activeRooms = rooms.values.lazy.filter {
            $0.hostID == account && ($0.status == .lobby || $0.status == .playing)
        }.count
        guard activeRooms < 12 else { throw OnlineError.conflict }
        let id = UUID()
        let room = StoredOnlineRoom(id: id, code: newInviteCode(), createdAt: date, hostID: account,
            configuration: configuration, seats: configuration.lobbySeats(
                humanSeats: [0: StoredOnlineSeat(role: .human, accountID: account, civilization: civilization)]))
        setRoom(room, at: date)
        return .match(try view(id, for: account, at: date))
    }

    mutating func join(
        code: String, civilization: String, account: UUID, at date: Date
    ) throws -> OnlineResponse {
        try validateCivilization(civilization)
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.utf8.count == 10,
              var room = rooms.values.first(where: { $0.code == normalized }) else {
            throw OnlineError.notFound
        }
        if room.seats.contains(where: { $0.accountID == account }) {
            return .match(try view(room.id, for: account, at: date))
        }
        guard room.status == .lobby, date.timeIntervalSince(room.createdAt) < Self.lobbyLifetime else {
            throw OnlineError.notFound
        }
        guard let index = room.seats.firstIndex(where: { $0.role == .open }),
              !room.seats.contains(where: { $0.role == .human && $0.civilization == civilization }) else {
            throw OnlineError.conflict
        }
        var humans = room.humans
        humans[index] = StoredOnlineSeat(role: .human, accountID: account, civilization: civilization)
        room.reconfigure(room.configuration, humanSeats: humans)
        setRoom(room, at: date)
        return .match(try view(room.id, for: account, at: date))
    }

    mutating func configure(
        _ id: UUID, configuration: OnlineConfiguration, revision: Int, account: UUID, at date: Date
    ) throws -> OnlineResponse {
        var room = try editableRoom(id, by: account)
        try configuration.validate()
        guard room.lobbyRevision == revision else { throw OnlineError.conflict }
        guard room.humans.keys.allSatisfy({ $0 < configuration.aiSeats.count && configuration.aiSeats[$0] == nil }) else {
            throw OnlineError.conflict
        }
        if room.configuration != configuration {
            room.reconfigure(configuration, humanSeats: room.humans)
            setRoom(room, at: date)
        }
        return .match(try view(id, for: account, at: date))
    }

    mutating func readyRoom(
        _ id: UUID, ready: Bool, revision: Int, account: UUID, at date: Date
    ) throws -> OnlineResponse {
        guard var room = rooms[id] else { throw OnlineError.notFound }
        let seat = try room.seat(for: account)
        guard room.status == .lobby, room.lobbyRevision == revision else { throw OnlineError.conflict }
        if room.seats[seat.index].ready != ready {
            room.seats[seat.index].ready = ready
            room.revision += 1
            setRoom(room, at: date)
        }
        return .match(try view(id, for: account, at: date))
    }

    mutating func startRoom(_ id: UUID, revision: Int, account: UUID, at date: Date) throws -> OnlineResponse {
        var room = try editableRoom(id, by: account)
        guard room.lobbyRevision == revision, date.timeIntervalSince(room.createdAt) < Self.lobbyLifetime,
              room.humans.count >= 2,
              room.seats.allSatisfy({ $0.role.isBot || ($0.role == .human && $0.ready) }) else {
            throw OnlineError.conflict
        }
        let gameplay = try OnlineGameplay(configuration: room.configuration, seats: room.seatsView(for: account,
                                                                                                    names: accounts))
        room.status = .playing
        room.commit(gameplay, at: date)
        setRoom(room, at: date)
        return .match(try view(id, for: account, at: date))
    }

    mutating func leave(_ id: UUID, account: UUID, at date: Date) throws -> OnlineResponse {
        guard var room = rooms[id] else { throw OnlineError.notFound }
        let seat = try room.seat(for: account)
        try room.removeHuman(seat, at: date)
        accounts[account]?.mutedRooms.remove(id)
        setRoom(room, at: date)
        return .ok
    }

    mutating func deleteAccount(_ account: UUID, at date: Date) throws -> OnlineResponse {
        for id in Array(rooms.keys) {
            guard var room = rooms[id] else { continue }
            if let seat = try? room.seat(for: account) { try room.removeHuman(seat, at: date) }
            room.receipts = room.receipts.filter { $0.value.accountID != account }
            setRoom(room, at: date)
        }
        accounts.removeValue(forKey: account)
        outbox = outbox.filter { $0.value.accountID != account }
        return .ok
    }

    private func editableRoom(_ id: UUID, by account: UUID) throws -> StoredOnlineRoom {
        guard let room = rooms[id] else { throw OnlineError.notFound }
        _ = try room.seat(for: account)
        guard room.hostID == account else { throw OnlineError.forbidden }
        guard room.status == .lobby else { throw OnlineError.conflict }
        return room
    }

    private func validateCivilization(_ value: String) throws {
        guard Self.civilizations.contains(value) else { throw OnlineError.invalidRequest }
    }

    private func newInviteCode() -> String {
        while true {
            let code = String((0..<10).map { _ in Self.inviteCharacters.randomElement()! })
            if !rooms.values.contains(where: { $0.code == code }) { return code }
        }
    }

    static func botCivilization(reserving values: Set<String>) -> String {
        civilizations.first { !values.contains($0) }!
    }
}

private extension OnlineConfiguration {
    func validate() throws {
        guard (3...4).contains(aiSeats.count),
              aiSeats.filter({ $0 == nil }).count >= 2,
              aiSeats.allSatisfy({ $0 == nil || $0?.isBot == true }),
              GameMode.newGameChoices.contains(mode), mode != .naval || rules == .standard else {
            throw OnlineError.invalidRequest
        }
    }

    func lobbySeats(humanSeats: [Int: StoredOnlineSeat]) -> [StoredOnlineSeat] {
        var reserved = Set(humanSeats.values.compactMap(\.civilization))
        return aiSeats.enumerated().map { index, role in
            if var human = humanSeats[index] {
                human.ready = false
                return human
            }
            guard let role else { return StoredOnlineSeat(role: .open) }
            let civilization = OnlineDatabase.botCivilization(reserving: reserved)
            reserved.insert(civilization)
            return StoredOnlineSeat(role: role, civilization: civilization)
        }
    }
}

extension StoredOnlineRoom {
    var isEmptyCancellation: Bool {
        status == .cancelled && seats.allSatisfy { $0.accountID == nil }
    }

    var humans: [Int: StoredOnlineSeat] {
        Dictionary(uniqueKeysWithValues: seats.enumerated().compactMap { index, seat in
            seat.accountID == nil ? nil : (index, seat)
        })
    }

    mutating func reconfigure(_ configuration: OnlineConfiguration, humanSeats: [Int: StoredOnlineSeat]) {
        self.configuration = configuration
        seats = configuration.lobbySeats(humanSeats: humanSeats)
        lobbyRevision += 1
        revision += 1
    }

    mutating func removeHuman(_ seat: PlayerID, at date: Date) throws {
        let departed = seats[seat.index].accountID
        seats[seat.index].accountID = nil
        if hostID == departed { hostID = seats.compactMap(\.accountID).first }
        switch status {
        case .lobby:
            reconfigure(configuration, humanSeats: humans)
            if humans.isEmpty { status = .cancelled }
        case .playing:
            try replaceDepartedSeat(seat, at: date)
        case .finished, .cancelled:
            revision += 1
        }
    }

    private mutating func replaceDepartedSeat(_ seat: PlayerID, at date: Date) throws {
        guard !humans.isEmpty, var gameplay else {
            status = .cancelled
            gameplay = nil
            revision += 1
            reconcileDecisions(at: date)
            return
        }
        try gameplay.replaceWithBot(seat)
        seats[seat.index].role = .classicAI
        commit(gameplay, at: date)
    }
}
