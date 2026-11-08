import XCTest
import CatanEngine
import EmpiresOnline

/// One simulator plays the guest through the native UI. The test process
/// represents the host via the same real HTTP contract on a local QA server.
@MainActor
final class OnlineLoopbackFlowTests: XCTestCase {
    func testGuestJoinsStartsAndResumesAnActualOnlineTable() async throws {
        continueAfterFailure = false
        let (app, room) = try await actingGuest(pace: .asynchronous)
        let corner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.vertex.")).firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 15))
        corner.tap()
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let road = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.edge.")).firstMatch
        XCTAssertTrue(road.waitForExistence(timeout: 12))
        capture("online-guest-road-after-placement", app: app)
        try resumeGuest(app, match: room.id)
    }

    func testTimedGuestSeesTheServerClockCountDownDuringSetup() async throws {
        continueAfterFailure = false
        let (app, _) = try await actingGuest(pace: .timedLive)
        let corner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.vertex.")).firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 15))
        let clock = app.staticTexts["online.clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        let first = try remainingSeconds(clock)
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThanOrEqual(first, 60)
        try await Task.sleep(for: .seconds(4))
        let later = try remainingSeconds(clock)
        XCTAssertGreaterThan(later, 0)
        XCTAssertLessThan(later, first)
        XCTAssertTrue(corner.exists, "The guest still owns the opening placement before expiry.")
        capture("online-timed-guest-setup-clock", app: app)
    }

    private func actingGuest(pace: OnlinePace) async throws -> (XCUIApplication, OnlineMatchView) {
        let endpoint = try loopbackEndpoint()
        let peer = OnlineTestPeer(endpoint: endpoint)
        let room = try await peer.createRoom(pace: pace)
        let app = launchGuest(endpoint: endpoint)
        enterGuest(app, code: room.code)
        let ready = app.buttons["online.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15))
        ready.tap()
        XCTAssertTrue(app.buttons["Unready"].waitForExistence(timeout: 10))
        try await peer.startAndPassFirstSetup(in: room)
        return (app, room)
    }

    private func remainingSeconds(_ clock: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(clock.value as? String)
        let digits = try XCTUnwrap(value.split(separator: " ").first)
        return try XCTUnwrap(Int(digits))
    }

    private func loopbackEndpoint() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let raw = environment["EMPIRES_ONLINE_UI_TEST_URL"] ?? environment["TEST_RUNNER_EMPIRES_ONLINE_UI_TEST_URL"]
        guard let raw else { throw XCTSkip("Start a loopback Empires match service to run native online integration.") }
        let endpoint = try XCTUnwrap(URL(string: raw))
        XCTAssertEqual(endpoint.scheme, "http")
        XCTAssertTrue(["localhost", "127.0.0.1"].contains(endpoint.host ?? ""))
        return endpoint
    }

    private func launchGuest(endpoint: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-empiresOnlineServer", endpoint.absoluteString,
                               "-empiresOnlineTestSession", UUID().uuidString]
        app.launch()
        return app
    }

    private func enterGuest(_ app: XCUIApplication, code: String) {
        let online = app.buttons["main-menu.online"]
        XCTAssertTrue(online.waitForExistence(timeout: 10))
        online.tap()
        let name = app.textFields["online.account.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Guest")
        app.buttons["online.account.submit"].tap()
        let join = app.buttons["online.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 15))
        join.tap()
        let invitation = app.textFields["online.invite-entry"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 10))
        invitation.tap()
        invitation.typeText(code)
        app.buttons["online.room-submit"].tap()
        XCTAssertTrue(app.staticTexts["online.invite-code"].waitForExistence(timeout: 12))
        capture("online-guest-lobby", app: app)
    }

    private func resumeGuest(_ app: XCUIApplication, match: UUID) throws {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset" }
        app.launch()
        let online = app.buttons["main-menu.online"]
        XCTAssertTrue(online.waitForExistence(timeout: 10))
        online.tap()
        let game = app.buttons["online.game.\(match)"]
        XCTAssertTrue(game.waitForExistence(timeout: 15))
        game.tap()
        let road = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.edge.")).firstMatch
        XCTAssertTrue(road.waitForExistence(timeout: 12))
        capture("online-guest-resumed", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class OnlineTestPeer {
    let endpoint: URL
    private var bearer: String?

    init(endpoint: URL) { self.endpoint = endpoint }

    func createRoom(pace: OnlinePace) async throws -> OnlineMatchView {
        guard case .account(let account) = try await send(.createAccount(name: "Host")) else {
            throw PeerError.unexpected
        }
        bearer = try XCTUnwrap(account.bearer)
        let settings = OnlineConfiguration(pace: pace, mode: .classic, rules: .standard,
                                           aiSeats: [nil, nil, .classicAI])
        return try await match(.createRoom(configuration: settings, civilization: "medieval"))
    }

    func startAndPassFirstSetup(in room: OnlineMatchView) async throws {
        let updated = try await match(.view(matchID: room.id))
        _ = try await match(.ready(matchID: room.id, isReady: true, revision: updated.lobbyRevision))
        var position = try await match(.start(matchID: room.id, revision: updated.lobbyRevision))
        for _ in 0 ..< 2 {
            let action = try XCTUnwrap(position.pending.first { $0.seat == position.viewer })
            let move = try XCTUnwrap(position.gameplay?.legalMoves.first)
            position = try await match(.submit(matchID: room.id, command: OnlineCommand(
                decisionID: action.id, revision: position.revision, move: move
            )))
        }
    }

    private func match(_ request: OnlineRequest) async throws -> OnlineMatchView {
        guard case .match(let position) = try await send(request) else { throw PeerError.unexpected }
        return position
    }

    private func send(_ value: OnlineRequest) async throws -> OnlineResponse {
        var request = URLRequest(url: endpoint.appendingPathComponent("v1").appendingPathComponent("online"),
                                 timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(value)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw PeerError.unexpected
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OnlineResponse.self, from: data)
    }

    private enum PeerError: Error { case unexpected }
}
