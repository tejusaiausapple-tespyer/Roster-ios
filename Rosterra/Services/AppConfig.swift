import Foundation

/// App-wide configuration constants.
enum AppConfig {
    /// Base URL of the Cloudflare Worker API (same backend as the web app).
    /// The web app calls these as same-origin `/api/...`; the native app must
    /// use the absolute production origin.
    static let apiBaseURL = URL(string: "https://sura-roster.com")!

    /// URL of the web app, surfaced to managers who mistakenly sign in here.
    static let webAppURL = URL(string: "https://sura-roster.com")!

    /// Support contact address for help, privacy, and account-deletion requests.
    static let supportEmail = "support@sura-roster.com"

    /// Public legal pages hosted on the marketing site.
    static let privacyPolicyURL = URL(string: "https://sura-roster.com/privacy")!
    static let termsOfServiceURL = URL(string: "https://sura-roster.com/terms")!

    /// Remote push master switch. Local shift reminders work regardless of
    /// this flag.
    static let pushEnabled = true

    /// Staff may start their shift this many seconds before the rostered
    /// start ("early check-in"). Paid time still begins at the rostered start.
    static let earlyClockInWindow: TimeInterval = 5 * 60

    /// After this idle interval in the background, re-require the device-auth gate.
    /// Mirrors the web app's 2-minute re-lock behaviour.
    static let deviceAuthBackgroundRelock: TimeInterval = 2 * 60

    /// The relying-party identifier (domain) for Apple passkeys. Must match the
    /// `webcredentials` entry in the app's Associated Domains entitlement AND the
    /// `apple-app-site-association` file hosted at that domain.
    static let passkeyRelyingParty = "sura-roster.com"
}
