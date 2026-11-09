import UIKit
import UserNotifications

@MainActor
final class OnlineAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        OnlineNotificationRouter.shared.receiveDeviceToken(deviceToken)
        if let token = OnlineNotificationRouter.shared.deviceToken {
            Task { await OnlineDeviceRegistrar.shared.register(token: token) }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        OnlineNotificationRouter.shared.registrationDidFail()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let match = Self.matchID(in: response.notification) else { return }
        await OnlineNotificationRouter.shared.openMatch(match)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let match = Self.matchID(in: notification)
        let activeMatch = await OnlineNotificationRouter.shared.activeMatchID
        if let match, match == activeMatch { return [] }
        return [.banner, .sound]
    }

    private nonisolated static func matchID(in notification: UNNotification) -> UUID? {
        guard let value = notification.request.content.userInfo["matchID"] as? String else { return nil }
        return UUID(uuidString: value)
    }
}
