#if targetEnvironment(macCatalyst)
import SwiftUI

/// Mac manager availability matrix — matches the prior Mac layout and
/// `ManagerAvailabilityView` data rules (week overrides → template → default).
struct MacManagerAvailabilityView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var weekOffset = 0
    @State private var searchText = ""
    @State private var isLocking = false
    @State private var staffPage = 0

    private let staffPageSize = 12

    init() {}

    private var bounds: (min: Int, max: Int) {
        (BusinessRules.availabilityMinWeekOffset, BusinessRules.availabilityMaxWeekOffset)
    }

    private var monday: Date {
        RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(Date()))
    }

    private var weekDays: [Date] { RosterCalendar.weekDays(for: monday) }
    private var weekKey: String { RosterCalendar.weekStartKey(monday) }

    private var isWeekAvailabilityLocked: Bool {
        repo.lockedAvailabilityWeeks.contains(weekKey)
    }

    private var dateRangeString: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return RosterCalendar.formatDateRange(start: first, end: last)
    }

    private var weekRelativeLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        case let n where n > 1: return "In \(n) weeks"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    private var allActiveStaff: [AppUser] {
        repo.staffMembers
            .filter { $0.status == .active }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private var staff: [AppUser] {
        guard !searchText.isEmpty else { return allActiveStaff }
        return allActiveStaff.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
                || ($0.defaultDepartment?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func availability(for user: AppUser) -> UserAvailability {
        user.resolvedAvailability(forWeekKey: weekKey)
    }

    private func availableCount(_ day: Weekday) -> Int {
        staff.filter { availability(for: $0)[day].available }.count
    }

    private var bestCover: (day: Weekday, count: Int)? {
        guard let day = Weekday.allCases.max(by: { availableCount($0) < availableCount($1) }) else { return nil }
        return (day, availableCount(day))
    }

    private var lowestCover: (day: Weekday, count: Int)? {
        guard let day = Weekday.allCases.min(by: { availableCount($0) < availableCount($1) }) else { return nil }
        return (day, availableCount(day))
    }

    private var averageDailyCover: Double {
        guard !staff.isEmpty else { return 0 }
        let total = Weekday.allCases.reduce(0) { $0 + availableCount($1) }
        return Double(total) / Double(Weekday.allCases.count)
    }

    var body: some View {
        MacScreen(
            title: "Team Availability",
            subtitle: dateRangeString
        ) {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: MacSpace.md) {
                    controlBar

                    if allActiveStaff.isEmpty {
                        MacEmptyState(
                            title: "No staff to show",
                            subtitle: "Add active staff accounts to view weekly availability.",
                            icon: "calendar.badge.exclamationmark"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if staff.isEmpty {
                        MacEmptyState(
                            title: "No matching staff",
                            subtitle: "Try a different name or department.",
                            icon: "person.crop.circle.badge.questionmark"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        coverageSummary
                        matrix(width: max(0, proxy.size.width - MacSpace.xl * 2))
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(MacSpace.xl)
            }
            .onChange(of: repo.allUsers) { _, _ in }
            .onChange(of: searchText) { _, _ in staffPage = 0 }
            .onChange(of: weekOffset) { _, _ in staffPage = 0 }
        }
    }

    // MARK: - Lock

    private var lockButton: some View {
        Button {
            guard !isLocking else { return }
            isLocking = true
            Task {
                await toggleWeekLock()
                isLocking = false
            }
        } label: {
            HStack(spacing: 6) {
                if isLocking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isWeekAvailabilityLocked ? "lock.fill" : "lock.open")
                }
                Text(isWeekAvailabilityLocked ? "Availability locked" : "Lock availability")
            }
        }
        .availabilityGlassPill()
        .disabled(isLocking)
        .help(isWeekAvailabilityLocked
              ? "Staff availability is locked for this week — click to unlock"
              : "Lock staff availability for this week")
        .accessibilityLabel(isWeekAvailabilityLocked
                            ? "Unlock staff availability"
                            : "Lock staff availability")
    }

    private func toggleWeekLock() async {
        let locking = !isWeekAvailabilityLocked
        do {
            try await repo.setAvailabilityWeekLock(weekKey: weekKey, locked: locking)
            toasts.show(
                locking ? "Staff availability locked for this week" : "Staff availability unlocked",
                style: .success
            )
        } catch {
            toasts.show("Lock update failed. \(error.localizedDescription)", style: .error)
        }
    }

    // MARK: - Week nav

    private var controlBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MacSpace.lg) {
                availabilityTitle
                Divider().frame(height: 34)
                weekNav
                Spacer(minLength: MacSpace.md)
                searchField
                lockButton
            }

            VStack(spacing: MacSpace.sm) {
                HStack(spacing: MacSpace.md) {
                    availabilityTitle
                    Spacer()
                    lockButton
                }
                HStack(spacing: MacSpace.md) {
                    weekNav
                    Spacer()
                    searchField
                }
            }
        }
        .padding(MacSpace.md)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var availabilityTitle: some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MacColor.accent)
                .frame(width: 36, height: 36)
                .background(MacColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly availability")
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
                Text("\(weekRelativeLabel) · \(dateRangeString)")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var searchField: some View {
        HStack(spacing: MacSpace.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MacColor.textTertiary)
            TextField("Search staff or department", text: $searchText)
                .textFieldStyle(.plain)
                .frame(minWidth: 180, idealWidth: 270, maxWidth: 300)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MacColor.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MacSpace.md)
        .padding(.vertical, 7)
        .macGlassSurface(cornerRadius: MacRadius.pill)
    }

    private var weekNav: some View {
        HStack(spacing: MacSpace.sm) {
            navArrow("chevron.left", enabled: weekOffset > bounds.min) {
                if weekOffset > bounds.min { weekOffset -= 1 }
            }

            Button {
                weekOffset = 0
            } label: {
                HStack(spacing: 5) {
                    Text(weekRelativeLabel)
                    if weekOffset != 0 {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
                .frame(minWidth: 88)
            }
            .availabilityGlassPill()
            .disabled(weekOffset == 0)
            .help(weekOffset == 0 ? "This week" : "Jump to this week")

            navArrow("chevron.right", enabled: weekOffset < bounds.max) {
                if weekOffset < bounds.max { weekOffset += 1 }
            }
        }
    }

    private func navArrow(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .frame(width: 18, height: 18)
        }
        .availabilityGlassPill()
        .disabled(!enabled)
        .accessibilityLabel(system == "chevron.left" ? "Previous week" : "Next week")
    }

    // MARK: - Matrix

    private func matrix(width: CGFloat) -> some View {
        let innerPadding: CGFloat = MacSpace.lg
        let nameCol = min(250, max(170, floor(width * 0.19)))
        let spacing: CGFloat = width < 900 ? 5 : 8
        let usable = max(0, width - innerPadding * 2 - nameCol - spacing * 7)
        let cellW = max(44, floor(usable / 7))

        return GeometryReader { geometry in
            let matrixChromeHeight: CGFloat = 113
            let availableRowsHeight = max(0, geometry.size.height - matrixChromeHeight)
            let rowsPerPage = max(1, min(staffPageSize, Int(availableRowsHeight / 32)))
            let pageCount = max(1, Int(ceil(Double(staff.count) / Double(rowsPerPage))))
            let page = min(staffPage, pageCount - 1)
            let pageStart = page * rowsPerPage
            let pageEnd = min(pageStart + rowsPerPage, staff.count)
            let rows = pageStart < staff.count ? Array(staff[pageStart..<pageEnd]) : []
            let rowHeight = min(54, max(32, availableRowsHeight / CGFloat(max(1, rows.count))))
            let cellHeight = max(25, rowHeight - 10)
            let avatarSize = min(34, max(24, rowHeight - 9))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: MacSpace.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Team availability matrix")
                            .font(MacType.sectionHeader)
                            .foregroundStyle(MacColor.textPrimary)
                        Text("\(staff.count) active staff · \(weekRelativeLabel.lowercased())")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    Spacer()

                    if pageCount > 1 {
                        HStack(spacing: MacSpace.sm) {
                            Button {
                                staffPage = max(0, page - 1)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.plain)
                            .disabled(page == 0)

                            Text("Page \(page + 1) of \(pageCount)")
                                .font(MacType.captionStrong)
                                .foregroundStyle(MacColor.textSecondary)

                            Button {
                                staffPage = min(pageCount - 1, page + 1)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.plain)
                            .disabled(page >= pageCount - 1)
                        }
                        .padding(.horizontal, MacSpace.md)
                        .padding(.vertical, 6)
                        .background(MacColor.cardBackgroundSecondary, in: Capsule())
                    }

                    HStack(spacing: MacSpace.lg) {
                        availabilityLegend("All day", tint: MacColor.success)
                        availabilityLegend("Set hours", tint: MacColor.accent)
                        availabilityLegend("Off", tint: MacColor.textTertiary)
                    }
                }
                .padding(.horizontal, MacSpace.lg)
                .frame(height: 54)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: spacing) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TEAM MEMBER")
                                .font(MacType.captionStrong)
                                .foregroundStyle(MacColor.textTertiary)
                            Text("Department")
                                .font(MacType.caption)
                                .foregroundStyle(MacColor.textSecondary)
                        }
                        .frame(width: nameCol, alignment: .leading)

                        ForEach(Array(weekDays.enumerated()), id: \.offset) { index, date in
                            let day = Weekday.allCases[index]
                            let count = availableCount(day)
                            VStack(spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(day.shortLabel)
                                        .font(MacType.captionStrong)
                                    Text(RosterCalendar.dayOfMonth(from: date))
                                        .font(MacType.caption)
                                        .foregroundStyle(MacColor.textTertiary)
                                }
                                .foregroundStyle(MacColor.textPrimary)

                                Text("\(count) of \(staff.count) available")
                                    .font(MacType.badge)
                                    .foregroundStyle(coverageTint(for: day))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(MacColor.cardBorder.opacity(0.65))
                                        Capsule()
                                            .fill(coverageTint(for: day))
                                            .frame(width: geometry.size.width * coverageRatio(for: day))
                                    }
                                }
                                .frame(height: 4)
                            }
                            .frame(width: cellW)
                        }
                    }
                    .padding(.horizontal, innerPadding)
                    .frame(height: 58)
                    .background(MacColor.tableHeaderBackground)
                    .overlay(Rectangle().fill(MacColor.separator).frame(height: 1), alignment: .bottom)

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, user in
                        let avail = availability(for: user)
                        HStack(spacing: spacing) {
                            HStack(spacing: MacSpace.sm) {
                                MacAvatar(name: user.fullName, size: avatarSize)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.fullName)
                                        .font(MacType.bodyStrong)
                                        .foregroundStyle(MacColor.textPrimary)
                                        .lineLimit(1)
                                    Text(user.defaultDepartment ?? "Staff")
                                        .font(MacType.caption)
                                        .foregroundStyle(MacColor.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: nameCol, alignment: .leading)

                            ForEach(Weekday.allCases) { day in
                                dayCell(avail[day], height: cellHeight)
                                    .frame(width: cellW)
                            }
                        }
                        .padding(.horizontal, innerPadding)
                        .frame(height: rowHeight)
                        .background(index.isMultiple(of: 2) ? Color.clear : MacColor.tableHeaderBackground.opacity(0.32))
                        .overlay(Rectangle().fill(MacColor.separator.opacity(0.45)).frame(height: 1), alignment: .bottom)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width, alignment: .leading)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.extraLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.extraLarge, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 12, y: 3)
    }

    private func availabilityLegend(_ label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
        }
    }

    private func coverageRatio(for day: Weekday) -> CGFloat {
        guard !staff.isEmpty else { return 0 }
        return CGFloat(availableCount(day)) / CGFloat(staff.count)
    }

    private func dayCell(_ day: DayAvailability, height: CGFloat) -> some View {
        let (label, indicator, textColor): (String, Color, Color) = {
            if !day.available { return ("Off", MacColor.textTertiary, MacColor.textSecondary) }
            if day.allDay { return ("All day", MacColor.success, MacColor.textPrimary) }
            let s = day.start ?? "—"
            let e = day.end ?? "—"
            return ("\(s)–\(e)", MacColor.accent, MacColor.textPrimary)
        }()

        return HStack(spacing: 6) {
            Circle()
                .fill(indicator)
                .frame(width: 6, height: 6)
            Text(label)
                .font(MacType.badge)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .padding(.horizontal, 6)
            .background(MacColor.cardBackgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(MacColor.cardBorder.opacity(0.7), lineWidth: 1)
            }
    }

    // MARK: - Coverage summary

    private var coverageSummary: some View {
        HStack(spacing: MacSpace.md) {
            coverageMetric(
                icon: "person.2",
                title: "Team shown",
                value: "\(staff.count)",
                detail: searchText.isEmpty ? "active staff" : "matching staff",
                tint: MacColor.accent
            )
            coverageMetric(
                icon: "chart.bar",
                title: "Average cover",
                value: String(format: "%.1f", averageDailyCover),
                detail: "staff per day",
                tint: MacColor.accent
            )
            if let bestCover {
                coverageMetric(
                    icon: "arrow.up.right",
                    title: "Best cover",
                    value: bestCover.day.shortLabel,
                    detail: "\(bestCover.count) available",
                    tint: MacColor.accent
                )
            }
            if let lowestCover {
                coverageMetric(
                    icon: "exclamationmark.triangle",
                    title: "Lowest cover",
                    value: lowestCover.day.shortLabel,
                    detail: "\(lowestCover.count) available",
                    tint: MacColor.warning
                )
            }
        }
    }

    private func coverageMetric(
        icon: String,
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(MacColor.textPrimary)
                    Text(title)
                        .font(MacType.captionStrong)
                        .foregroundStyle(MacColor.textSecondary)
                }
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacSpace.md)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.025), radius: 8, y: 2)
    }

    private func coverageTint(for day: Weekday) -> Color {
        let count = availableCount(day)
        if count == 0 { return MacColor.error }
        if count < max(1, staff.count / 2) { return MacColor.warning }
        return MacColor.success
    }
}

private extension View {
    @ViewBuilder
    func availabilityGlassPill() -> some View {
        if #available(iOS 26.0, *) {
            self
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .buttonStyle(.glass)
                .tint(.clear)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            self
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
#endif
