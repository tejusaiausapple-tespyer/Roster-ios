import Foundation
import FirebaseRemoteConfig

// MARK: - SemanticVersion

/// A `major.minor.patch` version, parsed leniently (missing components default
/// to 0, a `-suffix` like "-beta.1" is ignored) so it can compare both
/// `CFBundleShortVersionString` values and hand-typed Remote Config / App Store strings.
struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let core = string.split(separator: "-", maxSplits: 1).first.map(String.init) ?? string
        let parts = core.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var values: [Int] = []
        for part in parts.prefix(3) {
            guard let value = Int(part) else { return nil }
            values.append(value)
        }
        major = values[0]
        minor = values.count > 1 ? values[1] : 0
        patch = values.count > 2 ? values[2] : 0
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

// MARK: - AppUpdateStatus

/// The result of comparing the installed build against App Store + Remote Config.
enum AppUpdateStatus: Equatable {
    /// Installed build is current, or version inputs were missing/unparseable.
    case upToDate
    /// A newer public build exists; the user may continue and update later.
    case optional(latestVersion: String)
    /// Installed build is below the supported floor / force target; must update to continue.
    case required(minimumVersion: String)
}

// MARK: - App Store lookup

/// Fetches the latest publicly installable version from Apple's iTunes Lookup API.
protocol AppStoreVersionLooking: Sendable {
    func fetchLatestVersion() async -> String?
}

/// Decodes Apple's `lookup` JSON (`resultCount` + `results[].version`).
struct AppStoreLookupResponse: Decodable, Equatable {
    struct Result: Decodable, Equatable {
        let version: String?
    }

    let resultCount: Int
    let results: [Result]

    var latestVersion: String? {
        guard resultCount > 0, let version = results.first?.version, !version.isEmpty else {
            return nil
        }
        return version
    }
}

/// Live Apple lookup. Failures return `nil` so the gate can fail open on Apple
/// while still honoring a Firebase minimum floor.
struct AppStoreVersionLookup: AppStoreVersionLooking {
    /// Apple ID from App Store Connect (same as `AppConfig.appStoreURL`).
    static let appStoreID = "6791077796"

    private let session: URLSession
    private let url: URL

    init(
        session: URLSession = .shared,
        appStoreID: String = AppStoreVersionLookup.appStoreID,
        countryCode: String = "au"
    ) {
        self.session = session
        self.url = Self.lookupURL(appStoreID: appStoreID, countryCode: countryCode)
    }

    /// Rosterra is distributed through the Australian storefront. Apple's
    /// lookup API otherwise defaults to the US storefront, where this app ID
    /// returns no results and silently disables Store-version detection.
    static func lookupURL(appStoreID: String, countryCode: String) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: appStoreID),
            URLQueryItem(name: "country", value: countryCode.lowercased()),
        ]
        return components.url!
    }

    func fetchLatestVersion() async -> String? {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            let decoded = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            return decoded.latestVersion
        } catch {
            print("AppStoreVersionLookup: fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - AppVersionCheck (pure decision logic)

/// Decides `AppUpdateStatus` from raw version strings. Kept free of Firebase /
/// networking so the rules are unit-testable without stubs.
enum AppVersionCheck {
    /// Hybrid policy:
    /// 1. Below a *reachable* Firebase floor → required.
    /// 2. Force flag + behind a public App Store version → required to that Store version.
    /// 3. Otherwise behind App Store → optional.
    /// 4. Equal / newer (e.g. TestFlight) / unparseable installed → up to date.
    ///
    /// A Firebase floor newer than Apple's reported version is **not** enforced as
    /// mandatory — users could not install it yet (App Store propagation). When
    /// Apple lookup fails entirely (`appStoreVersion == nil`), a valid Firebase
    /// minimum is still honored so an outage can't disable the hard floor.
    static func evaluate(
        installedVersion: String,
        appStoreVersion: String?,
        minimumSupportedVersion: String,
        forceUpdate: Bool
    ) -> AppUpdateStatus {
        guard let installed = SemanticVersion(installedVersion) else { return .upToDate }

        let store = appStoreVersion.flatMap(SemanticVersion.init)
        let minimum = SemanticVersion(minimumSupportedVersion)

        if let minimum, installed < minimum {
            let floorIsReachable: Bool
            if let store {
                // Only hard-block when the Store already offers something >= floor.
                floorIsReachable = store >= minimum
            } else {
                // Apple unavailable — still honor the configured floor.
                floorIsReachable = true
            }
            if floorIsReachable {
                return .required(minimumVersion: minimumSupportedVersion)
            }
            // Floor is ahead of Store propagation: fall through and compare to Store.
        }

        guard let store, let appStoreVersion, installed < store else {
            return .upToDate
        }

        if forceUpdate {
            return .required(minimumVersion: appStoreVersion)
        }
        return .optional(latestVersion: appStoreVersion)
    }

    /// Legacy Remote Config–only evaluation (Mac Catalyst). Same major/minor gap
    /// rules as before Apple lookup was added on iOS.
    static func evaluateRemoteConfigOnly(
        installedVersion: String,
        latestVersion: String,
        minimumSupportedVersion: String,
        forceUpdate: Bool
    ) -> AppUpdateStatus {
        guard let installed = SemanticVersion(installedVersion) else { return .upToDate }

        if let minimum = SemanticVersion(minimumSupportedVersion), installed < minimum {
            return .required(minimumVersion: minimumSupportedVersion)
        }

        guard let latest = SemanticVersion(latestVersion), installed < latest else {
            return .upToDate
        }

        let isPatchOnlyGap = installed.major == latest.major && installed.minor == latest.minor
        if forceUpdate || !isPatchOnlyGap {
            return .required(minimumVersion: latestVersion)
        }
        return .optional(latestVersion: latestVersion)
    }
}

// MARK: - AppVersionChecking

protocol AppVersionChecking: AnyObject {
    func checkForUpdate() async -> AppUpdateStatus
    func startListeningForUpdates(onUpdate: @escaping @Sendable () -> Void)
    func stopListeningForUpdates()
}

extension AppVersionChecking {
    func startListeningForUpdates(onUpdate: @escaping @Sendable () -> Void) {}
    func stopListeningForUpdates() {}
}

// MARK: - AppVersionCheckService (Remote Config + App Store)

/// Fetches the platform's version-gate inputs and evaluates them against the
/// installed build via `AppVersionCheck`.
///
/// **iOS:** Apple Lookup supplies the latest public version; Firebase supplies
/// `ios_minimum_supported_version` and `ios_force_update`.
///
/// **Mac Catalyst:** keeps Remote Config–only keys (`mac_*`) so Mac is not
/// gated by the iOS App Store listing. Unset `mac_*` keys fall through to
/// defaults (no gate) until deliberately configured.
///
/// Must not be constructed before `FirebaseBootstrap.configure()` has run —
/// `RemoteConfig.remoteConfig()` requires the default `FirebaseApp` to already
/// exist. Callers should guard on `FirebaseBootstrap.hasConfigFile` first.
final class AppVersionCheckService: AppVersionChecking {
    private enum Key {
        #if targetEnvironment(macCatalyst)
        static let latestVersion = "mac_latest_version"
        static let minimumSupportedVersion = "mac_minimum_supported_version"
        static let forceUpdate = "mac_force_update"
        #else
        static let latestVersion = "ios_latest_version"
        static let minimumSupportedVersion = "ios_minimum_supported_version"
        static let forceUpdate = "ios_force_update"
        #endif
    }

    private let remoteConfig: RemoteConfig
    private let installedVersion: String
    private let appStoreLookup: AppStoreVersionLooking?
    private var configUpdateListener: ConfigUpdateListenerRegistration?

    init(
        remoteConfig: RemoteConfig = RemoteConfig.remoteConfig(),
        installedVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        appStoreLookup: AppStoreVersionLooking? = nil
    ) {
        self.remoteConfig = remoteConfig
        self.installedVersion = installedVersion
        #if targetEnvironment(macCatalyst)
        self.appStoreLookup = nil
        #else
        self.appStoreLookup = appStoreLookup ?? AppStoreVersionLookup()
        #endif

        let settings = RemoteConfigSettings()
        // Re-fetching on every launch/foreground is cheap and this is a
        // safety gate — don't let the SDK's default throttle (12h) delay a
        // force-update rollout by half a day.
        settings.minimumFetchInterval = 0
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            Key.latestVersion: installedVersion as NSObject,
            Key.minimumSupportedVersion: "0.0.0" as NSObject,
            Key.forceUpdate: false as NSObject,
        ])
    }

    /// Fetches and evaluates. Remote Config / Apple failures never throw —
    /// cached RC defaults and nil Apple results are handled by the pure policy.
    func checkForUpdate() async -> AppUpdateStatus {
        do {
            _ = try await remoteConfig.fetchAndActivate()
        } catch {
            print("AppVersionCheckService: fetchAndActivate failed, using cached values: \(error.localizedDescription)")
        }

        let minimum = remoteConfig[Key.minimumSupportedVersion].stringValue
        let forceUpdate = remoteConfig[Key.forceUpdate].boolValue

        #if targetEnvironment(macCatalyst)
        return AppVersionCheck.evaluateRemoteConfigOnly(
            installedVersion: installedVersion,
            latestVersion: remoteConfig[Key.latestVersion].stringValue,
            minimumSupportedVersion: minimum,
            forceUpdate: forceUpdate
        )
        #else
        async let storeVersion = appStoreLookup?.fetchLatestVersion()
        let appStoreVersion = await storeVersion
        return AppVersionCheck.evaluate(
            installedVersion: installedVersion,
            appStoreVersion: appStoreVersion,
            minimumSupportedVersion: minimum,
            forceUpdate: forceUpdate
        )
        #endif
    }

    /// Keeps an open foreground listener so a newly published mandatory floor
    /// can be enforced without waiting for another launch or scene transition.
    func startListeningForUpdates(onUpdate: @escaping @Sendable () -> Void) {
        guard configUpdateListener == nil else { return }
        configUpdateListener = remoteConfig.addOnConfigUpdateListener { update, error in
            if let error {
                print("AppVersionCheckService: real-time update failed: \(error.localizedDescription)")
                return
            }
            guard let update else { return }
            let relevantKeys: Set<String> = [
                Key.latestVersion,
                Key.minimumSupportedVersion,
                Key.forceUpdate,
            ]
            guard !update.updatedKeys.isDisjoint(with: relevantKeys) else { return }
            onUpdate()
        }
    }

    func stopListeningForUpdates() {
        configUpdateListener?.remove()
        configUpdateListener = nil
    }
}
