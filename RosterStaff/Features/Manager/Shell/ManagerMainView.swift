import SwiftUI

struct ManagerMainView: View {
    @State private var selectedTab: ManagerTab = .dashboard
    
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            // iOS Compact Layout: 5 visible bottom tabs
            TabView(selection: $selectedTab) {
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
                
                NavigationStack {
                    ManagerPlaceholderView(tab: .tasks)
                }
                .tabItem {
                    Label("Tasks", systemImage: ManagerTab.tasks.icon)
                }
                .tag(ManagerTab.tasks)
                
                ManagerTimesheetsView()
                .tabItem {
                    Label(ManagerTab.timesheets.title, systemImage: ManagerTab.timesheets.icon)
                }
                .tag(ManagerTab.timesheets)

                ManagerAccountView()
                .tabItem {
                    Label(ManagerTab.account.title, systemImage: ManagerTab.account.icon)
                }
                .tag(ManagerTab.account)
            }
            .tint(Color(hex: 0x4F46E5))
        } else {
            // iPadOS & macOS: Sidebar split view with all 10 tabs
            NavigationSplitView {
                List(ManagerTab.allCases, selection: Binding(
                    get: { selectedTab },
                    set: { if let val = $0 { selectedTab = val } }
                )) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
                .navigationTitle("Manager Portal")
                .listStyle(.sidebar)
            } detail: {
                switch selectedTab {
                case .account:
                    ManagerAccountView()
                case .dashboard:
                    ManagerDashboardView()
                case .roster:
                    ManagerRosterView()
                case .timesheets:
                    ManagerTimesheetsView()
                case .staff:
                    ManagerStaffView()
                case .availability:
                    ManagerAvailabilityView()
                case .reports:
                    ManagerReportsView()
                case .wage:
                    NavigationStack { ManagerWageView(embedInNavigationStack: false) }
                default:
                    NavigationStack {
                        ManagerPlaceholderView(tab: selectedTab)
                    }
                }
            }
        }
    }
}

#Preview {
    ManagerMainView()
}