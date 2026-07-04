import Foundation
import Security
import LocalAuthentication

/// Securely stores a single login credential (email + password) behind the
/// device biometric/passcode, enabling "Continue with Face ID" on the login
/// screen.
///
/// Security notes:
/// - The password is stored in the Keychain as a `kSecClassGenericPassword`
///   item protected by a `SecAccessControl` with `.biometryCurrentSet`, so it
///   can only be read after a successful Face ID / Touch ID match and is
///   automatically invalidated if the enrolled biometrics change.
/// - The item is `WhenUnlockedThisDeviceOnly`, so it never syncs to iCloud and
///   never leaves the device.
/// - The associated email is kept in `UserDefaults` purely to know *whether* a
///   credential exists and to prefill the field — the password itself is only
///   ever in the biometric-gated Keychain.
enum BiometricCredentialStore {
    private static let service = "com.sura.roster.staff.biometriclogin"
    private static let account = "primary"
    private static let emailKey = "roster_biometric_login_email"

    /// Whether a biometric credential has been saved (does not prompt).
    static var hasCredential: Bool {
        UserDefaults.standard.string(forKey: emailKey) != nil
    }

    /// The email associated with the saved biometric credential, if any.
    static var savedEmail: String? {
        UserDefaults.standard.string(forKey: emailKey)
    }

    /// Save the credential behind a biometric-gated Keychain item.
    static func save(email: String, password: String) {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessControl as String] = access

        if SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.set(email, forKey: emailKey)
        }
    }

    /// Read the stored password behind a biometric prompt. Returns nil on
    /// cancel / failure / absence.
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
        return await withCheckedContinuation { continuation in
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
    }

    /// Remove the saved biometric credential (e.g. after a stale-password failure).
    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }
}
