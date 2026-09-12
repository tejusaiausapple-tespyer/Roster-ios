import Foundation
import LocalAuthentication

/// Local app-lock using Face ID / Touch ID (with device-passcode fallback).
/// This is a *local* gate on top of a persisted Firebase session, mirroring the
/// web app's `deviceAuth` (biometric unlock, per-uid enablement flag). It is not
/// server-verified.
struct DeviceAuthService {
    static let shared = DeviceAuthService()

    enum VerifyOutcome {
        case success
        /// The enrolled biometry changed since `enable()` (re-enrollment,
        /// added/removed a face or fingerprint). Unlike BiometricCredentialStore
        /// / PasskeyStore (which use `.biometryCurrentSet` and so invalidate
        /// automatically on re-enrollment), this local re-lock gate previously
        /// had no such check — its "enabled" flag was a plain Keychain marker,
        /// so re-enrolling (itself requiring the device passcode) trivially
        /// satisfied it. The caller should force a full sign-in rather than
        /// silently accept it.
        case biometryChanged
        case cancelled
        case lockedOut
        case notEnrolled
        case failed(message: String)
    }

    private func keychainKey(_ uid: String) -> String { "roster_device_auth_\(uid)" }
    private func domainStateKey(_ uid: String) -> String { "roster_device_auth_domainstate_\(uid)" }

    /// Whether the device can perform biometric or passcode authentication.
    var isSupported: Bool {
        var error: NSError?
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// The available biometry type, for labelling ("Face ID" / "Touch ID").
    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Device Passcode"
        }
    }

    var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }

    func isEnabled(uid: String) -> Bool {
        KeychainHelper.get(keychainKey(uid)) != nil
    }

    /// Biometric enrollment fingerprint at this moment. `nil` when biometry
    /// can't currently be evaluated (passcode-only device, hardware
    /// temporarily unavailable, nothing enrolled) — callers must treat `nil`
    /// as inconclusive, not as "changed", since several of those causes are
    /// transient and not actually a re-enrollment.
    private func currentBiometryDomainState() -> Data? {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.evaluatedPolicyDomainState
    }

    /// Prompt for biometrics and, on success, persist the enablement flag
    /// plus a snapshot of the enrolled-biometry domain state (see `verify`).
    func enable(uid: String) async throws {
        try await evaluate(reason: "Enable secure unlock for Rosterra")
        KeychainHelper.set(ISO8601DateFormatter().string(from: Date()), for: keychainKey(uid))
        if let state = currentBiometryDomainState() {
            KeychainHelper.set(state.base64EncodedString(), for: domainStateKey(uid))
        } else {
            KeychainHelper.delete(domainStateKey(uid))
        }
    }

    func disable(uid: String) {
        KeychainHelper.delete(keychainKey(uid))
        KeychainHelper.delete(domainStateKey(uid))
    }

    /// Prompt to unlock. First checks whether the enrolled biometry has
    /// unambiguously changed since `enable()` — if so, disables the gate and
    /// reports `.biometryChanged` without prompting, so the caller can force
    /// a full sign-in instead of letting a newly-enrolled face/fingerprint
    /// (itself only obtainable via the device passcode) trivially pass.
    func verify(uid: String) async -> VerifyOutcome {
        if let storedBase64 = KeychainHelper.get(domainStateKey(uid)),
           let storedState = Data(base64Encoded: storedBase64),
           let current = currentBiometryDomainState(),
           current != storedState {
            disable(uid: uid)
            return .biometryChanged
        }
        do {
            try await evaluate(reason: "Unlock Rosterra")
            return .success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel:
                return .cancelled
            case .biometryLockout:
                return .lockedOut
            case .biometryNotEnrolled, .biometryNotAvailable:
                return .notEnrolled
            default:
                return .failed(message: error.localizedDescription)
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private func evaluate(reason: String) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? AuthError.generic("Authentication failed."))
                }
            }
        }
    }
}
