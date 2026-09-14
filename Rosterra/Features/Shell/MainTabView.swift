import SwiftUI

/// The main staff experience.
/// iPhone: native bottom tab bar.
/// iPad / Mac Catalyst: sidebar so a pointer and a resized window have a
/// stable navigation column instead of a phone-sized tab bar.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RosterRepository.self) private var repo
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        @Bindable var router = router

        Group {
            if PlatformUI.isPhone {
                phoneTabs
            } else {
                splitChrome
            }
        }
        .tint(Theme.brand)
        .onChange(of: router.selectedTab) { Haptics.tabChange() }
    }

    private var phoneTabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label(AppRouter.Tab.home.title, systemImage: AppRouter.Tab.home.icon) }
                .tag(AppRouter.Tab.home.rawValue)
            RosterView()
                .tabItem { Label(AppRouter.Tab.roster.title, systemImage: AppRouter.Tab.roster.icon) }
                .tag(AppRouter.Tab.roster.rawValue)
            PayslipsView()
                .tabItem { Label(AppRouter.Tab.payslips.title, systemImage: AppRouter.Tab.payslips.icon) }
                .tag(AppRouter.Tab.payslips.rawValue)
            AvailabilityView()
                .tabItem { Label(AppRouter.Tab.availability.title, systemImage: AppRouter.Tab.availability.icon) }
                .tag(AppRouter.Tab.availability.rawValue)
            AccountView()
                .tabItem { Label(AppRouter.Tab.account.title, systemImage: AppRouter.Tab.account.icon) }
                .tag(AppRouter.Tab.account.rawValue)
        }
    }

    private var splitChrome: some View {
        @Bindable var router = router
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            staffSidebar
                .navigationSplitViewColumnWidth(min: 248, ideal: 280, max: 340)
        } detail: {
            switch AppRouter.Tab(rawValue: router.selectedTab) ?? .home {
            case .home: HomeView()
            case .roster: RosterView()
            case .payslips: PayslipsView()
            case .availability: AvailabilityView()
            case .account: AccountView()
            }
        }
    }

    /// Floating source-list matching the manager Mac/iPad chrome. Account is
    /// pinned in the profile footer rather than listed with the work tabs.
    private var staffSidebar: some View {
        @Bindable var router = router
        return FloatingSidebarPanel {
            VStack(spacing: 0) {
                SidebarBrandHeader(
                    companyName: repo.appSettings.companyName,
                    roleLabel: "Staff"
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        SidebarSectionLabel(title: "Work")
                        ForEach(staffWorkTabs) { tab in
                            SidebarItemRow(
                                title: tab.title,
                                icon: tab.icon,
                                isSelected: router.selectedTab == tab.rawValue,
                                badge: tab == .home ? repo.unreadMessageCount : 0
                            ) {
                                router.select(tab)
                            }
                        }
                        SidebarSectionLabel(title: "Planning")
                        SidebarItemRow(
                            title: AppRouter.Tab.availability.title,
                            icon: AppRouter.Tab.availability.icon,
                            isSelected: router.selectedTab == AppRouter.Tab.availability.rawValue
                        ) {
                            router.select(.availability)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                SidebarProfileFooter(
                    name: repo.currentUser?.fullName ?? "—",
                    email: repo.currentUser?.email ?? "",
                    initials: repo.currentUser?.initials ?? "S",
                    isSelected: router.selectedTab == AppRouter.Tab.account.rawValue
                ) {
                    router.select(.account)
                }
            }
        }
        .navigationTitle("Staff")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sidebarColumnFill()
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40,
                       abs(value.translation.width) > abs(value.translation.height) {
                        withAnimation { columnVisibility = .detailOnly }
                    }
                }
        )
    }

    private var staffWorkTabs: [AppRouter.Tab] {
        [.home, .roster, .payslips]
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
            .contentLane()
            .tracksTitlePillCollapse()
        }
        .platformScrollIndicators()
        .background(Theme.background.ignoresSafeArea())
    }
}
