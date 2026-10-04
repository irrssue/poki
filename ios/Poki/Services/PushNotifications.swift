import Foundation
import Observation
import UIKit
import UserNotifications

/// Registration operations are serialized so sign-out cannot race a token callback.
@MainActor
@Observable
final class PushNotifications {
    var status = "Pokes are available in your in-app inbox."
    var denied = false
    var busy = false
    private var token: String?
    private var owner: UUID?
    private var account: AccountService?
    private var operation: Task<Void, Error>?
    private var generation = UUID()
    private var signingOut = false
    private var registeredToken: String?
    private var registeredOwner: UUID?
    private var registeredAt = Date.distantPast
    private let defaults: UserDefaults
    private let environment: String
    private let deviceID: UUID
    var available: Bool { ["sandbox", "production"].contains(environment) }

    init(defaults: UserDefaults = .standard, environment: String? = nil) {
        self.defaults = defaults
        self.environment = environment ?? (Bundle.main.object(forInfoDictionaryKey: "PokiPushEnvironment") as? String ?? "")
        if let value = defaults.string(forKey: "poki.push.device"), let id = UUID(uuidString: value) { deviceID = id }
        else { deviceID = UUID(); defaults.set(deviceID.uuidString, forKey: "poki.push.device") }
    }

    func synchronize(owner: UUID, account: AccountService) async {
        self.owner = owner; self.account = account
        guard available, !signingOut else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        denied = settings.authorizationStatus == .denied
        if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
            await registerIfNeeded()
        } else if denied {
            status = "Notifications are off. You can enable them in Settings."
            // Permission changes stop queued deliveries too.
            do { try await unregister(account: account) } catch { status = "Open Poki online to finish turning off delivery." }
            signingOut = false
        }
    }

    func enable() async {
        guard available, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
                UIApplication.shared.registerForRemoteNotifications()
                status = "Connecting notifications…"
            } else { denied = true; status = "Notifications are off. You can enable them in Settings." }
        } catch { status = "Could not enable notifications. Try again." }
    }

    func receivedToken(_ data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        await registerIfNeeded()
    }

    private func registerIfNeeded() async {
        guard available, !signingOut, let owner, let account, let token,
              registeredOwner != owner || registeredToken != token || Date().timeIntervalSince(registeredAt) > 86400 else { return }
        let previous = operation
        let expected = generation
        let task = Task { @MainActor in
            _ = try? await previous?.value
            guard self.generation == expected, !self.signingOut else { return }
            // Persist before the request: a lost response may still have registered remotely.
            self.defaults.set(true, forKey: "poki.push.mayBeRegistered")
            let _: EmptyResponse = try await account.rpc("poki_register_device", body: [
                "device_id": self.deviceID.uuidString, "device_token": token, "apns_environment": self.environment
            ])
            guard self.generation == expected else { return }
            self.registeredOwner = owner; self.registeredToken = token; self.registeredAt = Date()
            self.status = "Notifications enabled on this iPhone."
        }
        operation = task
        do { try await task.value } catch { status = "Could not connect notifications. Poki will retry while open." }
    }

    func unregister(account: AccountService) async throws {
        signingOut = true; generation = UUID()
        _ = try? await operation?.value
        guard defaults.bool(forKey: "poki.push.mayBeRegistered") else { return }
        do {
            let _: EmptyResponse = try await account.rpc("poki_unregister_device", body: ["device_id": deviceID.uuidString])
            defaults.set(false, forKey: "poki.push.mayBeRegistered")
            registeredOwner = nil; registeredToken = nil
        } catch {
            signingOut = false
            throw ServiceFailure(message: "Connect to the internet to stop notifications before signing out, then try again.")
        }
    }

    func clearAfterSignOut() {
        generation = UUID(); signingOut = false; owner = nil; account = nil
        registeredOwner = nil; registeredToken = nil
        defaults.set(false, forKey: "poki.push.mayBeRegistered")
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UIApplication.shared.unregisterForRemoteNotifications()
        status = "Pokes are available in your in-app inbox."
    }
}

@MainActor
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel?
    private var waitingToken: Data?
    private var waitingRoute: (UUID, UUID)?

    func attach(_ model: AppModel) {
        self.model = model
        if let waitingToken { Task { await model.push.receivedToken(waitingToken) }; self.waitingToken = nil }
        if let (recipient, sender) = waitingRoute { model.openNotification(recipient: recipient, sender: sender); waitingRoute = nil }
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard let model else { waitingToken = deviceToken; return }
        Task { await model.push.receivedToken(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        model?.push.status = "Could not connect notifications. Try again later."
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let recipient = (info["recipient_id"] as? String).flatMap(UUID.init(uuidString:))
        let sender = (info["sender_id"] as? String).flatMap(UUID.init(uuidString:))
        if let recipient, let sender {
            Task { @MainActor in
                if let model = self.model { model.openNotification(recipient: recipient, sender: sender) }
                else { self.waitingRoute = (recipient, sender) }
            }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The foreground app refreshes its authorized inbox; avoid stale account previews.
        completionHandler([])
        Task { @MainActor in await self.model?.refresh() }
    }
}
