import UIKit

/// Semantic haptic feedback, mirroring the web app's `triggerHaptic` patterns
/// (see src/lib/haptics.ts) but using native iOS feedback generators.
///
/// Two layers:
/// - Primitives (`light`, `success`, `selection`, …) map 1:1 onto UIKit
///   feedback generators.
/// - Semantic events (`tabChange`, `signIn`, `save`, …) name what happened in
///   the app. Views and view models should prefer these so the whole app stays
///   consistent and the mapping can be tuned in one place.
enum Haptics {
    // MARK: - Primitives

    static func light() { impact(.light) }
    static func medium() { impact(.medium) }
    static func heavy() { impact(.heavy) }
    static func soft() { impact(.soft) }
    static func rigid() { impact(.rigid) }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    // MARK: - Semantic events

    /// Switching tabs (bottom tab bar or the iPad sidebar).
    static func tabChange() { selection() }

    /// Successful sign-in — manual, Face ID, or passkey.
    static func signIn() { success() }

    /// User-initiated sign-out.
    static func signOut() { impact(.medium) }

    /// Forced sign-out (account locked/inactive while signed in).
    static func forcedSignOut() { warning() }

    /// A save completed (settings, profile, shift edits, …).
    static func saveSuccess() { success() }
    static func saveError() { error() }

    /// A submit completed (hours, task completion, forms, …).
    static func submitSuccess() { success() }
    static func submitError() { error() }

    /// Face ID / Touch ID / device-passcode authentication.
    static func authSuccess() { success() }
    static func authFailure() { error() }

    // MARK: - Notifications
    //
    // Push infrastructure is stubbed until the Apple Developer account is
    // approved (see NotificationService). These events are already wired from
    // AppDelegate's UNUserNotificationCenterDelegate, so once APNs/FCM is
    // enabled, remote notifications get haptics with no further changes.
    enum Notification {
        /// A notification arrived while the app is in the foreground.
        static func delivered() { Haptics.soft() }

        /// The user tapped a notification (banner or notification centre).
        static func opened() { Haptics.light() }

        /// A notification carrying urgent payload (e.g. shift cancelled).
        static func urgent() { Haptics.warning() }
    }

    // MARK: - Generators

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
