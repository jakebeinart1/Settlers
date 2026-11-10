import CatanEngine
import Foundation
import Testing
@testable import EmpiresOnline

struct OnlineAuthorityTests {
    @Test func finalDepartureRemovesCancelledRoomAcrossRestart() async throws {
        let fixture = try AuthorityFixture()
        let id = try await leaveStartedRoom(fixture: fixture)
        let restarted = try fixture.open()
        let database = await restarted.database
        #expect(database.rooms[id] == nil)
        #expect(database.outbox.values.allSatisfy { $0.matchID != id })
    }

    private func leaveStartedRoom(fixture: AuthorityFixture) async throws -> UUID {
        let server = try fixture.open()
        let room = try await fixture.startedRoom(on: server, pace: .asynchronous)
        _ = try await server.handle(.leave(matchID: room.view.id), bearer: room.host)
        let transferred = try await server.match(.view(matchID: room.view.id), bearer: room.guest)
        #expect(transferred.host && transferred.status == .playing)
        _ = try await server.handle(.leave(matchID: room.view.id), bearer: room.guest)
        let database = await server.database
        #expect(database.rooms[room.view.id] == nil)
        return room.view.id
    }

    @Test func startupPrunesLegacyEmptyCancellationButKeepsParticipantHistory() async throws {
        let fixture = try AuthorityFixture()
        let configuration = OnlineConfiguration(pace: .asynchronous, mode: .classic, rules: .standard,
                                                aiSeats: [nil, nil, .classicAI])
        let account = UUID()
        let date = fixture.clock.read()
        var empty = StoredOnlineRoom(id: UUID(), code: "empty", createdAt: date, hostID: nil,
                                     configuration: configuration, seats: [])
        empty.status = .cancelled
        var history = StoredOnlineRoom(id: UUID(), code: "history", createdAt: date, hostID: account,
                                       configuration: configuration,
                                       seats: [StoredOnlineSeat(role: .human, accountID: account)])
        history.status = .cancelled
        do {
            let store = try OnlineStore(directory: fixture.directory)
            try store.save(OnlineDatabase(rooms: [empty.id: empty, history.id: history]))
        }
        let server = try fixture.open()
        let database = await server.database
        #expect(database.rooms[empty.id] == nil)
        #expect(database.rooms[history.id]?.seats.first?.accountID == account)
    }

    @Test func snapshotWriteFailureMakesReadinessRetryable() async throws {
        let fixture = try AuthorityFixture()
        let server = try fixture.open()
        let room = try await fixture.startedRoom(on: server, pace: .asynchronous)
        let command = try room.firstCommand()
        let snapshot = fixture.directory.appendingPathComponent("authority-v1.json")
        let held = fixture.directory.appendingPathComponent("held.json")
        let files = FileManager.default
        try files.moveItem(at: snapshot, to: held)
        try files.createDirectory(at: snapshot, withIntermediateDirectories: false)
        await #expect(throws: OnlineError.unavailable) {
            try await server.handle(.submit(matchID: room.view.id, command: command), bearer: room.host)
        }
        #expect(await !server.isReady)
        let unchanged = try await server.match(.view(matchID: room.view.id), bearer: room.host)
        #expect(unchanged.revision == room.view.revision)
        try files.removeItem(at: snapshot)
        try files.moveItem(at: held, to: snapshot)
        fixture.clock.set(fixture.clock.read().addingTimeInterval(10))
        try await server.tick()
        #expect(await server.isReady)
        let accepted = try await server.match(.submit(matchID: room.view.id, command: command), bearer: room.host)
        #expect(accepted.revision == room.view.revision + 1)
        #expect(accepted.acknowledgedCommandID == command.id)
    }

    @Test func successorHostCanFillTheDepartedHostsSeat() async throws {
        let fixture = try AuthorityFixture()
        let server = try fixture.open()
        let host = try await server.newBearer("Host")
        let successor = try await server.newBearer("Successor")
        let guest = try await server.newBearer("Guest")
        let configuration = OnlineConfiguration(pace: .asynchronous, mode: .classic, rules: .standard,
                                                aiSeats: [nil, nil, nil, .classicAI])
        let room = try await server.match(.createRoom(configuration: configuration,
                                                       civilization: "greece"), bearer: host)
        _ = try await server.match(.join(code: room.code, civilization: "rome"), bearer: successor)
        _ = try await server.match(.join(code: room.code, civilization: "norse"), bearer: guest)
        _ = try await server.handle(.leave(matchID: room.id), bearer: host)
        let transferred = try await server.match(.view(matchID: room.id), bearer: successor)
        #expect(transferred.host)
        let filled = OnlineConfiguration(pace: .asynchronous, mode: .classic, rules: .standard,
                                        aiSeats: [.classicAI, nil, nil, .expertAI])
        let edited = try await server.match(.configure(matchID: room.id, configuration: filled,
            revision: transferred.lobbyRevision), bearer: successor)
        #expect(edited.seats.map(\.role) == [.classicAI, .human, .human, .expertAI])
    }

    @Test func staleLobbyReadinessCannotAuthorizeChangedRules() async throws {
        let fixture = try AuthorityFixture()
        let server = try fixture.open()
        let room = try await fixture.joinedRoom(on: server, pace: .asynchronous)
        let changed = OnlineConfiguration(pace: .timedLive, mode: .vast, rules: .conquest,
                                          aiSeats: [nil, nil, .expertAI])
        let updated = try await server.match(.configure(matchID: room.view.id, configuration: changed,
            revision: room.view.lobbyRevision), bearer: room.host)
        #expect(updated.lobbyRevision > room.view.lobbyRevision)
        await #expect(throws: OnlineError.conflict) {
            try await server.handle(.ready(matchID: room.view.id, isReady: true,
                revision: room.view.lobbyRevision), bearer: room.guest)
        }
        #expect(updated.seats.filter { $0.role == .human }.allSatisfy { !$0.ready })
        await #expect(throws: OnlineError.conflict) {
            try await server.handle(.start(matchID: room.view.id, revision: updated.lobbyRevision),
                                    bearer: room.host)
        }
    }

    @Test func durableCommandReceiptsAndPrivateViewsSurviveRestart() async throws {
        let fixture = try AuthorityFixture()
        let started = try await submitOpeningMove(fixture: fixture)
        let server = try fixture.open()
        let refreshed = try await server.match(.view(matchID: started.room.view.id), bearer: started.room.host)
        #expect(refreshed.gameplay?.players.first?.settlements.count == 1)
        let repeated = try await server.match(.submit(matchID: refreshed.id, command: started.command),
                                              bearer: started.room.host)
        #expect(repeated.revision == refreshed.revision)
        #expect(repeated.acknowledgedCommandID == started.command.id)
        await #expect(throws: OnlineError.conflict) {
            try await server.handle(.submit(matchID: refreshed.id, command: started.command),
                                    bearer: started.room.guest)
        }
        let guest = try await server.match(.view(matchID: refreshed.id), bearer: started.room.guest)
        #expect(guest.viewer != refreshed.viewer)
        #expect(guest.gameplay?.legalMoves.isEmpty == true)
        let outsider = try await server.newBearer("Outsider")
        await #expect(throws: OnlineError.notFound) {
            try await server.handle(.view(matchID: refreshed.id), bearer: outsider)
        }
    }

    private func submitOpeningMove(
        fixture: AuthorityFixture
    ) async throws -> (room: RoomFixture, command: OnlineCommand) {
        let server = try fixture.open()
        #expect(throws: OnlineError.unavailable) { try fixture.open() }
        let room = try await fixture.startedRoom(on: server, pace: .asynchronous)
        let command = try room.firstCommand()
        let accepted = try await server.match(.submit(matchID: room.view.id, command: command), bearer: room.host)
        #expect(accepted.acknowledgedCommandID == command.id)
        return (room, command)
    }

    @Test func liveTimeoutWinsAnExactDeadlineRaceAndMovesWithoutAClient() async throws {
        let fixture = try AuthorityFixture()
        let server = try fixture.open()
        let room = try await fixture.startedRoom(on: server, pace: .timedLive)
        let first = try room.firstCommand()
        let deadline = try #require(room.view.pending.first?.deadline)
        try await fixture.advanceClock(to: deadline, ticking: server)
        await #expect(throws: OnlineError.conflict) {
            try await server.handle(.submit(matchID: room.view.id, command: first), bearer: room.host)
        }
        try await server.tick()
        let next = try await server.match(.view(matchID: room.view.id), bearer: room.host)
        #expect(next.gameplay?.players.first?.settlements.count == 1)
        #expect(next.pending.first?.id != first.decisionID)
        #expect(next.pending.first?.deadline == deadline.addingTimeInterval(60))
    }

    @Test func longAuthorityOutagePausesLiveSetupClock() async throws {
        let fixture = try AuthorityFixture()
        let room = try await makeLiveRoom(fixture: fixture)
        let before = try #require(room.view.pending.first?.deadline)
        fixture.clock.set(fixture.clock.read().addingTimeInterval(120))
        let restarted = try fixture.open()
        let after = try await restarted.match(.view(matchID: room.view.id), bearer: room.host)
        #expect(after.pending.first?.deadline == before.addingTimeInterval(120))
        #expect(after.pending.first?.id == room.view.pending.first?.id)
    }

    private func makeLiveRoom(fixture: AuthorityFixture) async throws -> RoomFixture {
        let server = try fixture.open()
        return try await fixture.startedRoom(on: server, pace: .timedLive)
    }

    @Test func serviceOutageDoesNotExtendAnAsyncTrade() {
        let start = Date(timeIntervalSince1970: 100)
        let deadline = start.addingTimeInterval(120)
        let action = OnlinePendingAction(id: UUID(), seat: PlayerID(index: 0),
                                        kind: .trade, deadline: deadline)
        let configuration = OnlineConfiguration(pace: .asynchronous, mode: .classic, rules: .standard,
                                                aiSeats: [nil, nil, .classicAI])
        var room = StoredOnlineRoom(id: UUID(), code: "test", createdAt: start, hostID: nil,
                                    configuration: configuration, seats: [])
        room.status = .playing
        room.decisions = [StoredOnlineDecision(action: action,
            scope: OnlineDecisionScope(turn: 1, phase: "trade"), openedAt: start)]
        var database = OnlineDatabase(lastServiceAt: start)
        database.rooms[room.id] = room

        database.pauseDeadlinesForOutage(at: deadline.addingTimeInterval(3600))

        #expect(database.rooms[room.id]?.decisions.first?.action.deadline == deadline)
    }

    @Test func asyncActionsDriveAlertsWithoutAClientAndMuteDoesNotEraseTheInbox() async throws {
        let fixture = try AuthorityFixture()
        let server = try fixture.open()
        let room = try await fixture.startedRoom(on: server, pace: .asynchronous)
        let token = String(repeating: "a9", count: 32)
        let device = OnlineRequest.registerDevice(installationID: UUID(), token: token, environment: .production)
        _ = try await server.handle(device, bearer: room.host)
        let alerts = await server.pendingPushes()
        let alert = try #require(alerts.first)
        #expect(alert.matchID == room.view.id)
        #expect(alert.decisionID == room.view.pending.first?.id)
        _ = try await server.handle(.mute(matchID: room.view.id, muted: true), bearer: room.host)
        #expect(await server.pendingPushes().isEmpty)
        let inbox = try await server.handle(.list, bearer: room.host)
        if case .games(let games) = inbox { #expect(games.first?.needsYou == true) } else { Issue.record("Expected games") }
        _ = try await server.handle(.mute(matchID: room.view.id, muted: false), bearer: room.host)
        try await server.resolvePush(id: alert.id, result: .sent)
        _ = try await server.handle(device, bearer: room.host)
        #expect(await server.pendingPushes().isEmpty)
        _ = try await server.handle(.deleteAccount, bearer: room.host)
        await #expect(throws: OnlineError.unauthorized) {
            try await server.handle(.profile, bearer: room.host)
        }
        let remaining = try await server.match(.view(matchID: room.view.id), bearer: room.guest)
        #expect(remaining.seats[0].role == .classicAI)
        #expect(remaining.host)
    }
}

private struct RoomFixture {
    let view: OnlineMatchView
    let host: String
    let guest: String

    func firstCommand() throws -> OnlineCommand {
        let action = try #require(view.pending.first)
        let move = try #require(view.gameplay?.legalMoves.first)
        return OnlineCommand(decisionID: action.id, revision: view.revision, move: move)
    }
}

private final class AuthorityFixture {
    let directory: URL
    let clock = ManualClock()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    deinit {
        do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Test directory cleanup failed") }
    }

    func open() throws -> OnlineAuthority {
        try OnlineAuthority(directory: directory, clock: { [clock] in clock.read() })
    }

    func joinedRoom(on server: OnlineAuthority, pace: OnlinePace) async throws -> RoomFixture {
        let host = try await server.newBearer("Host")
        let guest = try await server.newBearer("Guest")
        let configuration = OnlineConfiguration(pace: pace, mode: .classic, rules: .standard,
                                                aiSeats: [nil, nil, .classicAI])
        let initial = try await server.match(.createRoom(configuration: configuration,
                                                         civilization: "greece"), bearer: host)
        let joined = try await server.match(.join(code: initial.code, civilization: "rome"), bearer: guest)
        return RoomFixture(view: joined, host: host, guest: guest)
    }

    func startedRoom(on server: OnlineAuthority, pace: OnlinePace) async throws -> RoomFixture {
        let room = try await joinedRoom(on: server, pace: pace)
        let revision = room.view.lobbyRevision
        for bearer in [room.host, room.guest] {
            _ = try await server.handle(.ready(matchID: room.view.id, isReady: true, revision: revision), bearer: bearer)
        }
        let view = try await server.match(.start(matchID: room.view.id, revision: revision), bearer: room.host)
        return RoomFixture(view: view, host: room.host, guest: room.guest)
    }

    func advanceClock(to deadline: Date, ticking server: OnlineAuthority) async throws {
        while clock.read().addingTimeInterval(10) < deadline {
            clock.set(clock.read().addingTimeInterval(10))
            try await server.tick()
        }
        clock.set(deadline)
    }
}

private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 100_000)

    func set(_ date: Date) { lock.withLock { value = date } }
    func read() -> Date { lock.withLock { value } }
}

private extension OnlineAuthority {
    func match(_ request: OnlineRequest, bearer: String) throws -> OnlineMatchView {
        let response = try handle(request, bearer: bearer)
        guard case .match(let match) = response else { throw OnlineError.unavailable }
        return match
    }

    func newBearer(_ name: String) throws -> String {
        let response = try handle(.createAccount(name: name), bearer: nil)
        guard case .account(let account) = response, let bearer = account.bearer else {
            throw OnlineError.unavailable
        }
        return bearer
    }
}
