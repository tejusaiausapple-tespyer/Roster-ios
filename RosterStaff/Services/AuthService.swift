import Foundation
import FirebaseAuth

enum AuthError: LocalizedError {
    case profileNotFound
    case accountLocked
    case accountInactive
    case notAuthenticated
    case wrongPassword
    case weakPassword
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .profileNotFound: return "User profile not found. Contact your manager."
        case .accountLocked: return "Your account has been locked. Contact your manager."
        case .accountInactive: return "Your account is inactive. Contact your manager."
        case .notAuthenticated: return "You are not signed in."
        case .wrongPassword: return "Your current password is incorrect."
        case .weakPassword: return "That password does not meet the requirements."
        case .generic(let message): return message
        }
    }
}

/// Thin wrapper around FirebaseAuth for the staff app. Session persistence is
/// handled automatically by the Firebase iOS SDK (Keychain), mirroring the web
/// app's IndexedDB persistence.
final class AuthService {
    static let shared = AuthService()

    var currentUID: String? { Auth.auth().currentUser?.uid }
    var currentEmail: String? { Auth.auth().currentUser?.email }

    /// Sign in with email/password. Returns the Firebase uid.
    func signIn(email: String, password: String) async throws -> String {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return result.user.uid
        } catch let error as NSError {
            throw mapAuthError(error)
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// Send a Firebase password-reset email to the given address. Firebase
    /// delivers the email and hosts the reset page; no backend change needed.
    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch let error as NSError {
            throw mapAuthError(error)
        }
    }

    /// Observe Firebase auth state; the closure receives the current uid (or nil).
    @discardableResult
    func addStateListener(_ handler: @escaping (String?) -> Void) -> AuthStateDidChangeListenerHandle {
        Auth.auth().addStateDidChangeListener { _, user in
            handler(user?.uid)
        }
    }

    func removeStateListener(_ handle: AuthStateDidChangeListenerHandle) {
        Auth.auth().removeStateDidChangeListener(handle)
    }

    /// Reauthenticate and update the password (mirrors changePassword in dataStore).
    func changePassword(current: String, new: String, email: String) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notAuthenticated }
        let credential = EmailAuthProvider.credential(withEmail: email, password: current)
        do {
            try await user.reauthenticate(with: credential)
        } catch let error as NSError {
            throw mapAuthError(error)
        }
        do {
            try await user.updatePassword(to: new)
        } catch let error as NSError {
            throw mapAuthError(error)
        }
    }

    private func mapAuthError(_ error: NSError) -> AuthError {
        guard error.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: error.code) else {
            return .generic(error.localizedDescription)
        }
        switch code {
        case .wrongPassword, .invalidCredential, .userMismatch:
            return .wrongPassword
        case .weakPassword:
            return .weakPassword
        case .userNotFound, .invalidEmail:
            return .generic("No account found for that email.")
        case .networkError:
            return .generic("Network error. Check your connection and try again.")
        case .tooManyRequests:
            return .generic("Too many attempts. Please wait a moment and try again.")
        case .keychainError:
            return .generic("Keychain access error. Please make sure Keychain Sharing is enabled and a valid Development Team is selected in Xcode.")
        default:
            return .generic(error.localizedDescription)
        }
    }
}
