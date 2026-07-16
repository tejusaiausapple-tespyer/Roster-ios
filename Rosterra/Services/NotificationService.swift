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
/// which is uploaded into `users/{uid}/notificationTokens/{docId}` — the same
/// subcollection the web app writes to, which the Worker's send pipeline
/// actually reads from (see `syncTokenAfterLogin` for why this matters: a
/// flat field on the user document, the previous approach here, is invisible
/// to that pipeline).
final class NotificationService: NSObject {
    static let shared = NotificationService()

    /// Payload key a push can set to escalate the haptic (e.g. shift cancelled).
    private static let urgentPayloadKey = "urgent"

    /// UserDefaults key for the last-registered token, so `clearTokenOnLogout`
    /// can compute the same subcollection doc id after an app relaunch (it's
    /// only handed a uid, not the token itself).
    private static let lastTokenDefaultsKey = "roster_last_fcm_token"

    /// Cached until a user is signed in (token can arrive before login).
    private var pendingToken: String?

    // MARK: - Authorization & registration

    /// Ask for notification permission (first call shows the system prompt)
    /// and, when push is enabled, register with APNs. Called on every login;
    /// iOS only prompts once, so repeat calls are free.
    ///
    /// Permission enables both **local** shift reminders (scheduled on-device
    /// from the last fetched roster) and remote push. The app does not keep
    /// running after it is closed — iOS delivers the alerts.
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

    /// Current authorization for Account UI.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    var isAuthorized: Bool {
        get async {
            let status = await authorizationStatus()
            return status == .authorized || status == .provisional
        }
    }

    // MARK: - Token pipeline (APNs / FCM)

    /// APNs token from AppDelegate, handed to FCM. FCM exchanges it for a
    /// registration token, delivered via `MessagingDelegate` below.
    func updateAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Persist the push token on the signed-in user's document.
    func updateFCMToken(_ token: String?) {
        pendingToken = token
        syncTokenAfterLogin()
    }

    /// Upload any cached token once a user is signed in. Writes into
    /// `users/{uid}/notificationTokens/{docId}` — the SAME subcollection the
    /// web app writes to and the Worker's send pipeline (`listUserNotificationTokens`
    /// in worker/handlers/notifications.ts) reads from. A flat `fcmToken`
    /// field on the user document (the old approach here) is never read by
    /// that pipeline, so tokens written that way are silently undeliverable —
    /// this was a real, previously-shipped bug: iOS push has never actually
    /// been reachable by the send pipeline despite the APNs/FCM wiring being
    /// otherwise correct. Schema and field set must match
    /// isValidNotificationTokenData in firestore.rules exactly (extra keys
    /// are rejected); 'ios-native' is already whitelisted there as a valid
    /// platform value.
    func syncTokenAfterLogin() {
        guard AppConfig.pushEnabled,
              let token = pendingToken,
              let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(token, forKey: Self.lastTokenDefaultsKey)
        let ref = Self.tokenDocRef(uid: uid, token: token)
        Task {
            do {
                let snapshot = try await ref.getDocument()
                let userAgent = Self.userAgentDescription()
                if snapshot.exists {
                    try await ref.updateData([
                        "platform": "ios-native",
                        "userAgent": userAgent,
                        "enabled": true,
                        "updatedAt": FieldValue.serverTimestamp(),
                    ])
                } else {
                    try await ref.setData([
                        "token": token,
                        "platform": "ios-native",
                        "userAgent": userAgent,
                        "enabled": true,
                        "createdAt": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp(),
                    ])
                }
            } catch {
                // Best-effort, matching the web app's fire-and-forget token sync.
            }
        }
    }

    /// Remove the token on sign-out so a shared device stops receiving the
    /// previous user's pushes. Deletes the same subcollection doc
    /// `syncTokenAfterLogin` writes — uses the last-registered token (cached
    /// in UserDefaults, since this method is only handed a uid) to compute
    /// its doc id.
    func clearTokenOnLogout(uid: String) {
        guard AppConfig.pushEnabled,
              let token = UserDefaults.standard.string(forKey: Self.lastTokenDefaultsKey) else { return }
        Self.tokenDocRef(uid: uid, token: token).delete()
        UserDefaults.standard.removeObject(forKey: Self.lastTokenDefaultsKey)
    }

    /// Same doc id scheme as the web app's `getTokenDocId` (`encodeURIComponent(token)`
    /// there) — percent-encode everything outside the unreserved set so the
    /// token is always a valid Firestore document id. Doesn't need to match
    /// the web app's exact encoding byte-for-byte; iOS and web tokens are
    /// always separate documents regardless.
    private static func tokenDocRef(uid: String, token: String) -> DocumentReference {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let docId = token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
        return Firestore.firestore().collection("users").document(uid)
            .collection("notificationTokens").document(docId)
    }

    private static func userAgentDescription() -> String {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion) / \(device.model)"
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
            var info = response.notification.request.content.userInfo
            // Local reminder ids encode the slot; surface it for routing.
            info["identifier"] = response.notification.request.identifier
            AppRouter.shared?.handleNotificationUserInfo(info)
        }
    }

    /// Silent background push (content-available) — refresh data so the app
    /// is current when next opened. Inert until push is enabled. Main-actor
    /// so the non-Sendable payload never crosses an isolation boundary.
    @MainActor
    func handleBackgroundPush(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        .newData
    }

    /// Local backup when a timesheet decision arrives via Firestore while the
    /// process is alive (foreground / brief background). When the app is fully
    /// closed, server FCM/APNs is the path that still delivers.
    func postTimesheetDecisionLocally(
        timesheetId: String,
        approved: Bool,
        body: String
    ) {
        let id = "timesheet-decision.\(approved ? "approved" : "rejected").\(timesheetId)"
        let content = UNMutableNotificationContent()
        content.title = approved ? "Timesheet approved" : "Timesheet needs changes"
        content.body = body
        content.sound = .default
        content.userInfo = [
            "event": approved ? "timesheet-approved" : "timesheet-rejected",
            "kind": approved ? "timesheet-approved" : "timesheet-rejected",
            "timesheetId": timesheetId,
            "shiftId": timesheetId,
            "url": "/staff/roster",
        ]
        // Near-immediate delivery so it still shows if the process is suspended.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    /// Local backup when newly published shifts appear on the staff listener
    /// while the process is alive. Closed-app delivery still relies on FCM.
    func postRosterPublishedLocally(newShiftCount: Int) {
        let id = "roster-published.\(Int(Date().timeIntervalSince1970))"
        let content = UNMutableNotificationContent()
        content.title = "Roster published"
        content.body = newShiftCount == 1
            ? "Your manager published a new shift. Tap to view."
            : "Your manager published \(newShiftCount) new shifts. Tap to view."
        content.sound = .default
        content.userInfo = [
            "event": "roster-published",
            "kind": "roster-published",
            "url": "/staff/roster",
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
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
