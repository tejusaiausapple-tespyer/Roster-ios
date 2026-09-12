import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// Owns the session/auth state machine and coordinates the data repository,
/// device-auth gate, and push registration. Mirrors the web app's authStore +
/// App.tsx gating logic.
@MainActor
@Observable
final class AuthViewModel {
    // Session
    var uid: String?
    var isRestoring = true

    // Device lock (local)
    var deviceAuthEnabled = false
    var deviceAuthVerified = false

    // Login form state
    var isWorking = false
    var errorMessage: String?

    // Forced sign-out messaging (locked/inactive accounts)
    var forcedSignOutMessage: String?
    var temporaryPassword: String?

    private var repository: RosterRepository?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var backgroundedAt: Date?
    /// Not `private` so tests can simulate the fresh-login path through
    /// `handleAuthState` directly, without driving a real `login()` call
    /// (which hits live Firebase Auth + Firestore — unsuitable for a fast,
    /// hermetic unit test).
    var isLoggingIn = false

    // MARK: - Wiring

    func bind(repository: RosterRepository) {
        guard self.repository == nil else { return }
        self.repository = repository
        NotificationService.shared.bind(repository: repository)
        guard FirebaseBootstrap.isConfigured else {
            isRestoring = false
            return
        }
        authListener = AuthService.shared.addStateListener { [weak self] uid in
            Task { @MainActor in self?.handleAuthState(uid: uid) }
        }
    }

    /// Not `private` so tests can drive this state machine directly (see
    /// `isLoggingIn`) — the gate-skip decision here is exactly what a past
    /// bug lived in, and it was previously untestable.
    func handleAuthState(uid: String?) {
        isRestoring = false
        self.uid = uid
        if let uid {
            deviceAuthEnabled = DeviceAuthService.shared.isEnabled(uid: uid)
            // On a restored session, require the gate again if enabled.
            // Fresh logins skip the gate.
            if isLoggingIn {
                deviceAuthVerified = true
            } else if !deviceAuthVerified {
                deviceAuthVerified = !deviceAuthEnabled
            }
            repository?.start(uid: uid)
            NotificationService.shared.requestAuthorizationAndRegister()
            NotificationService.shared.syncTokenAfterLogin()
            Task { await ServerClock.shared.sync() }
        } else {
            repository?.stop()
            deviceAuthEnabled = false
            deviceAuthVerified = false
        }
    }

    // MARK: - Login / logout

    func login(email: String, password: String) async {
        isLoggingIn = true
        errorMessage = nil
        forcedSignOutMessage = nil
        isWorking = true
        defer {
            isLoggingIn = false
            isWorking = false
        }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let uid = try await AuthService.shared.signIn(email: trimmed, password: password)
            // Validate the profile/status exactly like the web login flow.
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snap.data(), let user = AppUser(id: uid, data: data) else {
                try? AuthService.shared.signOut()
                throw AuthError.profileNotFound
            }
            if user.status == .locked {
                try? AuthService.shared.signOut()
                throw AuthError.accountLocked
            }
            if user.status == .inactive {
                try? AuthService.shared.signOut()
                throw AuthError.accountInactive
            }
            // Fresh login skips the device-auth gate for this session.
            deviceAuthVerified = true
            temporaryPassword = password
            // ServerClock, not the device clock — lastLoginAt should reflect
            // trusted time the same way clock-in/out attendance does, not a
            // value a manipulated device clock could report arbitrarily.
            try? await Firestore.firestore().collection("users").document(uid)
                .updateData(["lastLoginAt": FS.isoFormatter.string(from: ServerClock.shared.now)])
            // Best-effort, deliberately not awaited — claims this device as
            // the account's single active notification device without
            // adding a network round trip to the login flow. Distinct from
            // syncTokenAfterLogin() (called on every resolved auth state,
            // including a restored session): only this genuine credential
            // login should claim active status.
            NotificationService.shared.claimActiveDeviceOnLogin()
            Haptics.signIn()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        Haptics.signOut()
        Task { await endSession() }
    }

    /// Force sign-out with a message (e.g. account became locked while signed in).
    func forceSignOut(message: String) {
        forcedSignOutMessage = message
        Haptics.forcedSignOut()
        Task { await endSession() }
    }

    /// Order matters: the token delete MUST complete (or fail) while still
    /// authenticated as the departing user, before `signOut()` changes the
    /// auth context — see the doc comment on `clearTokenOnLogout`. Wrapped in
    /// its own Task by `logout()`/`forceSignOut()` so callers keep a
    /// synchronous call site; the ordering guarantee lives here regardless.
    private func endSession() async {
        if let uid {
            await NotificationService.shared.clearTokenOnLogout(uid: uid)
        }
        ShiftReminderScheduler.cancelAll()
        DailyJobReminderScheduler.cancelAll()
        try? AuthService.shared.signOut()
        deviceAuthVerified = false
        deviceAuthEnabled = false
        temporaryPassword = nil
    }

    // MARK: - Device auth gate

    /// Returns a message for `DeviceAuthGateView` to show on a non-success,
    /// non-cancel outcome (nil otherwise — cancel/dismiss needs no message,
    /// success needs none either since the gate just closes).
    @discardableResult
    func verifyDeviceAuth() async -> String? {
        guard let uid else { return nil }
        switch await DeviceAuthService.shared.verify(uid: uid) {
        case .success:
            Haptics.authSuccess()
            deviceAuthVerified = true
            return nil
        case .biometryChanged:
            Haptics.authFailure()
            deviceAuthEnabled = false
            // The Firebase session itself is still valid — only the local
            // re-lock gate is no longer trustworthy — so this is a full
            // sign-in requirement, not an account-status forced sign-out,
            // but forceSignOut's messaging path is exactly what's needed.
            forceSignOut(message: "Your device's Face ID/Touch ID enrollment changed, so secure unlock was turned off for your safety. Please sign in again.")
            return nil
        case .cancelled:
            Haptics.authFailure()
            return nil
        case .lockedOut:
            Haptics.authFailure()
            return "Too many failed attempts. Use your device passcode, or try again later."
        case .notEnrolled:
            Haptics.authFailure()
            return "No Face ID/Touch ID is set up on this device. Use your device passcode, or set up biometrics in Settings."
        case .failed(let message):
            Haptics.authFailure()
            return message
        }
    }

    func refreshDeviceAuthEnabled() {
        guard let uid else { return }
        deviceAuthEnabled = DeviceAuthService.shared.isEnabled(uid: uid)
    }

    // MARK: - Scene phase / background relock

    /// `now` defaults to the real clock for every production call site;
    /// tests pass an explicit instant to exercise the relock-threshold
    /// branch deterministically instead of sleeping for real minutes.
    func handleScenePhase(_ phase: ScenePhaseKind, now: Date = Date()) {
        switch phase {
        case .background:
            backgroundedAt = now
            // Don't keep the plaintext login password in memory once the app
            // leaves the foreground. (It exists only to let the Account tab
            // enable Face ID without re-prompting in the same session.)
            temporaryPassword = nil
        case .active:
            if let backgroundedAt,
               now.timeIntervalSince(backgroundedAt) >= AppConfig.deviceAuthBackgroundRelock,
               deviceAuthEnabled {
                deviceAuthVerified = false
            }
            self.backgroundedAt = nil
            Task {
                await ServerClock.shared.sync()
                await PendingEmailChange.reconcileIfNeeded()
                await repository?.refreshFromServer()
            }
        case .inactive:
            break
        }
    }

    enum ScenePhaseKind { case active, inactive, background }
}
