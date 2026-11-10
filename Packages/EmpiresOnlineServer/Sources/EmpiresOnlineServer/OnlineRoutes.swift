import EmpiresOnline
import Foundation
import Vapor

enum OnlineRoutes {
    private static let maxRequestBytes = 32 * 1_024

    static func install(on application: Application, authority: OnlineAuthority, signup: OnlineSignupAdmission = .closed) {
        let signupLimit = OnlineSignupLimit()
        application.get("health") { _ in await authority.isReady ? HTTPStatus.ok : .serviceUnavailable }
        application.on(.POST, "v1", "online", body: .collect(maxSize: "32kb")) { request async throws -> Response in
            try await respond(to: request, authority: authority, signup: signup, signupLimit: signupLimit)
        }
    }

    private static func respond(
        to request: Request, authority: OnlineAuthority, signup: OnlineSignupAdmission, signupLimit: OnlineSignupLimit
    ) async throws -> Response {
        do {
            let command = try decode(request)
            let bearer = request.headers.bearerAuthorization?.token
            if request.headers.contains(name: .authorization), bearer == nil {
                throw OnlineError.unauthorized
            }
            if case .createAccount = command {
                let peer = request.remoteAddress?.ipAddress
                // Vapor's serve flags can override the configured bind.
                let listener = request.application.http.server.shared.localAddress?.ipAddress
                let forwarded = request.headers.contains(name: .forwarded) || request.headers.contains(name: .xForwardedFor)
                guard signup.permits(bearer: bearer, directPeer: peer, listener: listener, forwarded: forwarded) else {
                    throw OnlineError.unauthorized
                }
                guard await signupLimit.admit(peer: peer ?? "unknown") else {
                    return try json(OnlineError.unavailable, status: .tooManyRequests)
                }
                return try json(await authority.handle(command, bearer: nil), status: .ok)
            }
            return try json(await authority.handle(command, bearer: bearer), status: .ok)
        } catch let error as OnlineError {
            return try json(error, status: status(for: error))
        } catch {
            request.logger.error("Online command could not be completed")
            return try json(OnlineError.unavailable, status: .serviceUnavailable)
        }
    }

    private static func decode(_ request: Request) throws -> OnlineRequest {
        guard let contentType = request.headers.contentType,
              contentType.type == "application", contentType.subType == "json",
              let body = request.body.data, body.readableBytes <= maxRequestBytes else {
            throw OnlineError.invalidRequest
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(OnlineRequest.self, from: Data(body.readableBytesView))
        } catch {
            throw OnlineError.invalidRequest
        }
    }

    private static func json(_ payload: some Encodable, status: HTTPStatus) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return Response(
            status: status,
            headers: ["Content-Type": "application/json", "Cache-Control": "no-store"],
            body: .init(data: try encoder.encode(payload))
        )
    }

    private static func status(for error: OnlineError) -> HTTPStatus {
        switch error {
        case .unauthorized: .unauthorized
        case .forbidden: .forbidden
        case .notFound: .notFound
        case .conflict: .conflict
        case .invalidRequest, .bankStockUnavailable: .badRequest
        case .unavailable: .serviceUnavailable
        }
    }

}

/// A bounded defense in depth for admitted registration. Trusted ingress
/// applies its own client limits without trusting app-supplied forwarding headers.
private actor OnlineSignupLimit {
    private var windowStart = Date()
    private var perPeer: [String: Int] = [:]
    private var total = 0

    func admit(peer: String) -> Bool {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 60 * 60 {
            windowStart = now
            perPeer.removeAll(keepingCapacity: true)
            total = 0
        }
        guard total < 120, perPeer[peer, default: 0] < 20 else { return false }
        total += 1
        perPeer[peer, default: 0] += 1
        return true
    }
}
