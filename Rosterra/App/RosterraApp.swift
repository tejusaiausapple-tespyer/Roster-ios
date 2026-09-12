import SwiftUI

@main
struct RosterraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("preferredColorScheme") private var preferredColorSchemeSetting: String = "system"

    @State private var repository = RosterRepository()
    @State private var auth = AuthViewModel()
    @State private var router = AppRouter()
    @State private var titlePillCollapse = TitlePillCollapse()

    #if targetEnvironment(macCatalyst)
    // Owned here rather than inside `MacRootView` so the menu bar, which is
    // declared on this scene, drives the same instances the window renders.
    @State private var macNavigation = MacNavigationModel()
    @State private var macToasts = MacToastCenter()
    #endif

    private var preferredColorScheme: ColorScheme? {
        switch preferredColorSchemeSetting {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(macCatalyst)
            MacRootView()
                .environment(repository)
                .environment(auth)
                .environment(router)
                .environment(titlePillCollapse)
                .environment(macNavigation)
                .environment(macToasts)
                .tint(MacColor.accent)
                .textSelection(.enabled)
                .preferredColorScheme(preferredColorScheme)
                .onOpenURL { url in router.handle(url: url) }
                .onAppear {
                    AppRouter.shared = router
                    NotificationService.shared.replayPendingTapIfNeeded()
                }
            #else
            RootView()
                .environment(repository)
                .environment(auth)
                .environment(router)
                .environment(titlePillCollapse)
                .tint(Theme.brand)
                .macTextSelection()
                .preferredColorScheme(preferredColorScheme)
                .onOpenURL { url in router.handle(url: url) }
                .onAppear {
                    AppRouter.shared = router
                    NotificationService.shared.replayPendingTapIfNeeded()
                }
            #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: MacWindow.defaultSize.width, height: MacWindow.defaultSize.height)
        .windowResizability(.automatic)
        // Do not use `.contentMinSize`: a wide screen would become the window
        // minimum and freeze resizing. Floor/ceiling come from
        // `MacWindow.minimumSize` / `maximumSize` (Catalyst needs both).
        .commands {
            SidebarCommands()
            MacCommands(
                repository: repository,
                auth: auth,
                router: router,
                navigation: macNavigation,
                colorSchemeSetting: $preferredColorSchemeSetting
            )
        }
        #endif
    }
}
