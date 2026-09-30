import SwiftUI

/// Top-level router. Chooses which screen to present based on Firebase config,
/// auth session, account status, and the gating flags — mirroring the web app's
/// RequireStaff + ProfileCompletionGate + DeviceAuthGate chain.
struct RootView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var versionCheck = AppVersionCheckViewModel()
    @State private var hasCheckedInitialVersion = false
    @State private var isCheckingForegroundVersion = false

    var body: some View {
        content
            // Keep the mounted form (and its in-flight sign-in) alive when
            // returning from password AutoFill, Face ID, or another app.
            // Replacing it with the splash screen discards its @State fields.
            .allowsHitTesting(!isCheckingForegroundVersion)
            .overlay {
                if isCheckingForegroundVersion {
                    SplashView()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.28), value: route)
            // `onChange(scenePhase)` is not guaranteed to fire for the initial
            // active value, so cold launch needs an explicit first check.
            .task {
                await versionCheck.check()
                hasCheckedInitialVersion = true
                if !versionCheck.isAccessBlocked {
                    NotificationService.shared.setVersionAccessAllowed(true)
                    auth.bind(repository: repo)
                }
                versionCheck.startListeningForUpdates()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    isCheckingForegroundVersion = true
                    Task {
                        await versionCheck.check()
                        isCheckingForegroundVersion = false
                        guard !versionCheck.isAccessBlocked else { return }
                        NotificationService.shared.setVersionAccessAllowed(true)
                        auth.handleScenePhase(.active)
                        repo.refreshShiftLiveActivity()
                    }
                case .inactive: auth.handleScenePhase(.inactive)
                case .background: auth.handleScenePhase(.background)
                @unknown default: break
                }
            }
            // Re-check immediately after login while the scene stays `.active`
            // (launch alone would otherwise miss a mid-session credential change).
            .onChange(of: auth.uid) { _, newUID in
                guard newUID != nil else { return }
                Task { await versionCheck.check() }
            }
            .onChange(of: versionCheck.isAccessBlocked) { _, blocked in
                if blocked {
                    NotificationService.shared.setVersionAccessAllowed(false)
                    repo.stop()
                } else if hasCheckedInitialVersion {
                    NotificationService.shared.setVersionAccessAllowed(true)
                    if let uid = auth.uid { repo.start(uid: uid) }
                    else { auth.bind(repository: repo) }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { versionCheck.isUpdateRequired },
                set: { _ in }
            )) {
                if case .required(let minimumVersion) = versionCheck.status {
                    UpdateRequiredView(minimumVersion: minimumVersion)
                }
            }
            .sheet(isPresented: Binding(
                get: { versionCheck.isUpdateAvailable },
                set: { isPresented in
                    if !isPresented { versionCheck.dismissOptionalUpdate() }
                }
            )) {
                if case .optional(let latestVersion) = versionCheck.status {
                    UpdateAvailableSheet(latestVersion: latestVersion) {
                        versionCheck.dismissOptionalUpdate()
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { router.pendingPasswordResetCode != nil },
                set: { if !$0 { router.pendingPasswordResetCode = nil } }
            )) {
                if let code = router.pendingPasswordResetCode {
                    PasswordResetSheet(code: code)
                }
            }
            .alert("Refresh failed", isPresented: Binding(
                get: { repo.refreshError != nil },
                set: { if !$0 { repo.refreshError = nil } }
            )) {
                Button("OK", role: .cancel) { repo.refreshError = nil }
            } message: {
                Text(repo.refreshError ?? "")
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
        if !hasCheckedInitialVersion || versionCheck.isUpdateRequired {
            SplashView()
        } else if versionCheck.isPolicyUnavailable {
            VersionPolicyUnavailableView {
                isCheckingForegroundVersion = true
                await versionCheck.check()
                isCheckingForegroundVersion = false
            }
        } else {
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
