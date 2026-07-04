import Foundation

/// Push notification registration — stubbed while running on a personal Apple team.
/// Re-enable APNs/FCM when a paid Developer account is ready (see WHEN_DEVELOPER_ACCOUNT_READY.md).
final class NotificationService: NSObject {
    static let shared = NotificationService()

    func requestAuthorizationAndRegister() {
        // No-op: personal teams cannot use Push Notifications capability.
    }

    func updateFCMToken(_ token: String?) {
        // No-op
    }

    func syncTokenAfterLogin() {
        // No-op
    }
}
