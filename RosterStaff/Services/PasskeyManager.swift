import Foundation
import AuthenticationServices
import UIKit

/// Apple passkey (platform `ASAuthorizationPlatformPublicKeyCredential`) manager.
///
/// This mirrors the web app's `deviceAuth.ts` model: the passkey ceremony is used
/// as a **local presence gate**, not server-verified authentication. A successful
/// registration/assertion proves the platform authenticator (Face ID / Touch ID /
/// passcode) verified the user on this device; the saved Firebase credential is
/// what actually signs them in. We do not send the attestation/assertion to a
/// server (there is no WebAuthn relying-party backend).
///
/// PREREQUISITES (passkeys will not work until all are in place):
///   1. Paid Apple Developer account + `DEVELOPMENT_TEAM` set.
///   2. Associated Domains entitlement `webcredentials:sura-roster.com`
///      (see RosterStaff.entitlements) wired via CODE_SIGN_ENTITLEMENTS.
///   3. An `apple-app-site-association` file hosted at
///      https://sura-roster.com/.well-known/apple-app-site-association with a
///      `webcredentials` section listing `<TeamID>.com.surainvestments.roster`.
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
/// `UserDefaults`, and the Firebase password in a device-only Keychain item.
/// The passkey assertion ceremony is the gate that protects retrieval — this
/// mirrors the web app's local, non-server-verified device-auth model, adapted
/// to actually sign the user into Firebase afterwards.
enum PasskeyStore {
    private static let emailKey = "roster_passkey_email"
    private static let credentialKey = "roster_passkey_credential_id"
    private static let passwordKeychainKey = "roster_passkey_password"

    static var isRegistered: Bool {
        UserDefaults.standard.string(forKey: credentialKey) != nil
    }

    static var email: String? { UserDefaults.standard.string(forKey: emailKey) }
    static var credentialID: String? { UserDefaults.standard.string(forKey: credentialKey) }

    static func save(email: String, credentialID: String, password: String) {
        UserDefaults.standard.set(email, forKey: emailKey)
        UserDefaults.standard.set(credentialID, forKey: credentialKey)
        KeychainHelper.set(password, for: passwordKeychainKey)
    }

    static func password() -> String? {
        KeychainHelper.get(passwordKeychainKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: credentialKey)
        KeychainHelper.delete(passwordKeychainKey)
    }
}
