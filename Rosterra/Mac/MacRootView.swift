#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacRootView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(MacNavigationModel.self) private var macNav
    @Environment(MacToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase

    @State private var versionCheck = AppVersionCheckViewModel()
    @State private var hasCheckedInitialVersion = false
    @State private var isCheckingForegroundVersion = false

    init() {}

    var body: some View {
        ZStack {
            MacColor.windowBackground.ignoresSafeArea()

            content
                .macObserved(repo: repo, auth: auth, nav: macNav, toasts: toasts)
                .animation(MacMotion.normal, value: route)
                // Foreground policy checks must preserve the mounted login
                // form and any editor state while temporarily blocking input.
                .allowsHitTesting(!isCheckingForegroundVersion)
                .overlay {
                    if isCheckingForegroundVersion {
                        MacSplashView()
                    }
                }
        }
        .background {
            MacWindowConfigurator()
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            MacWindow.configureAllScenes()
        }
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
                MacWindow.configureAllScenes()
                isCheckingForegroundVersion = true
                Task {
                    await versionCheck.check()
                    isCheckingForegroundVersion = false
                    guard !versionCheck.isAccessBlocked else { return }
                    NotificationService.shared.setVersionAccessAllowed(true)
                    auth.handleScenePhase(.active)
                }
            case .inactive:
                auth.handleScenePhase(.inactive)
            case .background:
                auth.handleScenePhase(.background)
            @unknown default:
                break
            }
        }
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
        .alert("Refresh failed", isPresented: Binding(
            get: { repo.refreshError != nil },
            set: { if !$0 { repo.refreshError = nil } }
        )) {
            Button("OK", role: .cancel) { repo.refreshError = nil }
        } message: {
            Text(repo.refreshError ?? "")
        }
        .onChange(of: repo.currentUser?.status) { _, status in
            guard let status, auth.uid != nil else { return }
            if status == .locked {
                auth.forceSignOut(message: AuthError.accountLocked.errorDescription ?? "")
            } else if status == .inactive {
                auth.forceSignOut(message: AuthError.accountInactive.errorDescription ?? "")
            }
        }
    }

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
            MacSplashView()
        } else if versionCheck.isPolicyUnavailable {
            VersionPolicyUnavailableView {
                isCheckingForegroundVersion = true
                await versionCheck.check()
                isCheckingForegroundVersion = false
            }
        } else if auth.uid != nil, repo.currentUser?.role == .staff {
            // Staff profile and role-review requirements are completed in the
            // iPhone app. Mac is a manager-only workspace and must not expose
            // those staff gates before the role check.
            MacManagerAccessRequiredView()
        } else {
            switch route {
            case .setup:
                MacSetupRequiredView()
            case .restoring, .profileLoading:
                MacSplashView()
            case .login:
                MacLoginView()
            case .forcedPasswordChange:
                MacChangePasswordView(isForced: true)
            case .profileCompletion:
                if let user = repo.currentUser {
                    MacProfileCompletionView(user: user)
                } else {
                    MacSplashView()
                }
            case .deviceAuthGate:
                MacDeviceAuthGateView()
            case .managerMain:
                MacShellView()
            case .staffMain:
                MacManagerAccessRequiredView()
            }
        }
    }
}

private struct MacManagerAccessRequiredView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        VStack(spacing: MacSpace.xl) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(MacColor.accent)
                .frame(width: 82, height: 82)
                .background(MacColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: MacRadius.extraLarge))

            VStack(spacing: MacSpace.sm) {
                Text("Manager access required")
                    .font(MacType.pageTitle)
                    .foregroundStyle(MacColor.textPrimary)
                Text("Rosterra for Mac is the manager workspace. Staff can view rosters, timesheets and published payslips in the iPhone app.")
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            Button("Sign Out") {
                auth.signOut()
            }
            .macButton(.prominent)
        }
        .padding(MacSpace.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.windowBackground)
    }
}

struct MacSplashView: View {
    init() {}

    var body: some View {
        VStack(spacing: MacSpace.lg) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: 12, y: 4)

            ProgressView()
                .controlSize(.regular)
                .tint(MacColor.accent)

            Text("Loading Rosterra...")
                .font(MacType.body)
                .foregroundStyle(MacColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
