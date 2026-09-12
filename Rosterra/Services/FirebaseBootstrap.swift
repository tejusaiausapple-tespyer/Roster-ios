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
        #if targetEnvironment(macCatalyst)
        // Persistent LevelDB allows only one process. Xcode "Run" while an older
        // Catalyst instance is still alive crashes with:
        //   Failed to open DB … LOCK: Resource temporarily unavailable
        // Catalyst also cannot use Process / NSWorkspace to quit the other copy.
        // In-memory cache avoids the lock; Mac managers have reliable network.
        settings.cacheSettings = MemoryCacheSettings()
        #else
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        #endif
        Firestore.firestore().settings = settings

        isConfigured = true
    }

    static var db: Firestore { Firestore.firestore() }
    static var auth: Auth { Auth.auth() }
}
