import SwiftUI

@main
struct RosterraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("preferredColorScheme") private var preferredColorSchemeSetting: String = "system"

    @State private var repository = RosterRepository()
    @State private var auth = AuthViewModel()
    @State private var router = AppRouter()
    @State private var titlePillCollapse = TitlePillCollapse()

    private var preferredColorScheme: ColorScheme? {
        switch preferredColorSchemeSetting {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(repository)
                .environment(auth)
                .environment(router)
                .environment(titlePillCollapse)
                .preferredColorScheme(preferredColorScheme)
                .tint(Theme.brand)
                .onOpenURL { url in router.handle(url: url) }
                .onAppear { AppRouter.shared = router }
        }
    }
}
