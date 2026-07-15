import Foundation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

/// Notification hub: permission, local shift reminders, and the remote-push
/// pipeline.
///
/// LOCAL notifications (shift reminders — see ShiftReminderScheduler) are
/// fully live: they need no Apple entitlement.
///
/// REMOTE push is wired end-to-end and live behind `AppConfig.pushEnabled`.
/// APNs hands its device token to FCM (`updateAPNSToken`), and FCM calls back
/// with the registration token via `MessagingDelegate` (`updateFCMToken`),
/// which is what actually gets uploaded to the user document — the backend's
/// send pipeline sends through FCM, not raw APNs.
final class NotificationService: NSObject {
    static let shared = NotificationService()

    /// Payload key a push can set to escalate the haptic (e.g. shift cancelled).
    private static let urgentPayloadKey = "urgent"

    /// Cached until a user is signed in (token can arrive before login).
    private var pendingToken: String?

    // MARK: - Authorization & registration

    /// Ask for notification permission (first call shows the system prompt)
    /// and, when push is enabled, register with APNs. Called on every login;
    /// iOS only prompts once, so repeat calls are free.
    func requestAuthorizationAndRegister() {
        if AppConfig.pushEnabled {
            Messaging.messaging().delegate = self
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            if AppConfig.pushEnabled {
                Task { @MainActor in
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - Token pipeline (APNs / FCM)

    /// APNs token from AppDelegate, handed to FCM. FCM exchanges it for a
    /// registration token, delivered via `MessagingDelegate` below.
    func updateAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Persist the push token on the signed-in user's document — the same
    /// field the web app writes, so the Worker's send pipeline covers both.
    func updateFCMToken(_ token: String?) {
        pendingToken = token
        syncTokenAfterLogin()
    }

    /// Upload any cached token once a user is signed in.
    func syncTokenAfterLogin() {
        guard AppConfig.pushEnabled,
              let token = pendingToken,
              let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).setData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
            "fcmPlatform": "ios",
        ], merge: true)
    }

    /// Remove the token on sign-out so a shared device stops receiving the
    /// previous user's pushes.
    func clearTokenOnLogout(uid: String) {
        guard AppConfig.pushEnabled else { return }
        Firestore.firestore().collection("users").document(uid).setData([
            "fcmToken": FieldValue.delete(),
        ], merge: true)
    }

    // MARK: - Delivery handling (local now; remote automatically once enabled)

    /// A notification arrived while the app is foregrounded.
    func handleForegroundDelivery(_ notification: UNNotification) {
        Task { @MainActor in
            if isUrgent(notification.request.content.userInfo) {
                Haptics.Notification.urgent()
            } else {
                Haptics.Notification.delivered()
            }
        }
    }

    /// The user tapped a notification — from a banner, notification centre,
    /// or a cold launch (terminated state); UNUserNotificationCenter delivers
    /// all three through the same delegate callback.
    func handleNotificationTap(_ response: UNNotificationResponse) {
        Task { @MainActor in
            Haptics.Notification.opened()
        }
        // Deep-link routing hook: userInfo carries shiftId for shift events.
        // Route via AppRouter here when notification categories grow.
    }

    /// Silent background push (content-available) — refresh data so the app
    /// is current when next opened. Inert until push is enabled. Main-actor
    /// so the non-Sendable payload never crosses an isolation boundary.
    @MainActor
    func handleBackgroundPush(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        .newData
    }

    private func isUrgent(_ userInfo: [AnyHashable: Any]) -> Bool {
        if let flag = userInfo[Self.urgentPayloadKey] as? Bool { return flag }
        if let flag = userInfo[Self.urgentPayloadKey] as? String { return flag == "true" || flag == "1" }
        return false
    }
}

extension NotificationService: MessagingDelegate {
    /// Fires on initial token issuance and again whenever FCM rotates the
    /// token — the only correct place to capture it (do not derive it from
    /// the raw APNs token).
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        updateFCMToken(fcmToken)
    }
}
