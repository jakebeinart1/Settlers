import Foundation
import Observation
import UIKit
import UserNotifications

enum OnlineRoute: Equatable {
    case match(UUID)
    case join(String)
}

/// Pushes and invite links are navigation hints. Opening a route always
/// fetches the current match through the authenticated transport.
@MainActor
@Observable
final class OnlineNotificationRouter {
    static let shared = OnlineNotificationRouter()
    var route: OnlineRoute?
    var activeMatchID: UUID?
    private(set) var deviceToken: String?
    private(set) var registrationFailed = false

    func open(url: URL) -> Bool {
        guard url.scheme == "empires", url.host == "online", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "match":
            guard let id = UUID(uuidString: parts[1]) else { return false }
            openMatch(id)
        case "join":
            let code = parts[1].uppercased()
            guard (4 ... 32).contains(code.count),
                  code.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 90).contains($0) }) else {
                return false
            }
            route = .join(code)
        default: return false
        }
        return true
    }

    func openMatch(_ id: UUID) { route = .match(id) }

    func receiveDeviceToken(_ data: Data) {
        registrationFailed = false
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
    }

    func registrationDidFail() { registrationFailed = true }
    func registrationDidSucceed() { registrationFailed = false }

    func requestNotifications() async throws -> Bool {
        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        if allowed {
            registrationFailed = false
            UIApplication.shared.registerForRemoteNotifications()
        }
        return allowed
    }

    func registerIfAlreadyAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional || status == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
