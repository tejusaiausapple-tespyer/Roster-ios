#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacManagerTenureView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var searchText = ""
    @State private var activeOnly = true
    @State private var sortBy: SortField = .name
    @State private var selectedStaffID: String?

    private enum SortField: String, CaseIterable, Identifiable {
        case name
        case tenure
        case hours

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .tenure: return "Tenure"
            case .hours: return "Hours"
            }
        }

        var icon: String {
            switch self {
            case .name: return "textformat"
            case .tenure: return "rosette"
            case .hours: return "clock"
            }
        }
    }

    private var rows: [TenureMetrics.StaffTenure] {
        TenureMetrics.compute(
            users: repo.allUsers,
            timesheets: repo.timesheets,
            shifts: repo.shifts
        )
    }

    private var filteredRows: [TenureMetrics.StaffTenure] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows
            .filter { !activeOnly || $0.status == .active }
            .filter {
                query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                switch sortBy {
                case .name:
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .tenure:
                    if lhs.tenureDays == rhs.tenureDays {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.tenureDays > rhs.tenureDays
                case .hours:
                    if lhs.totalApprovedHours == rhs.totalApprovedHours {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.totalApprovedHours > rhs.totalApprovedHours
                }
            }
    }

    private var selectedRow: TenureMetrics.StaffTenure? {
        guard let selectedStaffID else { return filteredRows.first }
        return filteredRows.first { $0.id == selectedStaffID } ?? filteredRows.first
    }

    private var rowsWithApprovedShifts: [TenureMetrics.StaffTenure] {
        rows.filter { $0.firstApprovedDate != nil }
    }

    private var averageTenureDays: Double {
        guard !rowsWithApprovedShifts.isEmpty else { return 0 }
        let days = rowsWithApprovedShifts.reduce(0) { $0 + $1.tenureDays }
        return Double(days) / Double(rowsWithApprovedShifts.count)
    }

    private var totalApprovedHours: Double {
        rows.reduce(0) { $0 + $1.totalApprovedHours }
    }

    private var averageWeeklyHours: Double {
        let worked = rows.filter { $0.totalApprovedHours > 0 }
        guard !worked.isEmpty else { return 0 }
        return worked.reduce(0) { $0 + $1.avgWeeklyHours } / Double(worked.count)
    }

    var body: some View {
        MacScreen(
            title: "Tenure & Hours",
            subtitle: "Approved service history for \(rows.count) staff",
            actions: {
                MacRefreshButton("Refresh tenure data") {
                    await repo.refreshFromServer()
                }
            }
        ) {
            GeometryReader { geometry in
                VStack(spacing: MacSpace.md) {
                    controls
                    summaryStrip

                    HStack(spacing: 0) {
                        tenureList
                            .frame(
                                width: min(
                                    430,
                                    max(350, geometry.size.width * 0.37)
                                )
                            )

                        Rectangle()
                            .fill(MacColor.separator)
                            .frame(width: 1)

                        if let selectedRow {
                            tenureInspector(selectedRow)
                        } else {
                            MacEmptyState(
                                title: "No staff to show",
                                subtitle: searchText.isEmpty
                                    ? "Turn off Active staff only to include inactive staff."
                                    : "Try another name.",
                                icon: "rosette"
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .background(
                        MacColor.cardBackground,
                        in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                            .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
                }
                .padding(MacSpace.xl)
            }
        }
        .onAppear {
            maintainSelection()
        }
        .onChange(of: filteredRows.map(\.id)) { _, _ in
            maintainSelection()
        }
    }

    private var controls: some View {
        HStack(spacing: MacSpace.md) {
            HStack(spacing: 6) {
                ForEach(SortField.allCases) { field in
                    sortButton(field)
                }
            }

            Toggle("Active staff only", isOn: $activeOnly)
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer(minLength: MacSpace.lg)

            HStack(spacing: MacSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MacColor.textTertiary)

                TextField("Search staff", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MacType.body)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MacColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, MacSpace.md)
            .frame(width: 280)
            .frame(minHeight: 40)
            .background(
                MacColor.cardBackground,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: MacSpace.xl) {
            summaryItem(
                icon: "person.2.fill",
                value: "\(rowsWithApprovedShifts.count)",
                label: "With approved shifts"
            )
            summaryItem(
                icon: "rosette",
                value: TenureMetrics.friendlyDays(averageTenureDays),
                label: "Average tenure",
                tint: MacColor.warning
            )
            summaryItem(
                icon: "clock.fill",
                value: RosterFormat.decimalHours(totalApprovedHours),
                label: "Approved hours",
                tint: MacColor.success
            )
            summaryItem(
                icon: "chart.line.uptrend.xyaxis",
                value: RosterFormat.hours(averageWeeklyHours),
                label: "Average weekly",
                tint: MacColor.info
            )

            Spacer()

            Text("\(filteredRows.count) shown")
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textSecondary)
        }
        .padding(.horizontal, MacSpace.lg)
        .frame(minHeight: 52)
        .macGlassSurface(cornerRadius: MacRadius.large)
    }

    private var tenureList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STAFF")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.textTertiary)
                Spacer()
                Text(sortBy == .name ? "A–Z" : "BY \(sortBy.title.uppercased())")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.textTertiary)
            }
            .padding(.horizontal, MacSpace.lg)
            .frame(height: 44)
            .background(MacColor.tableHeaderBackground)

            if filteredRows.isEmpty {
                MacEmptyState(
                    title: "No staff to show",
                    subtitle: searchText.isEmpty
                        ? "Change the active staff filter."
                        : "No names match your search.",
                    icon: "person.2.slash"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredRows) { row in
                            tenureRow(row)
                        }
                    }
                    .padding(MacSpace.sm)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(MacColor.cardBackgroundSecondary)
    }

    private func tenureRow(_ row: TenureMetrics.StaffTenure) -> some View {
        let isSelected = selectedStaffID == row.id
            || (selectedStaffID == nil && filteredRows.first?.id == row.id)

        return Button {
            selectedStaffID = row.id
        } label: {
            VStack(alignment: .leading, spacing: MacSpace.sm) {
                HStack(spacing: MacSpace.md) {
                    MacAvatar(name: row.name, size: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name)
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)
                            .lineLimit(1)
                        Text(row.employmentType?.label ?? "Employment not set")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    Spacer()

                    Circle()
                        .fill(statusTint(row.status))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(row.status.rawValue.capitalized)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacColor.textTertiary)
                }

                HStack(spacing: MacSpace.lg) {
                    compactMetric("Tenure", TenureMetrics.tenureString(days: row.tenureDays))
                    compactMetric("Approved", RosterFormat.hours(row.totalApprovedHours))
                    compactMetric("Avg/wk", RosterFormat.hours(row.avgWeeklyHours))
                }
            }
            .padding(MacSpace.md)
            .background(
                isSelected ? MacColor.tableRowSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tenureInspector(_ row: TenureMetrics.StaffTenure) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacSpace.xl) {
                HStack(alignment: .top, spacing: MacSpace.lg) {
                    ZStack {
                        MacAvatar(name: row.name, size: 64)
                        Image(systemName: "rosette")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MacColor.warning)
                            .padding(5)
                            .background(MacColor.cardBackground, in: Circle())
                            .offset(x: 24, y: 24)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.name)
                            .font(MacType.pageTitle)
                            .foregroundStyle(MacColor.textPrimary)
                        Text(row.employmentType?.label ?? "Employment type not set")
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    Spacer()

                    statusPill(row.status)
                }

                HStack(spacing: MacSpace.md) {
                    inspectorMetric(
                        title: "Service tenure",
                        value: TenureMetrics.tenureString(days: row.tenureDays),
                        detail: row.firstApprovedDate == nil ? "No approved shifts" : "\(row.tenureDays) days",
                        icon: "rosette",
                        tint: MacColor.warning
                    )
                    inspectorMetric(
                        title: "Approved hours",
                        value: RosterFormat.hours(row.totalApprovedHours),
                        detail: "Lifetime total",
                        icon: "clock.fill",
                        tint: MacColor.success
                    )
                    inspectorMetric(
                        title: "Weekly average",
                        value: RosterFormat.hours(row.avgWeeklyHours),
                        detail: "Since first shift",
                        icon: "chart.bar.fill",
                        tint: MacColor.info
                    )
                }

                serviceMilestone(row)

                HStack(alignment: .top, spacing: MacSpace.md) {
                    detailCard(title: "Service record", icon: "calendar") {
                        detailRow("Employment start", formattedDate(row.startDate))
                        detailRow("First approved shift", formattedDate(row.firstApprovedDate))
                        detailRow("Service days", row.tenureDays > 0 ? "\(row.tenureDays)" : "—")
                    }

                    detailCard(title: "Employment", icon: "briefcase") {
                        detailRow("Type", row.employmentType?.label ?? "Not set")
                        detailRow("Status", row.status.rawValue.capitalized)
                        detailRow(
                            "Approved records",
                            row.firstApprovedDate == nil ? "None yet" : "Included"
                        )
                    }
                }
            }
            .padding(MacSpace.xxl)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.cardBackground)
    }

    private func serviceMilestone(_ row: TenureMetrics.StaffTenure) -> some View {
        Group {
            if row.firstApprovedDate == nil {
                HStack(spacing: MacSpace.md) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(MacColor.textTertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Service tenure has not started")
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)
                        Text("Tenure begins from the first approved shift.")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                    }
                    Spacer()
                }
                .padding(MacSpace.lg)
                .background(
                    MacColor.cardBackgroundSecondary,
                    in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                )
            } else {
                let completedYears = row.tenureDays / 365
                let daysIntoYear = row.tenureDays % 365
                let nextYear = completedYears + 1
                let daysRemaining = 365 - daysIntoYear

                VStack(alignment: .leading, spacing: MacSpace.md) {
                    HStack {
                        Label(
                            "\(nextYear)-year service milestone",
                            systemImage: "medal.fill"
                        )
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)

                        Spacer()

                        Text("\(daysRemaining) days remaining")
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    ProgressView(value: Double(daysIntoYear), total: 365)
                        .tint(MacColor.warning)
                }
                .padding(MacSpace.lg)
                .background(
                    MacColor.warning.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                        .strokeBorder(MacColor.warning.opacity(0.22), lineWidth: 1)
                }
            }
        }
    }

    private func sortButton(_ field: SortField) -> some View {
        let isSelected = sortBy == field
        return Button {
            sortBy = field
        } label: {
            Label(field.title, systemImage: field.icon)
                .font(MacType.captionStrong)
                .foregroundStyle(isSelected ? Color.white : MacColor.textPrimary)
                .padding(.horizontal, MacSpace.md)
                .frame(minHeight: 36)
                .background(
                    isSelected ? MacColor.textPrimary : MacColor.cardBackground,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : MacColor.cardBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func summaryItem(
        icon: String,
        value: String,
        label: String,
        tint: Color = MacColor.textPrimary
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
        }
    }

    private func compactMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
            Text(value)
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorMetric(
        title: String,
        value: String,
        detail: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(MacType.monoLarge)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textSecondary)
            Text(detail)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MacColor.cardBackgroundSecondary,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func detailCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            Label(title, systemImage: icon)
                .font(MacType.sectionHeader)
                .foregroundStyle(MacColor.textPrimary)
            content()
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            MacColor.cardBackgroundSecondary,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
            Spacer(minLength: MacSpace.md)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusPill(_ status: UserStatus) -> some View {
        MacStatusPill(
            text: status.rawValue.capitalized,
            foreground: statusTint(status),
            background: statusTint(status).opacity(0.12),
            border: statusTint(status).opacity(0.3),
            icon: statusIcon(status)
        )
    }

    private func statusTint(_ status: UserStatus) -> Color {
        switch status {
        case .active: return MacColor.success
        case .inactive: return MacColor.textTertiary
        case .locked: return MacColor.error
        }
    }

    private func statusIcon(_ status: UserStatus) -> String {
        switch status {
        case .active: return "checkmark.circle.fill"
        case .inactive: return "pause.circle.fill"
        case .locked: return "lock.fill"
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return RosterFormat.date(RosterCalendar.dateString(from: date))
    }

    private func maintainSelection() {
        if let selectedStaffID,
           filteredRows.contains(where: { $0.id == selectedStaffID }) {
            return
        }
        selectedStaffID = filteredRows.first?.id
    }
}
#endif
