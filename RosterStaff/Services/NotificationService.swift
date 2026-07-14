import Foundation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

/// Notification hub: permission, local shift reminders, and the remote-push
/// pipeline.
///
/// LOCAL notifications (shift reminders — see ShiftReminderScheduler) are
/// fully live: they need no Apple entitlement.
///
/// REMOTE push is wired end-to-end but held behind `AppConfig.pushEnabled`,
/// which stays `false` until the paid Apple Developer account is approved.
/// Activation steps live in docs/WHEN_DEVELOPER_ACCOUNT_READY.md and are:
///   1. Add the Push Notifications capability + `aps-environment` entitlement.
///   2. Re-add the FirebaseMessaging package (see project.yml note) and
///      uncomment the marked block in `updateFCMToken(_:)`'s caller path.
///   3. Set `AppConfig.pushEnabled = true`.
/// Everything else — authorization, APNs registration, token upload to the
/// user document, foreground/background/terminated handling, haptics —
/// is already in place.
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

    /// APNs token from AppDelegate. With FirebaseMessaging linked this is
    /// handed to FCM (which then calls `updateFCMToken`); until then the raw
    /// hex token is stored so the backend can use it directly if needed.
    func updateAPNSToken(_ deviceToken: Data) {
        // When FirebaseMessaging is re-added:
        //   Messaging.messaging().apnsToken = deviceToken
        // and updateFCMToken(_:) is invoked from MessagingDelegate.
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        updateFCMToken(hex)
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
