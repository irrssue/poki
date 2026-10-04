import SwiftUI
import UserNotifications
import UIKit

@MainActor @Observable final class NotificationController {
    static let shared = NotificationController()
    var permission: UNAuthorizationStatus = .notDetermined
    var error: String?
    var pendingRecipient: UUID?
    var token: String?
    var owner: UUID?
    var onToken: ((String) -> Void)?
    var onOpen: (() -> Void)?
    var onForeground: (() -> Void)?

    func refreshPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if owner != nil && [.authorized, .provisional, .ephemeral].contains(permission) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    func enable() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            error = nil
            await refreshPermission()
        } catch { self.error = "Could not request notifications. Please try again." }
    }
    func clear() {
        owner = nil; token = nil; pendingRecipient = nil; error = nil
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    func receive(token data: Data) {
        guard owner != nil else { return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        self.token = token; error = nil; onToken?(token)
    }
    func open(recipient: UUID) { pendingRecipient = recipient; onOpen?() }
}

final class PokiAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationController.shared.receive(token: deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        NotificationController.shared.error = "Notifications could not connect on this device. Please try again."
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["recipient_id"] as? String,
              let recipient = UUID(uuidString: raw), response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { NotificationController.shared.open(recipient: recipient) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let raw = notification.request.content.userInfo["recipient_id"] as? String,
              let recipient = UUID(uuidString: raw) else { return [] }
        return await MainActor.run {
            let controller = NotificationController.shared
            guard controller.owner == recipient else { return [] }
            // The banner is immediate; the refresh brings the inbox and badge up to date.
            controller.onForeground?()
            return [.banner, .sound]
        }
    }
}
