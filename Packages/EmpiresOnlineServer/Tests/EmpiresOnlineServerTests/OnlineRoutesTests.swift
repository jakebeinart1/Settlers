import APNSCore
import EmpiresOnline
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import EmpiresOnlineServer

@Suite struct OnlineRoutesTests {
    @Test func accountCredentialCanReadItsProfile() async throws {
        try await withServer { application in
            let health = try await application.sendRequest(.GET, "/health")
            #expect(health.status == .ok)

            let created = try await request(.createAccount(name: "Player"), application)
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
        try await withServer { application in
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
        let response = try await request(.createAccount(name: name), application)
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

    private func withServer(_ test: (Application) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = try OnlineAuthority(directory: directory)
        let application = try await Application.make(.testing)
        OnlineRoutes.install(on: application, authority: authority)
        do {
            try await test(application)
        } catch {
            try await application.asyncShutdown()
            try FileManager.default.removeItem(at: directory)
            throw error
        }
        try await application.asyncShutdown()
        try FileManager.default.removeItem(at: directory)
    }
}
