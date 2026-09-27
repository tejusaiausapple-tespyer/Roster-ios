import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseCrashlytics
#if targetEnvironment(macCatalyst)
import Darwin
#endif

/// Configures Firebase once at launch and exposes shared handles.
/// Firestore is configured with offline persistence so cached shifts/timesheets
/// remain available offline — matching the web app's persistent local cache.
enum FirebaseBootstrap {
    private(set) static var isConfigured = false
#if targetEnvironment(macCatalyst)
    // Keep the advisory lock descriptor open for the process lifetime.
    private static var cacheLockDescriptor: Int32 = -1

    private static func canOpenPersistentCache() -> Bool {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return false }
        let path = directory.appendingPathComponent("roster-firestore-cache.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        cacheLockDescriptor = descriptor
        return true
    }
#endif

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
        // A normal Mac launch uses the same on-device cache as iOS. A second
        // Catalyst process must not open the same LevelDB database; use memory
        // for that duplicate process rather than crashing on its cache lock.
#if targetEnvironment(macCatalyst)
        if canOpenPersistentCache() {
            settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        } else {
            settings.cacheSettings = MemoryCacheSettings()
        }
#else
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
#endif
        Firestore.firestore().settings = settings

        isConfigured = true
    }

    static var db: Firestore { Firestore.firestore() }
    static var auth: Auth { Auth.auth() }
}
