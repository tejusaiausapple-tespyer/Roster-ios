import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseCrashlytics

/// Configures Firebase once at launch and exposes shared handles.
/// Firestore is configured with offline persistence so cached shifts/timesheets
/// remain available offline — matching the web app's persistent local cache.
enum FirebaseBootstrap {
    private(set) static var isConfigured = false

    /// True when the real GoogleService-Info.plist is present in the bundle.
    static var hasConfigFile: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    static func configure() {
        guard !isConfigured else { return }
        guard hasConfigFile else {
            // Left unconfigured on purpose; RootView shows a setup message.
            return
        }
        FirebaseApp.configure()
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        Firestore.firestore().settings = settings

        isConfigured = true
    }

    static var db: Firestore { Firestore.firestore() }
    static var auth: Auth { Auth.auth() }
}
