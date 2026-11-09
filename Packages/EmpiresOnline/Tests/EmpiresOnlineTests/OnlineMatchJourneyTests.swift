import CatanAI
import CatanEngine
import EmpiresOnline
import Foundation
import Testing

@Suite(.serialized)
struct OnlineMatchJourneyTests {
    private static let maximumCommittedActions = 2_000

    @Test func completesAsyncMatch() async throws {
        try await playToWinner(.asynchronous)
    }

    @Test func completesTimedMatch() async throws {
        try await playToWinner(.timedLive)
    }

    private func playToWinner(_ pace: OnlinePace) async throws {
        let fixture = try JourneyFixture()
        let server = try fixture.open()
        let host = try await JourneyClient.register("Journey Host", on: server)
        let guest = try await JourneyClient.register("Journey Guest", on: server)
        var view = try await openTable(pace, host: host, guest: guest, server: server)
        let table = view.id
        let firstDecision = try #require(view.pending.first)
        try await moveClock(pace, fixture: fixture, decision: firstDecision, server: server)
        view = try await host.match(.view(matchID: table))
        #expect((view.pending.first?.id == firstDecision.id) == (pace == .asynchronous))
        var pilot = JourneyPilot()
        for _ in 0..<Self.maximumCommittedActions where view.status == .playing {
            let revision = view.revision
            fixture.clock.advance(by: 1)
            view = try await playNext(view, host: host, guest: guest, pilot: &pilot, server: server)
            try #require(view.revision > revision)
        }
        try #require(view.status == .finished, "Match exceeded the committed action cap")
        let winner = try #require(view.gameplay?.winner)
        #expect(pilot.humanActors.count == 2)
        #expect(pilot.botActions > 0)
        #expect(pilot.diceRolls > 0)
        try await confirmSharedResult(table: table, winner: winner, revision: view.revision, clients: [host, guest])
    }

    private func openTable(
        _ pace: OnlinePace, host: JourneyClient, guest: JourneyClient, server: OnlineAuthority
    ) async throws -> OnlineMatchView {
        let config = OnlineConfiguration(pace: pace, mode: .classic, rules: .standard,
                                         aiSeats: [nil, nil, .classicAI])
        let lobby = try await host.match(.createRoom(configuration: config, civilization: "greece"))
        let joined = try await guest.match(.join(code: lobby.code, civilization: "rome"))
        #expect(joined.seats.map(\.role) == [.human, .human, .classicAI])
        let token = String(repeating: "a9", count: 32)
        _ = try await host.handle(.registerDevice(installationID: UUID(), token: token, environment: .development))
        for client in [host, guest] {
            _ = try await client.handle(.ready(matchID: lobby.id, isReady: true, revision: joined.lobbyRevision))
        }
        let playing = try await host.match(.start(matchID: lobby.id, revision: joined.lobbyRevision))
        let action = try #require(playing.pending.first)
        let alerts = await server.pendingPushes()
        let alert = try #require(alerts.first)
        #expect(alert.matchID == lobby.id && alert.decisionID == action.id)
        #expect(alert.token == token)
        return playing
    }

    private func moveClock(
        _ pace: OnlinePace, fixture: JourneyFixture, decision: OnlinePendingAction, server: OnlineAuthority
    ) async throws {
        if pace == .asynchronous {
            #expect(decision.deadline == nil)
            fixture.clock.advance(by: 3_600)
        } else {
            let deadline = try #require(decision.deadline)
            while fixture.clock.read() < deadline {
                fixture.clock.advance(by: min(10, deadline.timeIntervalSince(fixture.clock.read())))
                try await server.tick()
            }
        }
        try await server.tick()
    }

    private func playNext(
        _ view: OnlineMatchView, host: JourneyClient, guest: JourneyClient,
        pilot: inout JourneyPilot, server: OnlineAuthority
    ) async throws -> OnlineMatchView {
        let pending = try #require(view.pending.first)
        switch view.seats[pending.seat.index].role {
        case .classicAI, .expertAI:
            try await server.tick()
            pilot.botActions += 1
            return try await host.match(.view(matchID: view.id))
        case .human:
            let client = pending.seat.index == 0 ? host : guest
            let current = if view.viewer == pending.seat {
                view
            } else {
                try await client.match(.view(matchID: view.id))
            }
            let gameplay = try #require(current.gameplay)
            let move = try pilot.move(from: gameplay)
            let command = OnlineCommand(decisionID: pending.id, revision: current.revision, move: move)
            let accepted = try await client.match(.submit(matchID: view.id, command: command))
            #expect(accepted.acknowledgedCommandID == command.id)
            return accepted
        case .open:
            throw OnlineError.unavailable
        }
    }

    private func confirmSharedResult(
        table: UUID, winner: PlayerID, revision: Int, clients: [JourneyClient]
    ) async throws {
        for client in clients {
            let result = try await client.match(.view(matchID: table))
            #expect(result.status == .finished && result.revision == revision)
            #expect(result.gameplay?.winner == winner && result.pending.isEmpty)
            guard case .games(let games) = try await client.handle(.list) else {
                throw OnlineError.unavailable
            }
            let summary = try #require(games.first(where: { $0.id == table }))
            #expect(summary.status == .finished && !summary.needsYou)
        }
    }
}

private struct JourneyClient {
    let server: OnlineAuthority
    let bearer: String

    static func register(_ name: String, on server: OnlineAuthority) async throws -> Self {
        guard case .account(let account) = try await server.handle(.createAccount(name: name), bearer: nil),
              let bearer = account.bearer else { throw OnlineError.unavailable }
        return Self(server: server, bearer: bearer)
    }

    func handle(_ request: OnlineRequest) async throws -> OnlineResponse {
        try await server.handle(request, bearer: bearer)
    }

    func match(_ request: OnlineRequest) async throws -> OnlineMatchView {
        guard case .match(let view) = try await handle(request) else { throw OnlineError.unavailable }
        return view
    }
}

/// Picks only from the authenticated client's public projection. The pilot
/// has no access to the authoritative checkpoint, other hands, or dice seed.
private struct JourneyPilot {
    private let bot = Bot(personality: .balanced)
    private var rng = RandomSource(seed: 9)
    var humanActors: Set<PlayerID> = []
    var botActions = 0
    var diceRolls = 0

    mutating func move(from view: OnlineGameplayView) throws -> GameMove {
        humanActors.insert(view.viewer)
        if let count = view.discardCount { return try discard(count, from: view.resources) }
        try #require(!view.legalMoves.isEmpty)
        let move = bot.decide(for: view.boardPresentationState, player: view.viewer,
                              legalMoves: view.legalMoves, rng: &rng)
        if move == .rollDice { diceRolls += 1 }
        return move
    }

    private func discard(_ count: Int, from cards: [Resource: Int]) throws -> GameMove {
        var left = count
        var selected: [Resource: Int] = [:]
        for resource in Resource.allCases where left > 0 {
            let amount = min(left, cards[resource, default: 0])
            if amount > 0 { selected[resource] = amount }
            left -= amount
        }
        try #require(left == 0)
        return .discard(selected)
    }
}

private final class JourneyFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let clock = JourneyClock()

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func open() throws -> OnlineAuthority {
        try OnlineAuthority(directory: directory, clock: { [clock] in clock.read() })
    }

    deinit {
        do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Test directory cleanup failed") }
    }
}

private final class JourneyClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 100_000)

    func read() -> Date { lock.withLock { date } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}
