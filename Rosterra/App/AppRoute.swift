import Foundation

/// The single screen RootView should present, derived from session and
/// profile state. Extracted from RootView so the gate ordering is a pure,
/// unit-tested decision instead of an inline `switch true` (which previously
/// let managers bypass the forced-password-change and device-auth gates).
///
/// Gate order (first match wins):
///   setup → restoring → login → profileLoading → forcedPasswordChange →
///   profileCompletion → deviceAuthGate → managerMain / staffMain
///
/// Notes:
/// - `forcedPasswordChange` and `deviceAuthGate` apply to BOTH roles.
/// - `profileCompletion` is effectively staff-only because
///   `AppUser.needsProfileCompletion` returns false for managers.
enum AppRoute: String, Equatable {
    case setup
    case restoring
    case login
    case profileLoading
    case forcedPasswordChange
    case profileCompletion
    case deviceAuthGate
    case managerMain
    case staffMain

    static func determine(
        hasFirebaseConfig: Bool,
        isRestoring: Bool,
        uid: String?,
        user: AppUser?,
        deviceAuthEnabled: Bool,
        deviceAuthVerified: Bool
    ) -> AppRoute {
        guard hasFirebaseConfig else { return .setup }
        if isRestoring { return .restoring }
        guard uid != nil else { return .login }
        guard let user else { return .profileLoading }
        if user.mustChangePassword { return .forcedPasswordChange }
        if user.needsProfileCompletion { return .profileCompletion }
        if deviceAuthEnabled && !deviceAuthVerified { return .deviceAuthGate }
        return user.role == .manager ? .managerMain : .staffMain
    }
}
