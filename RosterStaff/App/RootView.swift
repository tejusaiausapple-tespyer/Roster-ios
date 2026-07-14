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
            .animation(.easeInOut(duration: 0.28), value: route)
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

    /// The single routing decision — pure and unit-tested in AppRouteTests.
    /// Gates (forced password change, device auth) apply to both roles.
    private var route: AppRoute {
        AppRoute.determine(
            hasFirebaseConfig: FirebaseBootstrap.hasConfigFile,
            isRestoring: auth.isRestoring,
            uid: auth.uid,
            user: repo.currentUser,
            deviceAuthEnabled: auth.deviceAuthEnabled,
            deviceAuthVerified: auth.deviceAuthVerified
        )
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .setup:
            SetupRequiredView()
        case .restoring, .profileLoading:
            SplashView()
        case .login:
            LoginView()
        case .forcedPasswordChange:
            ChangePasswordView(isForced: true)
        case .profileCompletion:
            if let user = repo.currentUser {
                ProfileCompletionView(user: user)
            } else {
                SplashView()
            }
        case .deviceAuthGate:
            DeviceAuthGateView()
        case .managerMain:
            ManagerMainView()
        case .staffMain:
            MainTabView()
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
        Image("AppLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}
