import APNSCore
import EmpiresOnline
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import EmpiresOnlineServer

@Suite struct OnlineRoutesTests {
    private static let operatorToken = String(repeating: "a1", count: 32)
    private static let operatorAuthorization = "Bearer \(operatorToken)"

    @Test func signupIsClosedByDefaultEvenWithForwardedLoopback() async throws {
        try await withServer { application in
            let request = OnlineRequest.createAccount(name: "Uninvited")
            let response = try await application.sendRequest(.POST, "/v1/online", headers: [
                "Content-Type": "application/json", "X-Forwarded-For": "127.0.0.1"
            ], body: .init(bytes: try JSONEncoder().encode(request)))
            #expect(response.status == .unauthorized)
            #expect(try error(from: response) == .unauthorized)
        }
    }

    @Test func accountCredentialCanReadItsProfile() async throws {
        try await withServer(provisioning: true) { application in
            let health = try await application.sendRequest(.GET, "/health")
            #expect(health.status == .ok)

            let created = try await request(.createAccount(name: "Player"), application,
                                            authorization: Self.operatorAuthorization)
            #expect(created.status == .ok)
            #expect(created.headers.first(name: .cacheControl) == "no-store")
            let response = try JSONDecoder().decode(OnlineResponse.self, from: Data(created.body.readableBytesView))
            guard case .account(let account) = response else { throw OnlineError.invalidRequest }
            let bearer = try #require(account.bearer)

            let profile = try await request(.profile, application, authorization: "Bearer \(bearer)")
            #expect(profile.status == .ok)
            let profileResponse = try JSONDecoder().decode(OnlineResponse.self, from: Data(profile.body.readableBytesView))
            guard case .account(let returned) = profileResponse else { throw OnlineError.invalidRequest }
            #expect(returned.id == account.id)
            #expect(returned.bearer == nil)
        }
    }

    @Test func enrollmentAndPlayerCredentialsHaveSeparatePrivileges() async throws {
        try await withServer(provisioning: true) { application in
            let enroll = OnlineRequest.createAccount(name: "Guest")
            let player = try await createCredential("Host", application)
            let wrongToken = "Bearer \(String(repeating: "b1", count: 32))"
            for authorization in [nil, wrongToken, player] {
                let response = try await request(enroll, application, authorization: authorization)
                #expect(response.status == .unauthorized)
                #expect(try error(from: response) == .unauthorized)
            }
            let profile = try await request(.profile, application, authorization: Self.operatorAuthorization)
            #expect(profile.status == .unauthorized)
        }
    }

    @Test(arguments: [false, true])
    func loopbackSignupAllowsOnlyDirectRequests(forwarded: Bool) async throws {
        try await withServer(environment: ["EMPIRES_ONLINE_ALLOW_LOOPBACK_SIGNUP": "1"]) { application in
            let client = try application.testing(method: .running(hostname: "127.0.0.1", port: 0))
            var headers: HTTPHeaders = ["Content-Type": "application/json"]
            if forwarded { headers.add(name: .xForwardedFor, value: "127.0.0.1") }
            let enroll = OnlineRequest.createAccount(name: "Local player")
            let response = try await client.sendRequest(.POST, "/v1/online", headers: headers,
                                                        body: .init(bytes: try JSONEncoder().encode(enroll)))
            #expect(response.status == (forwarded ? .unauthorized : .ok))
        }
    }

    @Test func loopbackSignupCannotBindPublicly() {
        #expect(throws: ServerConfigurationError.invalidLoopbackSignupConfiguration) {
            _ = try ServerConfiguration(environment: [
                "EMPIRES_ONLINE_DATA_DIRECTORY": "/unused", "EMPIRES_ONLINE_ALLOW_LOOPBACK_SIGNUP": "1",
                "EMPIRES_ONLINE_BIND_ADDRESS": "0.0.0.0"
            ])
        }
    }

    @Test func loopbackSignupIsClosedIfActualListenerUsesWildcard() async throws {
        try await withServer(environment: ["EMPIRES_ONLINE_ALLOW_LOOPBACK_SIGNUP": "1"]) { application in
            try await application.server.start(address: .hostname("0.0.0.0", port: 0))
            do {
                let port = try #require(application.http.server.shared.localAddress?.port)
                let enroll = OnlineRequest.createAccount(name: "Local player")
                let body = try JSONEncoder().encode(enroll)
                let response = try await application.client.post(URI(string: "http://127.0.0.1:\(port)/v1/online")) {
                    $0.headers.contentType = .json
                    $0.body = .init(bytes: body)
                }
                #expect(response.status == .unauthorized)
            } catch {
                await application.server.shutdown()
                throw error
            }
            await application.server.shutdown()
        }
    }

    @Test func malformedAndUnauthenticatedRequestsReturnPublicErrors() async throws {
        try await withServer { application in
            let unauthorized = try await request(.profile, application)
            #expect(unauthorized.status == .unauthorized)
            #expect(try error(from: unauthorized) == .unauthorized)

            let wrongScheme = try await request(.createAccount(name: "Player"), application, authorization: "Basic fake")
            #expect(wrongScheme.status == .unauthorized)

            let malformed = try await application.sendRequest(
                .POST, "/v1/online", headers: ["Content-Type": "application/json"], body: .init(string: "{")
            )
            #expect(malformed.status == .badRequest)
            #expect(try error(from: malformed) == .invalidRequest)
        }
    }

    @Test func invalidAPNsTokensAreDistinctFromRetryableFailures() {
        #expect(APNSDelivery.outcome(for: APNSError(responseStatus: 410)) == .invalidToken)
        #expect(APNSDelivery.outcome(for: APNSError(responseStatus: 503)) == .retry)
        #expect(APNSDelivery.outcome(for: APNSError(responseStatus: 403)) == .retry)
    }

    @Test(arguments: OnlinePace.allCases)
    func twoAccountsCanPlayThroughTheHTTPContract(pace: OnlinePace) async throws {
        try await withServer(provisioning: true) { application in
            let host = try await createCredential("Host", application)
            let guest = try await createCredential("Guest", application)
            let outsider = try await createCredential("Outsider", application)
            let playing = try await startRoom(pace: pace, host: host, guest: guest, application)
            #expect(playing.status == .playing)
            let decision = try #require(playing.pending.first)
            #expect((decision.deadline != nil) == (pace == .timedLive))
            let move = try #require(playing.gameplay?.legalMoves.first)
            let command = OnlineCommand(decisionID: decision.id, revision: playing.revision, move: move)
            let submit = OnlineRequest.submit(matchID: playing.id, command: command)

            let unauthorized = try await request(.view(matchID: playing.id), application, authorization: outsider)
            #expect(unauthorized.status == .notFound)
            let guestView = try await match(.view(matchID: playing.id), application, authorization: guest)
            #expect(guestView.gameplay?.legalMoves.isEmpty == true)

            let committed = try await match(submit, application, authorization: host)
            let retry = try await match(submit, application, authorization: host)
            #expect(committed.revision > playing.revision)
            #expect(retry.revision == committed.revision)
            #expect(retry.acknowledgedCommandID == command.id)
        }
    }

    private func startRoom(
        pace: OnlinePace, host: String, guest: String, _ application: Application
    ) async throws -> OnlineMatchView {
        let configuration = OnlineConfiguration(
            pace: pace, mode: .classic, rules: .standard, aiSeats: [nil, nil, .classicAI]
        )
        let room = try await match(.createRoom(configuration: configuration, civilization: "rome"), application, authorization: host)
        let joined = try await match(.join(code: room.code, civilization: "egypt"), application, authorization: guest)
        let revision = joined.lobbyRevision
        let ready = OnlineRequest.ready(matchID: room.id, isReady: true, revision: revision)
        _ = try await match(ready, application, authorization: host)
        _ = try await match(ready, application, authorization: guest)
        return try await match(.start(matchID: room.id, revision: revision), application, authorization: host)
    }

    private func createCredential(_ name: String, _ application: Application) async throws -> String {
        let response = try await request(.createAccount(name: name), application, authorization: Self.operatorAuthorization)
        let created = try JSONDecoder().decode(OnlineResponse.self, from: Data(response.body.readableBytesView))
        guard case .account(let account) = created else { throw OnlineError.invalidRequest }
        return "Bearer \(try #require(account.bearer))"
    }

    private func match(
        _ command: OnlineRequest, _ application: Application, authorization: String
    ) async throws -> OnlineMatchView {
        let response = try await request(command, application, authorization: authorization)
        #expect(response.status == .ok)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(OnlineResponse.self, from: Data(response.body.readableBytesView))
        guard case .match(let match) = result else { throw OnlineError.invalidRequest }
        return match
    }

    private func request(
        _ command: OnlineRequest, _ application: Application, authorization: String? = nil
    ) async throws -> TestingHTTPResponse {
        var headers: HTTPHeaders = ["Content-Type": "application/json"]
        if let authorization { headers.add(name: .authorization, value: authorization) }
        return try await application.sendRequest(
            .POST, "/v1/online", headers: headers, body: .init(bytes: try JSONEncoder().encode(command))
        )
    }

    private func error(from response: TestingHTTPResponse) throws -> OnlineError {
        try JSONDecoder().decode(OnlineError.self, from: Data(response.body.readableBytesView))
    }

    private func withServer(
        provisioning: Bool = false, environment: [String: String] = [:],
        _ test: (Application) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let authority = try OnlineAuthority(directory: directory)
        var settings = environment
        settings["EMPIRES_ONLINE_DATA_DIRECTORY"] = directory.path
        if provisioning {
            let tokenFile = directory.appendingPathComponent("provisioning-token")
            try Data("\(Self.operatorToken)\n".utf8).write(to: tokenFile)
            settings["EMPIRES_ONLINE_PROVISIONING_TOKEN_FILE"] = tokenFile.path
        }
        let configuration = try ServerConfiguration(environment: settings)
        let application = try await Application.make(.testing)
        OnlineRoutes.install(on: application, authority: authority, signup: configuration.signup)
        do {
            try await test(application)
        } catch {
            try await application.asyncShutdown()
            throw error
        }
        try await application.asyncShutdown()
    }
}
