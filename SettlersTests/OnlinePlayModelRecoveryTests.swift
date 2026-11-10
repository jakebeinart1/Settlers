import Foundation
import Testing
import CatanEngine
import EmpiresOnline
@testable import Settlers

@MainActor
struct OnlinePlayModelRecoveryTests {
    @Test(arguments: [false, true])
    func reconnectSettlesPendingMoveWithoutLeavingAnotherMatch(rejected: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await RecoveryFixture(directory: directory, commitBeforeDisconnect: !rejected)
        defer { fixture.clearStorage() }
        let model = fixture.model

        await model.restore()
        let original = try await fixture.loseFirstSubmission()
        if rejected { try await fixture.advanceFromOtherDevice(using: original) }
        #expect(await model.run(.view(matchID: fixture.other.id)))
        let other = try #require(model.match)
        let otherMove = try #require(other.gameplay?.legalMoves.first)

        await model.submit(otherMove, in: other)
        #expect(try fixture.storage.read(OnlineStorageKey.submission) != nil)
        #expect(await fixture.transport.attempts == [original])
        #expect(model.isConfirmingMoveInAnotherMatch)

        await model.refresh()
        #expect(await fixture.transport.attempts == [original, original])
        #expect(model.match?.id == other.id)
        #expect(!model.hasPendingSubmission)
        #expect(try fixture.storage.read(OnlineStorageKey.submission) == nil)
        #expect(try await fixture.firstRevision() == fixture.first.revision + 1)

        await model.submit(otherMove, in: try #require(model.match))
        #expect(model.match?.revision == other.revision + 1)
    }

    @Test func reconnectPublishesConfirmedMoveInItsMatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await RecoveryFixture(directory: directory, commitBeforeDisconnect: true)
        defer { fixture.clearStorage() }

        await fixture.model.restore()
        let original = try await fixture.loseFirstSubmission()
        await fixture.model.refresh()

        #expect(await fixture.transport.attempts == [original, original])
        #expect(fixture.model.match?.id == fixture.first.id)
        #expect(fixture.model.match?.revision == fixture.first.revision + 1)
        #expect(!fixture.model.hasPendingSubmission)
    }

    @Test func accountRecoveryNeverRetriesThePreviousAccountsMove() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await RecoveryFixture(directory: directory, commitBeforeDisconnect: false)
        defer { fixture.clearStorage() }

        await fixture.model.restore()
        let original = try await fixture.loseFirstSubmission()
        await fixture.model.signOut()
        await fixture.model.recover(using: fixture.guest)
        await fixture.model.refresh()

        #expect(fixture.model.account?.name == "Guest")
        #expect(!fixture.model.hasPendingSubmission)
        #expect(await fixture.transport.attempts == [original])
        #expect(try await fixture.firstRevision() == fixture.first.revision)
    }
}

@MainActor
private struct RecoveryFixture {
    let authority: OnlineAuthority
    let transport: InterruptedMoveTransport
    let storage: OnlineSecureStore
    let model: OnlinePlayModel
    let first: OnlineMatchView
    let other: OnlineMatchView
    let host: String
    let guest: String

    init(directory: URL, commitBeforeDisconnect: Bool) async throws {
        let authority = try OnlineAuthority(directory: directory, clock: { Date(timeIntervalSince1970: 1_000) })
        let host = try await Self.bearer(named: "Host", on: authority)
        let guest = try await Self.bearer(named: "Guest", on: authority)
        let first = try await Self.start(.asynchronous, on: authority, host: host, guest: guest)
        let other = try await Self.start(.timedLive, on: authority, host: host, guest: guest)
        let endpoint = try #require(URL(string: "https://\(UUID().uuidString).example.invalid"))
        let storage = OnlineSecureStore(endpoint: endpoint)
        try storage.write(Data(host.utf8), key: OnlineStorageKey.bearer)
        let transport = InterruptedMoveTransport(authority: authority, match: first.id,
                                                 commitBeforeDisconnect: commitBeforeDisconnect)
        self.authority = authority
        self.transport = transport
        self.storage = storage
        model = OnlinePlayModel(storage: storage) { request, bearer in try await transport.send(request, bearer: bearer) }
        self.first = first
        self.other = other
        self.host = host
        self.guest = guest
    }

    func loseFirstSubmission() async throws -> OnlineCommand {
        #expect(await model.run(.view(matchID: first.id)))
        let position = try #require(model.match)
        await model.submit(try #require(position.gameplay?.legalMoves.first), in: position)
        #expect(model.hasPendingSubmission)
        #expect(model.isOffline)
        return try #require(await transport.attempts.first)
    }

    func advanceFromOtherDevice(using original: OnlineCommand) async throws {
        let another = OnlineCommand(decisionID: original.decisionID, revision: original.revision, move: original.move)
        _ = try await authority.handle(.submit(matchID: first.id, command: another), bearer: host)
    }

    func firstRevision() async throws -> Int {
        try await Self.position(.view(matchID: first.id), on: authority, bearer: host).revision
    }

    func clearStorage() {
        try? storage.remove(OnlineStorageKey.submission)
        try? storage.remove(OnlineStorageKey.bearer)
    }

    private static func bearer(named name: String, on authority: OnlineAuthority) async throws -> String {
        let response = try await authority.handle(.createAccount(name: name), bearer: nil)
        guard case .account(let account) = response else { throw OnlineClientError.unexpectedResponse }
        return try #require(account.bearer)
    }

    private static func start(_ pace: OnlinePace, on authority: OnlineAuthority,
                              host: String, guest: String) async throws -> OnlineMatchView {
        let configuration = OnlineConfiguration(pace: pace, mode: .classic, rules: .standard,
                                                aiSeats: [nil, nil, .classicAI])
        let created = try await position(.createRoom(configuration: configuration, civilization: "medieval"),
                                         on: authority, bearer: host)
        let joined = try await position(.join(code: created.code, civilization: "greece"), on: authority, bearer: guest)
        for bearer in [host, guest] {
            _ = try await authority.handle(.ready(matchID: joined.id, isReady: true, revision: joined.lobbyRevision),
                                           bearer: bearer)
        }
        return try await position(.start(matchID: joined.id, revision: joined.lobbyRevision), on: authority, bearer: host)
    }

    private static func position(_ request: OnlineRequest, on authority: OnlineAuthority,
                                 bearer: String) async throws -> OnlineMatchView {
        let response = try await authority.handle(request, bearer: bearer)
        guard case .match(let position) = response else { throw OnlineClientError.unexpectedResponse }
        return position
    }
}

private actor InterruptedMoveTransport {
    let authority: OnlineAuthority
    let match: UUID
    let commitBeforeDisconnect: Bool
    private(set) var attempts: [OnlineCommand] = []

    init(authority: OnlineAuthority, match: UUID, commitBeforeDisconnect: Bool) {
        self.authority = authority
        self.match = match
        self.commitBeforeDisconnect = commitBeforeDisconnect
    }

    func send(_ request: OnlineRequest, bearer: String?) async throws -> OnlineResponse {
        do {
            if case .submit(let id, let command) = request, id == match {
                attempts.append(command)
                if attempts.count == 1 {
                    if commitBeforeDisconnect { _ = try await authority.handle(request, bearer: bearer) }
                    throw URLError(.networkConnectionLost)
                }
            }
            return try await authority.handle(request, bearer: bearer)
        } catch OnlineError.conflict {
            throw OnlineClientError.rejected(409, .conflict)
        }
    }
}
