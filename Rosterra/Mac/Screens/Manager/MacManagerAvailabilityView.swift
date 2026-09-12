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
        user.weeklyAvailability[weekKey] ?? user.availability ?? .defaultAvailability
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
                VStack(spacing: 0) {
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
                            .padding(.horizontal, MacSpace.xl)
                            .padding(.bottom, MacSpace.lg)

                        matrix(width: proxy.size.width)
                    }
                }
            }
            .onChange(of: repo.allUsers) { _, _ in }
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
            ZStack {
                searchField

                HStack(spacing: MacSpace.md) {
                    weekNav
                    dateRangeLabel
                    Spacer(minLength: MacSpace.md)
                    lockButton
                }
            }
            .frame(minWidth: 700, maxWidth: .infinity)

            VStack(spacing: MacSpace.md) {
                HStack(spacing: MacSpace.md) {
                    weekNav
                    dateRangeLabel
                    Spacer(minLength: 0)
                }
                HStack(spacing: MacSpace.md) {
                    searchField
                    Spacer(minLength: 0)
                    lockButton
                }
            }
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
    }

    private var dateRangeLabel: some View {
        Text(dateRangeString)
            .font(MacType.bodyStrong)
            .foregroundStyle(MacColor.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var searchField: some View {
        HStack(spacing: MacSpace.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MacColor.textTertiary)
            TextField("Search staff or department", text: $searchText)
                .textFieldStyle(.plain)
                .frame(minWidth: 150, idealWidth: 220, maxWidth: 220)
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
        let outerMargin: CGFloat = MacSpace.xl
        let innerPadding: CGFloat = MacSpace.md
        let cardWidth = max(0, width - outerMargin * 2)
        let nameCol = min(220, max(140, floor(width * 0.2)))
        let spacing: CGFloat = width < 800 ? 4 : 8
        let usable = max(0, cardWidth - innerPadding * 2 - nameCol - spacing * 7)
        let cellW = max(40, floor(usable / 7))

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: spacing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TEAM")
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.textTertiary)
                        Text("\(staff.count) staff shown")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                    }
                    .frame(width: nameCol, alignment: .leading)

                    ForEach(Array(weekDays.enumerated()), id: \.offset) { index, date in
                        let day = Weekday.allCases[index]
                        VStack(spacing: 3) {
                            Text(day.shortLabel)
                                .font(MacType.captionStrong)
                                .foregroundStyle(MacColor.textPrimary)
                            Text(RosterCalendar.dayOfMonth(from: date))
                                .font(MacType.caption)
                                .foregroundStyle(MacColor.textTertiary)
                            Text(
                                cellW < 86
                                    ? "\(availableCount(day))/\(staff.count)"
                                    : "\(availableCount(day))/\(staff.count) available"
                            )
                                .font(MacType.badge)
                                .foregroundStyle(coverageTint(for: day))
                                .minimumScaleFactor(0.65)
                        }
                        .frame(width: cellW)
                    }
                }
                .padding(.horizontal, innerPadding)
                .padding(.vertical, MacSpace.md)
                .background(MacColor.tableHeaderBackground)
                .overlay(Rectangle().fill(MacColor.separator).frame(height: 1), alignment: .bottom)

                ForEach(staff) { user in
                    let avail = availability(for: user)
                    HStack(spacing: spacing) {
                        HStack(spacing: MacSpace.sm) {
                            MacAvatar(name: user.fullName, size: 34)

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
                            dayCell(avail[day])
                                .frame(width: cellW)
                        }
                    }
                    .padding(.horizontal, innerPadding)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().fill(MacColor.separator.opacity(0.55)).frame(height: 1), alignment: .bottom)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
            .background(MacColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, outerMargin)
            .padding(.bottom, MacSpace.xl)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayCell(_ day: DayAvailability) -> some View {
        let (label, tint): (String, Color) = {
            if !day.available { return ("Off", MacColor.error) }
            if day.allDay { return ("All day", MacColor.success) }
            let s = day.start ?? "—"
            let e = day.end ?? "—"
            return ("\(s)–\(e)", MacColor.warning)
        }()

        return Text(label)
            .font(MacType.badge)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    // MARK: - Coverage summary

    private var coverageSummary: some View {
        HStack(spacing: 0) {
            coverageMetric(
                icon: "person.2",
                title: "Team shown",
                value: "\(staff.count)",
                detail: searchText.isEmpty ? "active staff" : "matching staff",
                tint: MacColor.info
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
                    tint: MacColor.success
                )
            }
            if let lowestCover {
                coverageMetric(
                    icon: "exclamationmark.triangle",
                    title: "Lowest cover",
                    value: lowestCover.day.shortLabel,
                    detail: "\(lowestCover.count) available",
                    tint: lowestCover.count == 0 ? MacColor.error : MacColor.warning
                )
            }
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                Text(value)
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacSpace.lg)
        .frame(maxWidth: .infinity, minHeight: 88)
        .overlay {
            Rectangle()
                .strokeBorder(MacColor.separator.opacity(0.5), lineWidth: 0.5)
        }
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
