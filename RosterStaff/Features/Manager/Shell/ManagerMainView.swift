import SwiftUI

struct ManagerMainView: View {
    @Environment(RosterRepository.self) private var repo
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
                sidebar
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

    // MARK: - Sidebar (iPad / macOS)

    /// The original plain sidebar list, with Account moved out of the list
    /// and pinned to the bottom as a profile row.
    private var sidebar: some View {
        List(ManagerTab.allCases.filter { $0 != .account }, selection: Binding(
            get: { selectedTab },
            set: { if let val = $0 { selectedTab = val } }
        )) { tab in
            NavigationLink(value: tab) {
                Label(tab.title, systemImage: tab.icon)
            }
        }
        .navigationTitle("Manager Portal")
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
    }

    private var sidebarFooter: some View {
        Button {
            selectedTab = .account
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.brand.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String((repo.currentUser?.fullName ?? "M").prefix(2)).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.brand)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.currentUser?.fullName ?? "—")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(repo.currentUser?.email ?? "")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedTab == .account ? Theme.brand.opacity(0.12) : .clear)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityLabel("Account settings")
    }
}

#Preview {
    ManagerMainView()
}