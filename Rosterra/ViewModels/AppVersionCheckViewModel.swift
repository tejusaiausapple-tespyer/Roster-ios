import Foundation
import Observation

/// Drives the update-required / update-available UI from `AppVersionCheckService`.
/// Checked on launch, every foreground, and after login (see `RootView`).
@Observable
final class AppVersionCheckViewModel {
    private(set) var status: AppUpdateStatus = .upToDate

    /// Version the user tapped "Later" on — suppresses the optional sheet for
    /// the rest of this session so it doesn't reappear on every foreground.
    private var dismissedOptionalVersion: String?

    /// Serializes overlapping `check()` calls so a stale fail-open cannot clear
    /// a required gate, while a trailing re-check still runs after the in-flight
    /// one finishes (login + foreground racing).
    private var isChecking = false
    private var needsRecheck = false

    /// When `true`, `service` was injected (tests) — skip the Firebase plist gate.
    private let hasInjectedService: Bool

    /// Constructed lazily on first `check()`, not at init — `RemoteConfig.remoteConfig()`
    /// requires Firebase to already be configured, which isn't guaranteed yet
    /// when this view model is created as `RootView`'s `@State`.
    private var service: AppVersionChecking?

    init(service: AppVersionChecking? = nil) {
        self.service = service
        self.hasInjectedService = service != nil
    }

    var isUpdateRequired: Bool {
        if case .required = status { return true }
        return false
    }

    var isUpdateAvailable: Bool {
        if case .optional(let latestVersion) = status {
            return latestVersion != dismissedOptionalVersion
        }
        return false
    }

    @MainActor
    func check() async {
        if !hasInjectedService {
            guard FirebaseBootstrap.hasConfigFile else { return }
        }

        if isChecking {
            needsRecheck = true
            return
        }

        isChecking = true
        defer { isChecking = false }

        let service = self.service ?? AppVersionCheckService()
        self.service = service

        repeat {
            needsRecheck = false
            status = await service.checkForUpdate()
        } while needsRecheck
    }

    func dismissOptionalUpdate() {
        if case .optional(let latestVersion) = status {
            dismissedOptionalVersion = latestVersion
        }
    }
}
