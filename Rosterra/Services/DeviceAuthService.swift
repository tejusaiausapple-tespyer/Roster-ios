import Foundation
import LocalAuthentication

/// Local app-lock using Face ID / Touch ID (with device-passcode fallback).
/// This is a *local* gate on top of a persisted Firebase session, mirroring the
/// web app's `deviceAuth` (biometric unlock, per-uid enablement flag). It is not
/// server-verified.
struct DeviceAuthService {
    static let shared = DeviceAuthService()

    private func keychainKey(_ uid: String) -> String { "roster_device_auth_\(uid)" }

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

    /// Prompt for biometrics and, on success, persist the enablement flag.
    func enable(uid: String) async throws {
        try await evaluate(reason: "Enable secure unlock for Rosterra")
        KeychainHelper.set(ISO8601DateFormatter().string(from: Date()), for: keychainKey(uid))
    }

    func disable(uid: String) {
        KeychainHelper.delete(keychainKey(uid))
    }

    /// Prompt to unlock. Returns true on success, false on cancel/failure.
    func verify(uid: String) async -> Bool {
        do {
            try await evaluate(reason: "Unlock Rosterra")
            return true
        } catch {
            return false
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
