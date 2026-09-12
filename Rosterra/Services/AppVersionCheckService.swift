import Foundation
import FirebaseRemoteConfig

// MARK: - SemanticVersion

/// A `major.minor.patch` version, parsed leniently (missing components default
/// to 0, a `-suffix` like "-beta.1" is ignored) so it can compare both
/// `CFBundleShortVersionString` values and hand-typed Remote Config strings.
struct SemanticVersion: Comparable {
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

/// The result of comparing the installed build against Remote Config.
enum AppUpdateStatus: Equatable {
    /// Installed build is current, or Remote Config values were missing/unparseable.
    case upToDate
    /// A newer build exists; the user may continue and update later.
    case optional(latestVersion: String)
    /// Installed build is below the floor Remote Config allows; must update to continue.
    case required(minimumVersion: String)
}

// MARK: - AppVersionCheck (pure decision logic)

/// Decides `AppUpdateStatus` from raw version strings. Kept free of Firebase
/// so the version-comparison rules are unit-testable without a network stub.
enum AppVersionCheck {
    /// - Parameters:
    ///   - installedVersion: `CFBundleShortVersionString` of the running build.
    ///   - latestVersion: Remote Config `ios_latest_version` — newest build available.
    ///   - minimumSupportedVersion: Remote Config `ios_minimum_supported_version` — hard floor.
    ///   - forceUpdate: Remote Config `ios_force_update` — a kill switch that, when set,
    ///     treats `latestVersion` itself as the floor (e.g. to pull everyone off a build
    ///     with a live incident, without having to also bump the minimum-supported floor).
    ///
    /// Behind a shared minimum floor, being behind `latestVersion` is only ever *optional*
    /// when the gap is patch-only (same major.minor — bug fixes, no behavior the user needs
    /// to opt into). Any major or minor gap is treated as mandatory, since those releases
    /// are assumed to carry changes the app can't safely run stale against.
    ///
    /// Unparseable `installedVersion` fails open (`.upToDate`) — a build whose version
    /// string this logic can't understand is never blocked from launching.
    static func evaluate(
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

// MARK: - AppVersionCheckService (Remote Config networking)

/// Fetches the platform's Remote Config version-gate keys and evaluates them
/// against the installed build via `AppVersionCheck.evaluate`.
///
/// Mac Catalyst reads `mac_*` rather than `ios_*`. A Mac build ships on its own
/// schedule (or not at all), so sharing the iOS floor could hard-block Mac
/// users behind `UpdateRequiredView` with no build available to install. The
/// `mac_*` keys are unset by default, which falls through to the defaults
/// registered below — no gate — until someone deliberately sets one.
///
/// Must not be constructed before `FirebaseBootstrap.configure()` has run —
/// `RemoteConfig.remoteConfig()` requires the default `FirebaseApp` to already
/// exist. Callers should guard on `FirebaseBootstrap.hasConfigFile` first.
final class AppVersionCheckService {
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

    init(
        remoteConfig: RemoteConfig = RemoteConfig.remoteConfig(),
        installedVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    ) {
        self.remoteConfig = remoteConfig
        self.installedVersion = installedVersion

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

    /// Fetches and evaluates. On fetch failure (offline, throttled, etc.) this
    /// falls back to whatever Remote Config already has cached/defaulted —
    /// it never throws, so a Remote Config outage can't block the app.
    func checkForUpdate() async -> AppUpdateStatus {
        do {
            _ = try await remoteConfig.fetchAndActivate()
        } catch {
            print("AppVersionCheckService: fetchAndActivate failed, using cached values: \(error.localizedDescription)")
        }

        return AppVersionCheck.evaluate(
            installedVersion: installedVersion,
            latestVersion: remoteConfig[Key.latestVersion].stringValue,
            minimumSupportedVersion: remoteConfig[Key.minimumSupportedVersion].stringValue,
            forceUpdate: remoteConfig[Key.forceUpdate].boolValue
        )
    }
}
