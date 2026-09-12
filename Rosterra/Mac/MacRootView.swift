#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacRootView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(MacNavigationModel.self) private var macNav
    @Environment(MacToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase

    @State private var versionCheck = AppVersionCheckViewModel()

    init() {}

    var body: some View {
        ZStack {
            MacColor.windowBackground.ignoresSafeArea()

            content
                .macObserved(repo: repo, auth: auth, nav: macNav, toasts: toasts)
                .animation(MacMotion.normal, value: route)
        }
        .background {
            MacWindowConfigurator()
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            auth.bind(repository: repo)
            MacWindow.configureAllScenes()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                MacWindow.configureAllScenes()
                auth.handleScenePhase(.active)
                Task { await versionCheck.check() }
            case .inactive:
                auth.handleScenePhase(.inactive)
            case .background:
                auth.handleScenePhase(.background)
            @unknown default:
                break
            }
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
        case .managerMain, .staffMain:
            MacShellView()
        }
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
