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

    /// Branded, sectioned sidebar mirroring the PWA's design language:
    /// company header, grouped nav with tinted icon chips, and a profile
    /// footer that jumps to the Account tab.
    private var sidebar: some View {
        List(selection: Binding(
            get: { selectedTab },
            set: { if let val = $0 { selectedTab = val } }
        )) {
            ForEach(ManagerSidebarSection.allCases, id: \.self) { section in
                Section {
                    ForEach(section.tabs) { tab in
                        NavigationLink(value: tab) {
                            sidebarRow(tab)
                        }
                    }
                } header: {
                    if let title = section.title {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                            .kerning(0.6)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(Theme.brand)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { sidebarHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
    }

    private func sidebarRow(_ tab: ManagerTab) -> some View {
        let selected = selectedTab == tab
        return HStack(spacing: 12) {
            Image(systemName: tab.icon)
                .font(.subheadline.weight(.semibold))
                .symbolVariant(selected ? .fill : .none)
                .foregroundStyle(selected ? Theme.brand : Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.brand.opacity(0.14) : Theme.textTertiary.opacity(0.10))
                )
            Text(tab.title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
        }
        .padding(.vertical, 3)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.heroGradient)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.appSettings.companyName.isEmpty ? "Roster" : repo.appSettings.companyName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("Manager Portal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.brand)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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