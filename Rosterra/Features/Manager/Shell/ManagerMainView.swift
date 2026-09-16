import SwiftUI

struct ManagerMainView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AppRouter.self) private var router
    @Environment(TitlePillCollapse.self) private var titlePillCollapse
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    private var selectedTab: ManagerTab {
        get { router.selectedManagerTab }
        nonmutating set { router.selectedManagerTab = newValue }
    }

    var body: some View {
        content
            .onChange(of: router.selectedManagerTab) {
                titlePillCollapse.fraction = 0
                Haptics.tabChange()
            }
    }

    @ViewBuilder
    private var content: some View {
        if PlatformUI.isPhone {
            // iOS Compact Layout: 5 visible bottom tabs
            TabView(selection: Binding(get: { selectedTab }, set: { selectedTab = $0 })) {
                ManagerDashboardView()
                .tabItem {
                    Label(ManagerTab.dashboard.title, systemImage: ManagerTab.dashboard.icon)
                }
                .tag(ManagerTab.dashboard)
                
                ManagerRosterView()
                .tabItem {
                    Label(ManagerTab.roster.title, systemImage: ManagerTab.roster.icon)
                }
                .tag(ManagerTab.roster)
                
                ManagerTasksView()
                .tabItem {
                    Label("Tasks", systemImage: ManagerTab.tasks.icon)
                }
                .tag(ManagerTab.tasks)
                
                ManagerTimesheetsView()
                .tabItem {
                    Label(ManagerTab.timesheets.title, systemImage: ManagerTab.timesheets.icon)
                }
                .tag(ManagerTab.timesheets)
                .badge(badge(for: .timesheets))

                ManagerAccountView()
                .tabItem {
                    Label(ManagerTab.account.title, systemImage: ManagerTab.account.icon)
                }
                .tag(ManagerTab.account)
            }
            .tint(Theme.brand)
            .phoneTabBarMinimizeOnScroll()
        } else {
            // iPadOS & macOS: solid source-list sidebar with every ManagerTab
            // (Account pinned in the profile footer).
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 248, ideal: 280, max: 340)
            } detail: {
                switch selectedTab {
                case .account:
                    ManagerAccountView()
                case .dashboard:
                    ManagerDashboardView()
                case .roster:
                    ManagerRosterView()
                case .tasks:
                    ManagerTasksView()
                case .timesheets:
                    ManagerTimesheetsView()
                case .staff:
                    ManagerStaffView()
                case .availability:
                    ManagerAvailabilityView()
                case .reports:
                    ManagerReportsView()
                case .tenure:
                    ManagerTenureView()
                case .wage:
                    NavigationStack { ManagerWageView(embedInNavigationStack: false) }
                case .payroll:
                    NavigationStack { ManagerPayrollView(embedInNavigationStack: false) }
                }
            }
        }
    }

    // MARK: - Sidebar (iPad / macOS)

    /// Floating source-list: inset rounded card, grouped destinations,
    /// profile footer. Account stays out of the list and is pinned at the bottom.
    private var sidebar: some View {
        FloatingSidebarPanel {
            VStack(spacing: 0) {
                SidebarBrandHeader(
                    companyName: repo.appSettings.companyName,
                    roleLabel: "Manager"
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(ManagerSidebarSection.allCases) { section in
                            SidebarSectionLabel(title: section.title)
                            ForEach(section.tabs) { tab in
                                SidebarItemRow(
                                    title: tab.title,
                                    icon: tab.icon,
                                    isSelected: selectedTab == tab,
                                    badge: badge(for: tab)
                                ) {
                                    selectedTab = tab
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                SidebarProfileFooter(
                    name: repo.currentUser?.fullName ?? "—",
                    email: repo.currentUser?.email ?? "",
                    initials: repo.currentUser?.initials ?? "M",
                    isSelected: selectedTab == .account
                ) {
                    selectedTab = .account
                }
            }
        }
        .navigationTitle("Manager")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sidebarColumnFill()
        // The system edge-swipe opens the sidebar, but there is no built-in
        // right-to-left swipe to dismiss it. Mirror the gesture: a leftward
        // drag anywhere on the sidebar collapses it. Mouse users use the
        // system sidebar toggle (or View → Hide Sidebar on Mac).
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

    private func badge(for tab: ManagerTab) -> Int {
        switch tab {
        case .timesheets:
            return repo.timesheets.filter { $0.status == .pending }.count
        default:
            return 0
        }
    }
}

#Preview {
    ManagerMainView()
}