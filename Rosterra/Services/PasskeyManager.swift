import Foundation
import AuthenticationServices
import UIKit
import Security
import LocalAuthentication

/// Apple passkey (platform `ASAuthorizationPlatformPublicKeyCredential`) manager.
///
/// This mirrors the web app's `deviceAuth.ts` model: the passkey ceremony is used
/// as a **local presence gate**, not server-verified authentication. A successful
/// registration/assertion proves the platform authenticator (Face ID / Touch ID /
/// passcode) verified the user on this device; the saved Firebase credential is
/// what actually signs them in. We do not send the attestation/assertion to a
/// server (there is no WebAuthn relying-party backend).
///
/// Prerequisites are now all in place: paid team `GS2KGPX9P8`, the Associated
/// Domains entitlement, and `apple-app-site-association` hosting the real
/// team ID (was a `TEAMID` placeholder — fixed 2026-07-15).
///
/// NOTE: `register(email:userID:)` below is not currently called from any
/// screen — there is no UI flow that creates a passkey, so
/// `PasskeyStore.isRegistered` is always false and the "Sign in with
/// Passkey" quick-login row on `LoginView` never surfaces today. Wiring a
/// registration entry point (e.g. in Account settings) is a follow-up, not
/// a launch blocker: with no trigger, this code path cannot fail for users.
/// `signIn(credentialID:)` is fully wired and would work once a credential
/// exists.
@MainActor
final class PasskeyManager: NSObject {
    static let shared = PasskeyManager()

    enum PasskeyError: LocalizedError {
        case unsupported
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported: return "Passkeys aren't available on this device."
            case .cancelled: return "Passkey request was cancelled."
            case .failed(let message): return message
            }
        }
    }

    /// Passkeys require iOS 16+; the app targets iOS 17, so always true at runtime.
    var isSupported: Bool { true }

    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    private var provider: ASAuthorizationPlatformPublicKeyCredentialProvider {
        ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: AppConfig.passkeyRelyingParty
        )
    }

    private func randomData(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    // MARK: - Registration

    /// Register a new platform passkey for the user. Returns the credential ID
    /// (base64url) to persist locally. Triggers the system passkey creation UI.
    func register(email: String, userID: String) async throws -> String {
        let challenge = randomData(32)
        let userIDData = Data(userID.utf8)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: email,
            userID: userIDData
        )
        let authorization = try await perform(request: request)
        guard let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw PasskeyError.failed("Unexpected passkey registration result.")
        }
        return credential.credentialID.base64URLEncodedString()
    }

    // MARK: - Assertion (sign-in)

    /// Assert an existing passkey. Succeeds (returns) only when the platform
    /// authenticator verifies the user. `credentialID` is the base64url id saved
    /// at registration time.
    func signIn(credentialID: String) async throws {
        let challenge = randomData(32)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if let idData = Data(base64URLEncoded: credentialID) {
            request.allowedCredentials = [
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: idData)
            ]
        }
        let authorization = try await perform(request: request)
        guard authorization.credential is ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw PasskeyError.failed("Unexpected passkey assertion result.")
        }
        // Local gate only — a successful assertion is our proof of presence.
    }

    // MARK: - Ceremony plumbing

    private func perform(request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension PasskeyManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        let mapped: PasskeyError
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            mapped = .cancelled
        } else {
            mapped = .failed(error.localizedDescription)
        }
        continuation?.resume(throwing: mapped)
        continuation = nil
    }
}

extension PasskeyManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}

// MARK: - base64url helpers (match the web app's bufferToBase64Url / base64UrlToBuffer)

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: normalized)
    }
}

/// Local persistence for a registered passkey: the credential id + email in
/// `UserDefaults`, and the Firebase password in a **biometric-gated** Keychain
/// item (`.biometryCurrentSet`, device-only) — the same protection class as
/// `BiometricCredentialStore`. The passkey assertion proves presence, but the
/// password itself is additionally protected at the Keychain level so it can
/// never be read without a biometric match, even if the assertion step is
/// bypassed by other code.
enum PasskeyStore {
    private static let emailKey = "roster_passkey_email"
    private static let credentialKey = "roster_passkey_credential_id"
    /// Pre-hardening item location (plain KeychainHelper). Migrated + removed
    /// on first read; never written to anymore.
    private static let legacyPasswordKeychainKey = "roster_passkey_password"

    private static let service = "com.sura.roster.staff.passkeylogin"
    private static let account = "primary"

    static var isRegistered: Bool {
        UserDefaults.standard.string(forKey: credentialKey) != nil
    }

    static var email: String? { UserDefaults.standard.string(forKey: emailKey) }
    static var credentialID: String? { UserDefaults.standard.string(forKey: credentialKey) }

    static func save(email: String, credentialID: String, password: String) {
        guard storeProtectedPassword(password) else { return }
        UserDefaults.standard.set(email, forKey: emailKey)
        UserDefaults.standard.set(credentialID, forKey: credentialKey)
        KeychainHelper.delete(legacyPasswordKeychainKey)
    }

    /// Read the stored password behind a biometric prompt. Falls back to a
    /// one-time migration of the legacy unprotected item if present.
    /// Returns nil on cancel / failure / absence.
    static func readPassword(reason: String) async -> String? {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        let protected: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        if let protected { return protected }

        // Legacy migration: move any unprotected item into the gated store.
        if let legacy = KeychainHelper.get(legacyPasswordKeychainKey) {
            if storeProtectedPassword(legacy) {
                KeychainHelper.delete(legacyPasswordKeychainKey)
            }
            return legacy
        }
        return nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: credentialKey)
        KeychainHelper.delete(legacyPasswordKeychainKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Write the password behind `.biometryCurrentSet` (auto-invalidated when
    /// enrolled biometrics change), never synced off-device.
    private static func storeProtectedPassword(_ password: String) -> Bool {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return false }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessControl as String] = access
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
