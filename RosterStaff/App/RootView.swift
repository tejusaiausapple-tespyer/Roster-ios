import SwiftUI

/// Top-level router. Chooses which screen to present based on Firebase config,
/// auth session, account status, and the gating flags — mirroring the web app's
/// RequireStaff + ProfileCompletionGate + DeviceAuthGate chain.
struct RootView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.28), value: stateKey)
            .onAppear { auth.bind(repository: repo) }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active: auth.handleScenePhase(.active)
                case .inactive: auth.handleScenePhase(.inactive)
                case .background: auth.handleScenePhase(.background)
                @unknown default: break
                }
            }
            .onChange(of: repo.currentUser?.status) { _, status in
                // If the account is locked/deactivated mid-session, sign out.
                guard let status, auth.uid != nil else { return }
                if status == .locked {
                    auth.forceSignOut(message: AuthError.accountLocked.errorDescription ?? "")
                } else if status == .inactive {
                    auth.forceSignOut(message: AuthError.accountInactive.errorDescription ?? "")
                }
            }
    }

    // A key that changes whenever the presented screen should change (drives animation).
    private var stateKey: String {
        if !FirebaseBootstrap.hasConfigFile { return "setup" }
        if auth.isRestoring { return "restoring" }
        if auth.uid == nil { return "login" }
        guard let user = repo.currentUser else { return "profileLoading" }
        if user.role == .manager { return "manager" }
        if user.mustChangePassword { return "changePassword" }
        if user.needsProfileCompletion { return "profile" }
        if auth.deviceAuthEnabled && !auth.deviceAuthVerified { return "gate" }
        return "main"
    }

    @ViewBuilder
    private var content: some View {
        if !FirebaseBootstrap.hasConfigFile {
            SetupRequiredView()
        } else if auth.isRestoring {
            SplashView()
        } else if auth.uid == nil {
            LoginView()
        } else if let user = repo.currentUser {
            switch true {
            case user.role == .manager:
                ManagerMainView()
            case user.mustChangePassword:
                ChangePasswordView(isForced: true)
            case user.needsProfileCompletion:
                ProfileCompletionView(user: user)
            case auth.deviceAuthEnabled && !auth.deviceAuthVerified:
                DeviceAuthGateView()
            default:
                MainTabView()
            }
        } else {
            SplashView()
        }
    }
}

/// Simple branded splash / loading screen.
struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                AppLogoMark(size: 76)
                ProgressView()
                    .tint(Theme.brand)
            }
        }
    }
}

/// A compact rendering of the app logo (roster card + clock), used on splash/login.
struct AppLogoMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Theme.brand)
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
