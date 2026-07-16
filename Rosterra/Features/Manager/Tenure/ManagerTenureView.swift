import SwiftUI

// Manager Tenure & Hours: per-staff service tenure (from first approved shift)
// and approved-hours totals, computed from already-loaded users, shifts, and
// timesheets. Mirrors the web app's Tenure Summary (core metrics only — no
// export). Detail sheet drills into one staff member's breakdown.
struct ManagerTenureView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var searchText = ""
    @State private var activeOnly = true
    @State private var sortBy: SortField = .name
    @State private var selected: TenureMetrics.StaffTenure?

    var embedInNavigationStack = true

    enum SortField: String, CaseIterable, Identifiable {
        case name, tenure, hours
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: return "Name"
            case .tenure: return "Tenure"
            case .hours: return "Hours"
            }
        }
    }

    private var rows: [TenureMetrics.StaffTenure] {
        TenureMetrics.compute(users: repo.allUsers, timesheets: repo.timesheets, shifts: repo.shifts)
    }

    private var filtered: [TenureMetrics.StaffTenure] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows
            .filter { !activeOnly || $0.status == .active }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .sorted { a, b in
                switch sortBy {
                case .name: return a.name < b.name
                case .tenure: return a.tenureDays > b.tenureDays
                case .hours: return a.totalApprovedHours > b.totalApprovedHours
                }
            }
    }

    // MARK: - KPIs

    private var withShifts: [TenureMetrics.StaffTenure] { rows.filter { $0.firstApprovedDate != nil } }
    private var avgTenureDays: Double {
        guard !withShifts.isEmpty else { return 0 }
        return Double(withShifts.reduce(0) { $0 + $1.tenureDays }) / Double(withShifts.count)
    }
    private var totalApprovedHours: Double { rows.reduce(0) { $0 + $1.totalApprovedHours } }

    var body: some View {
        if embedInNavigationStack {
            NavigationStack { rootContent }
        } else {
            rootContent
        }
    }

    private var rootContent: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                controlBar
                if filtered.isEmpty {
                    emptyState
                    Spacer()
                } else {
                    list
                }
            }
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Tenure & Hours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Tenure & Hours", icon: "rosette")
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name")
        .sheet(item: $selected) { row in
            ManagerTenureDetailSheet(row: row)
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        VStack(spacing: 10) {
            kpiStrip
            HStack(spacing: 8) {
                Picker("Sort", selection: $sortBy) {
                    ForEach(SortField.allCases) { field in
                        Text(field.title).tag(field)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $activeOnly) {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .tint(Theme.brand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var kpiStrip: some View {
        HStack(spacing: 12) {
            kpi("\(withShifts.count)", "With shifts", "person.2.fill")
            kpi(TenureMetrics.friendlyDays(avgTenureDays), "Avg tenure", "rosette")
            kpi(RosterFormat.decimalHours(totalApprovedHours), "Approved hrs", "clock.fill")
        }
    }

    private func kpi(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Theme.brand)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card))
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 12)], spacing: 12) {
                ForEach(filtered) { row in
                    Button {
                        selected = row
                        Haptics.selection()
                    } label: {
                        card(row)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable { await repo.refreshFromServer() }
    }

    private func card(_ row: TenureMetrics.StaffTenure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(row.initials)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.brand.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(row.employmentType?.label ?? "—")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            Divider().overlay(Theme.separator)
            HStack {
                metric("Tenure", TenureMetrics.tenureString(days: row.tenureDays))
                Spacer()
                metric("Approved", RosterFormat.hours(row.totalApprovedHours))
                Spacer()
                metric("Avg/wk", RosterFormat.hours(row.avgWeeklyHours))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "rosette",
            title: searchText.isEmpty ? "No staff to show" : "No matches for \"\(searchText)\""
        )
        .padding(.top, 40)
    }
}

// MARK: - Detail sheet

struct ManagerTenureDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let row: TenureMetrics.StaffTenure

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    detailRow("Tenure", TenureMetrics.tenureString(days: row.tenureDays))
                    detailRow("First approved shift", row.firstApprovedDate.map { RosterFormat.date(RosterCalendar.dayFormatter.string(from: $0)) } ?? "No approved shifts")
                    detailRow("Start date", row.startDate.map { RosterFormat.date(RosterCalendar.dayFormatter.string(from: $0)) } ?? "—")
                }
                Section("Hours") {
                    detailRow("Total approved", RosterFormat.hours(row.totalApprovedHours))
                    detailRow("Average per week", RosterFormat.hours(row.avgWeeklyHours))
                }
                Section("Employment") {
                    detailRow("Type", row.employmentType?.label ?? "—")
                    detailRow("Status", row.status.rawValue.capitalized)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(row.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    ManagerTenureView()
        .environment(RosterRepository())
}
