import UIKit
import UserNotifications

/// App lifecycle hooks, including remote push / FCM registration.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseBootstrap.configure()
        // Local shift reminders need the delegate regardless of Firebase, or
        // foreground banners won't present.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Remote push registration (inert until AppConfig.pushEnabled)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.updateAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal: local shift reminders keep working without APNs.
        print("APNs registration failed: \(error.localizedDescription)")
    }

    /// Silent background pushes (content-available) — covers background and
    /// terminated-then-woken states once push is enabled.
    /// Completion-handler form: the async variant trips Swift 6 sendability
    /// checking (`[AnyHashable: Any]` crossing into the main actor).
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            completionHandler(await NotificationService.shared.handleBackgroundPush(userInfo))
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Foreground delivery. Fires for local notifications today and for
    /// remote pushes automatically once APNs/FCM is enabled — the haptic
    /// wiring below needs no changes at that point.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        NotificationService.shared.handleForegroundDelivery(notification)
        return [.banner, .badge, .sound]
    }

    /// The user tapped a notification (from a banner or notification centre).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        NotificationService.shared.handleNotificationTap(response)
    }
}
