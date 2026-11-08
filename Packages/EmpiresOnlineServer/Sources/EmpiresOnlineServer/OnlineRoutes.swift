import EmpiresOnline
import Foundation
import Vapor

enum OnlineRoutes {
    private static let maxRequestBytes = 32 * 1_024

    static func install(on application: Application, authority: OnlineAuthority) {
        application.get("health") { _ in HTTPStatus.ok }
        application.on(.POST, "v1", "online", body: .collect(maxSize: "32kb")) { request async throws -> Response in
            try await respond(to: request, authority: authority)
        }
    }

    private static func respond(to request: Request, authority: OnlineAuthority) async throws -> Response {
        do {
            let command = try decode(request)
            let bearer = request.headers.bearerAuthorization?.token
            if request.headers.contains(name: .authorization), bearer == nil {
                throw OnlineError.unauthorized
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
        case .invalidRequest: .badRequest
        case .unavailable: .serviceUnavailable
        }
    }

}
