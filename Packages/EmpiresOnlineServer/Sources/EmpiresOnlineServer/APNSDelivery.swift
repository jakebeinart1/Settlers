import APNS
import APNSCore
import EmpiresOnline
import Foundation

struct APNSDelivery: Sendable {
    private static let defaultExpiry: TimeInterval = 60 * 60
    private static let requestTimeout: Duration = .seconds(12)

    private let client: APNSClient<JSONDecoder, JSONEncoder>
    private let topic: String
    private let environment: OnlinePushEnvironment

    init(configuration: PushConfiguration) throws {
        do {
            let key = try String(contentsOf: configuration.keyFile, encoding: .utf8)
            client = APNSClient(
                configuration: .init(
                    authenticationMethod: .jwt(
                        privateKey: try .init(pemRepresentation: key),
                        keyIdentifier: configuration.keyID,
                        teamIdentifier: configuration.teamID
                    ),
                    environment: configuration.isProduction ? .production : .development
                ),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder()
            )
        } catch {
            throw ServerConfigurationError.invalidPushKey
        }
        environment = configuration.isProduction ? .production : .development
        topic = configuration.topic
    }

    func deliver(_ push: OnlinePush, now: Date = .now) async -> OnlinePushResult {
        guard push.environment == environment else { return .retry }
        guard let notification = notification(for: push, now: now) else { return .sent }
        do {
            try await send(notification, deviceToken: push.token)
            return .sent
        } catch let error as APNSError {
            return Self.outcome(for: error)
        } catch {
            return .retry
        }
    }

    func shutdown() async throws { try await client.shutdown() }

    static func outcome(for error: APNSError) -> OnlinePushResult {
        if error.responseStatus == 410 || error.reason == .badDeviceToken || error.reason == .deviceTokenNotForTopic {
            return .invalidToken
        }
        return .retry
    }

    private func notification(for push: OnlinePush, now: Date) -> APNSAlertNotification<MatchRoute>? {
        let expiresAt = push.expiresAt ?? now.addingTimeInterval(Self.defaultExpiry)
        guard expiresAt > now else { return nil }
        var notification = APNSAlertNotification(
            alert: .init(title: .raw("Your move in Empires")),
            expiration: .timeIntervalSince1970InSeconds(Int(expiresAt.timeIntervalSince1970)),
            priority: .immediately,
            topic: topic,
            payload: MatchRoute(matchID: push.matchID),
            threadID: push.matchID.uuidString,
            apnsID: push.id
        )
        // A retry refers to the same durable action and coalesces while offline.
        notification.collapseID = push.decisionID.uuidString
        return notification
    }

    private func send(_ notification: APNSAlertNotification<MatchRoute>, deviceToken: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask { _ = try await client.sendAlertNotification(notification, deviceToken: deviceToken) }
            tasks.addTask {
                try await Task.sleep(for: Self.requestTimeout)
                throw DeliveryTimeout()
            }
            defer { tasks.cancelAll() }
            _ = try await tasks.next()
        }
    }

    private struct MatchRoute: Encodable, Sendable {
        let matchID: UUID
    }

    private struct DeliveryTimeout: Error {}
}
