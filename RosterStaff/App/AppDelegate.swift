import UIKit
import UserNotifications

/// App lifecycle hooks. Push / FCM wiring is disabled on personal Apple teams;
/// re-enable with FirebaseMessaging when a paid Developer account is ready.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseBootstrap.configure()
        if FirebaseBootstrap.isConfigured {
            UNUserNotificationCenter.current().delegate = self
        }
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }
}
