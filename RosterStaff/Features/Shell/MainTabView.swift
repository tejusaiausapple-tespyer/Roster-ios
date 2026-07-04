import SwiftUI

/// The main staff experience: five tabs using the native bottom tab bar.
/// A standard `TabView` keeps thumb-reach, safe-area handling, and
/// accessibility behaviour consistent with the rest of iOS — no bespoke
/// floating chrome competing with content.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppRouter.Tab.home.rawValue)
            RosterView()
                .tabItem { Label("Roster", systemImage: "calendar") }
                .tag(AppRouter.Tab.roster.rawValue)
            TasksView()
                .tabItem { Label("Tasks", systemImage: "list.bullet.clipboard") }
                .tag(AppRouter.Tab.tasks.rawValue)
            AvailabilityView()
                .tabItem { Label("Availability", systemImage: "calendar.badge.clock") }
                .tag(AppRouter.Tab.availability.rawValue)
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppRouter.Tab.account.rawValue)
        }
        .tint(Theme.brand)
    }
}

/// A scroll container preconfigured with screen padding, used by every tab.
struct TabScroll<Content: View>: View {
    var topPadding: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                content
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, topPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }
}
