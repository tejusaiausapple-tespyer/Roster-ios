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
    private var isLoggingIn = false

    // MARK: - Wiring

    func bind(repository: RosterRepository) {
        guard self.repository == nil else { return }
        self.repository = repository
        guard FirebaseBootstrap.isConfigured else {
            isRestoring = false
            return
        }
        authListener = AuthService.shared.addStateListener { [weak self] uid in
            Task { @MainActor in self?.handleAuthState(uid: uid) }
        }
    }

    private func handleAuthState(uid: String?) {
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
            try? await Firestore.firestore().collection("users").document(uid)
                .updateData(["lastLoginAt": FS.isoFormatter.string(from: Date())])
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        try? AuthService.shared.signOut()
        deviceAuthVerified = false
        deviceAuthEnabled = false
        temporaryPassword = nil
    }

    /// Force sign-out with a message (e.g. account became locked while signed in).
    func forceSignOut(message: String) {
        forcedSignOutMessage = message
        logout()
    }

    // MARK: - Device auth gate

    func verifyDeviceAuth() async {
        guard let uid else { return }
        let ok = await DeviceAuthService.shared.verify(uid: uid)
        if ok {
            Haptics.success()
            deviceAuthVerified = true
        } else {
            Haptics.error()
        }
    }

    func refreshDeviceAuthEnabled() {
        guard let uid else { return }
        deviceAuthEnabled = DeviceAuthService.shared.isEnabled(uid: uid)
    }

    // MARK: - Scene phase / background relock

    func handleScenePhase(_ phase: ScenePhaseKind) {
        switch phase {
        case .background:
            backgroundedAt = Date()
            // Don't keep the plaintext login password in memory once the app
            // leaves the foreground. (It exists only to let the Account tab
            // enable Face ID without re-prompting in the same session.)
            temporaryPassword = nil
        case .active:
            if let backgroundedAt,
               Date().timeIntervalSince(backgroundedAt) >= AppConfig.deviceAuthBackgroundRelock,
               deviceAuthEnabled {
                deviceAuthVerified = false
            }
            self.backgroundedAt = nil
            Task { await repository?.refreshFromServer() }
        case .inactive:
            break
        }
    }

    enum ScenePhaseKind { case active, inactive, background }
}
