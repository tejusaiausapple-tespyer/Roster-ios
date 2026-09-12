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

    /// Weak handle for silent-push refresh (owned by SwiftUI `@State`).
    @MainActor
    private weak var repository: RosterRepository?

    /// A notification tap that arrived before `AppRouter.shared` was set —
    /// e.g. `AppDelegate` registers as the `UNUserNotificationCenter`
    /// delegate synchronously in `didFinishLaunchingWithOptions`, which can
    /// win the race against `RosterraApp`'s `.onAppear` on a cold launch via
    /// notification tap. Buffered here and replayed once the router becomes
    /// available, instead of being silently dropped by `AppRouter.shared?`.
    @MainActor
    private var pendingTapUserInfo: [AnyHashable: Any]?

    /// Called once from `AuthViewModel.bind` so background pushes can refresh.
    @MainActor
    func bind(repository: RosterRepository) {
        self.repository = repository
    }

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
        let previousToken = UserDefaults.standard.string(forKey: Self.lastTokenDefaultsKey)
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
                // A silent FCM rotation on an already-registered device —
                // never fires on first-ever registration on this device
                // (nothing stored yet) or when the token is unchanged. This
                // carries the device's single-active-notification-device
                // status (if any) forward to the new token doc; a brand-new
                // doc with no previous token to compare against is left
                // alone deliberately — the Worker's fail-open read treats a
                // missing `active` field as active, so a genuinely new
                // device is reachable by default until something else
                // explicitly deactivates it.
                if let previousToken, previousToken != token {
                    await WorkerAPIClient.shared.activateDevice(token: token, previousToken: previousToken, reason: "refresh")
                }
            } catch {
                // Best-effort, matching the web app's fire-and-forget token sync.
            }
        }
    }

    /// Called right after a fresh sign-in succeeds (`AuthViewModel.login()`)
    /// — distinct from `syncTokenAfterLogin()`, which also fires on every
    /// resolved auth state (including a restored session) and must never
    /// claim active status on its own: that could let an unrelated app
    /// relaunch silently steal active status back from wherever the account
    /// most recently logged in. Only a genuine credential login claims this
    /// device as the account's single active notification device. No-ops if
    /// no token is registered yet on this device — nothing to claim with.
    func claimActiveDeviceOnLogin() {
        guard AppConfig.pushEnabled,
              let token = pendingToken ?? UserDefaults.standard.string(forKey: Self.lastTokenDefaultsKey) else { return }
        Task {
            await WorkerAPIClient.shared.activateDevice(token: token, previousToken: nil, reason: "login")
        }
    }

    /// Remove the token on sign-out so a shared device stops receiving the
    /// previous user's pushes. Deletes the same subcollection doc
    /// `syncTokenAfterLogin` writes — uses the last-registered token (cached
    /// in UserDefaults, since this method is only handed a uid) to compute
    /// its doc id.
    ///
    /// Must be awaited by the caller BEFORE `AuthService.signOut()` runs —
    /// the delete rule requires `request.auth.uid == userId` (this uid), so
    /// once sign-out (or a new login) changes the auth context, a
    /// still-in-flight or offline-queued delete gets silently rejected and
    /// the old token doc survives, which is exactly what let a device keep
    /// receiving the previous account's pushes after switching users.
    func clearTokenOnLogout(uid: String) async {
        guard AppConfig.pushEnabled,
              let token = UserDefaults.standard.string(forKey: Self.lastTokenDefaultsKey) else { return }
        try? await Self.tokenDocRef(uid: uid, token: token).delete()
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
        #if targetEnvironment(macCatalyst)
        // Catalyst runs under the scaled-iPad idiom, so `UIDevice` reports
        // "iPadOS / iPad" here. With the single-active-device gate that leaves
        // two indistinguishable iPad rows and no way to tell which one just
        // took over the account's notifications.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion) / Mac"
        #else
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion) / \(device.model)"
        #endif
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
            if let router = AppRouter.shared {
                router.handleNotificationUserInfo(info)
            } else {
                pendingTapUserInfo = info
            }
        }
    }

    /// Call once `AppRouter.shared` is set (`RosterraApp`'s `.onAppear`) to
    /// deliver a tap that arrived too early instead of leaving it dropped.
    @MainActor
    func replayPendingTapIfNeeded() {
        guard let info = pendingTapUserInfo, let router = AppRouter.shared else { return }
        pendingTapUserInfo = nil
        router.handleNotificationUserInfo(info)
    }

    /// Silent background push (content-available) — pull fresh Firestore data
    /// so the next foreground open is current. Listeners alone may not wake
    /// while suspended.
    @MainActor
    func handleBackgroundPush(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard Auth.auth().currentUser != nil else { return .noData }
        guard let repository else { return .noData }
        await ServerClock.shared.sync()
        await PendingEmailChange.reconcileIfNeeded()
        await repository.refreshFromServer()
        return .newData
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
