#if targetEnvironment(macCatalyst)
import SwiftUI
import Charts

// MARK: - Mac Manager Dashboard View

struct MacManagerDashboardView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacNavigationModel.self) private var nav

    @State private var contentWidth: CGFloat = 1000

    init() {}

    private var todayKey: String { RosterCalendar.todayKey() }

    private var firstName: String {
        repo.currentUser?.firstName ?? "there"
    }

    private var greeting: String {
        let hour = RosterCalendar.calendar.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var weekDays: [Date] {
        RosterCalendar.weekDays(for: RosterCalendar.weekStart())
    }

    private var weekKeys: [String] {
        weekDays.map { RosterCalendar.dateString(from: $0) }
    }

    private var todayShifts: [Shift] {
        repo.shifts
            .filter { $0.date == todayKey && $0.status == .published }
            .sorted { $0.rosteredStart < $1.rosteredStart }
    }

    private var pendingTimesheets: [Shift] {
        repo.shifts.filter { shift in
            guard let status = repo.timesheet(forShift: shift.id)?.status else { return false }
            return status == .pending || status == .absentReported
        }
        .sorted { $0.date < $1.date }
    }

    private var weekRosteredHours: Double {
        guard let first = weekKeys.first, let last = weekKeys.last else { return 0 }
        return repo.shifts
            .filter { $0.status == .published && $0.date >= first && $0.date <= last }
            .reduce(0) { $0 + $1.scheduledHours }
    }

    private var weekApprovedHours: Double {
        guard let first = weekKeys.first, let last = weekKeys.last else { return 0 }
        return repo.timesheets.reduce(0) { sum, ts in
            guard ts.status == .approved, let date = repo.shiftsById[ts.shiftId]?.date else { return sum }
            guard date >= first && date <= last else { return sum }
            return sum + ts.workedHours
        }
    }

    private var missingSubmissions: Int {
        let actioned: Set<TimesheetStatus> = [.pending, .approved, .absentReported, .absent]
        return repo.shifts.filter { shift in
            guard shift.status == .published, shift.isSubmittable() else { return false }
            if let status = repo.timesheet(forShift: shift.id)?.status, actioned.contains(status) {
                return false
            }
            guard let user = repo.user(id: shift.staffId), user.role == .staff, user.status == .active else {
                return false
            }
            return true
        }.count
    }

    private var weekHours: [MacDashboardDayHours] {
        weekDays.map { day in
            let key = RosterCalendar.dateString(from: day)
            let rostered = repo.shifts
                .filter { $0.status == .published && $0.date == key }
                .reduce(0.0) { $0 + $1.scheduledHours }
            let approved = repo.timesheets.reduce(0.0) { sum, ts in
                guard ts.status == .approved, repo.shiftsById[ts.shiftId]?.date == key else { return sum }
                return sum + ts.workedHours
            }
            return MacDashboardDayHours(
                label: RosterCalendar.dayOfWeek(from: day),
                rostered: rostered,
                approved: approved
            )
        }
    }

    var body: some View {
        MacScreen(
            title: "Dashboard",
            subtitle: RosterCalendar.todayFormattedLong()
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: MacSpace.lg) {
                    VStack(alignment: .leading, spacing: MacSpace.xs) {
                        Text("\(greeting), \(firstName)")
                            .font(MacType.pageTitle)
                            .foregroundStyle(MacColor.textPrimary)
                        Text("Here is what needs your attention today.")
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }
                    summaryStrip
                    rosterAndApprovals
                    weeklyHoursCard
                }
                .padding(MacSpace.xl)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity)
            }
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { contentWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in contentWidth = width }
            })
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryMetric(
                title: "On shift today",
                value: "\(todayShifts.count)",
                detail: "team members",
                icon: "person.2.fill",
                tint: MacColor.accent
            )
            summaryMetric(
                title: "Rostered",
                value: RosterFormat.hours(weekRosteredHours),
                detail: "this week",
                icon: "clock.fill",
                tint: MacColor.info
            )
            summaryMetric(
                title: "Approved",
                value: RosterFormat.hours(weekApprovedHours),
                detail: "this week",
                icon: "checkmark.circle.fill",
                tint: MacColor.success
            )
            summaryMetric(
                title: "Needs attention",
                value: "\(pendingTimesheets.count + missingSubmissions)",
                detail: "\(pendingTimesheets.count) pending · \(missingSubmissions) missing",
                icon: "exclamationmark.circle.fill",
                tint: pendingTimesheets.isEmpty && missingSubmissions == 0 ? MacColor.success : MacColor.warning,
                action: { nav.select(.managerTimesheets) }
            )
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
    }

    private var weeklyHoursCard: some View {
        MacCard(padding: 0) {
            VStack(alignment: .leading, spacing: MacSpace.md) {
                HStack {
                    Text("Hours this week")
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Spacer()
                    HStack(spacing: MacSpace.md) {
                        legendDot(MacColor.accent, "Rostered")
                        legendDot(MacColor.success, "Approved")
                    }
                }
                .padding(.horizontal, MacSpace.lg)
                .padding(.top, MacSpace.lg)

                Chart(weekHours) { item in
                    BarMark(
                        x: .value("Day", item.label),
                        y: .value("Rostered", item.rostered)
                    )
                    .foregroundStyle(MacColor.accent.opacity(0.28))
                    .cornerRadius(5)

                    LineMark(
                        x: .value("Day", item.label),
                        y: .value("Approved", item.approved)
                    )
                    .foregroundStyle(MacColor.success)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Day", item.label),
                        y: .value("Approved", item.approved)
                    )
                    .foregroundStyle(MacColor.success)
                    .symbolSize(36)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(MacColor.separator.opacity(0.7))
                        AxisValueLabel()
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textTertiary)
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 168)
                .padding(.horizontal, MacSpace.lg)
                .padding(.bottom, MacSpace.lg)
            }
        }
    }

    private var rosterAndApprovals: some View {
        dashboardLayout {
            todayRosterCard
                .frame(maxWidth: .infinity)
            pendingCard
                .frame(maxWidth: contentWidth >= 1100 ? 340 : .infinity)
        }
    }

    private var dashboardLayout: AnyLayout {
        contentWidth >= 1100
            ? AnyLayout(HStackLayout(alignment: .top, spacing: MacSpace.lg))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: MacSpace.lg))
    }

    private var todayRosterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's roster")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Spacer()
                Button("View all →") {
                    nav.select(.managerRoster)
                }
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MacSpace.lg)
            .padding(.vertical, MacSpace.md)
            .overlay(Rectangle().fill(MacColor.separator).frame(height: 1), alignment: .bottom)

            if todayShifts.isEmpty {
                Text("No shifts rostered for today")
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                HStack {
                    tableHeader("Staff", alignment: .leading)
                    tableHeader("Shift", alignment: .leading)
                    tableHeader("Hours", alignment: .trailing)
                    tableHeader("Status", alignment: .trailing)
                }
                .padding(.horizontal, MacSpace.lg)
                .padding(.vertical, 8)
                .background(MacColor.tableHeaderBackground)

                ForEach(todayShifts) { shift in
                    let staff = repo.user(id: shift.staffId)
                    HStack(spacing: MacSpace.md) {
                        HStack(spacing: MacSpace.sm) {
                            MacAvatar(name: staff?.fullName ?? "?", size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(staff?.fullName ?? "Staff member")
                                    .font(MacType.bodyStrong)
                                    .foregroundStyle(MacColor.textPrimary)
                                    .lineLimit(1)
                                if let role = shift.department, !role.isEmpty {
                                    Text(role)
                                        .font(MacType.caption)
                                        .foregroundStyle(MacColor.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))")
                            .font(MacType.mono)
                            .foregroundStyle(MacColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(RosterFormat.hours(shift.scheduledHours))
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)
                            .frame(width: 72, alignment: .trailing)

                        MacStatusPill(
                            shiftStatus: shift.staffDisplayStatus(
                                timesheet: repo.timesheet(forShift: shift.id)
                            )
                        )
                            .frame(width: 140, alignment: .trailing)
                    }
                    .padding(.horizontal, MacSpace.lg)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().fill(MacColor.separator.opacity(0.6)).frame(height: 1), alignment: .bottom)
                }
            }
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pending approvals")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                if pendingTimesheets.count > 0 {
                    Text("\(pendingTimesheets.count)")
                        .font(MacType.badge)
                        .foregroundStyle(MacColor.warning)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(MacColor.warning.opacity(0.14), in: Capsule())
                }
                Spacer()
                Button("Review all") {
                    nav.select(.managerTimesheets)
                }
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MacSpace.lg)
            .padding(.vertical, MacSpace.md)
            .overlay(Rectangle().fill(MacColor.separator).frame(height: 1), alignment: .bottom)

            if pendingTimesheets.isEmpty {
                VStack(spacing: MacSpace.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(MacColor.success)
                    Text("Queue clear")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("All submitted timesheets have been reviewed.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .padding(.horizontal, MacSpace.lg)
            } else {
                ForEach(pendingTimesheets.prefix(4)) { shift in
                    let staff = repo.user(id: shift.staffId)
                    Button {
                        nav.select(.managerTimesheets)
                    } label: {
                        HStack(spacing: MacSpace.md) {
                            MacAvatar(name: staff?.fullName ?? "?", size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(staff?.fullName ?? "Staff member")
                                    .font(MacType.bodyStrong)
                                    .foregroundStyle(MacColor.textPrimary)
                                    .lineLimit(1)
                                Text("\(RosterFormat.dateShort(shift.date))  ·  \(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))")
                                    .font(MacType.caption)
                                    .foregroundStyle(MacColor.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MacColor.textTertiary)
                        }
                        .padding(.horizontal, MacSpace.lg)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(Rectangle().fill(MacColor.separator.opacity(0.6)).frame(height: 1), alignment: .bottom)
                }
            }
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
    }

    private func tableHeader(_ title: String, alignment: Alignment) -> some View {
        Text(title.uppercased())
            .font(MacType.captionStrong)
            .foregroundStyle(MacColor.textTertiary)
            .tracking(0.4)
            .frame(maxWidth: alignment == .leading ? .infinity : nil, alignment: alignment)
            .frame(width: alignment == .trailing && title == "Hours" ? 72 : (alignment == .trailing ? 140 : nil), alignment: alignment)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
        }
    }

    private func summaryMetric(
        title: String,
        value: String,
        detail: String,
        icon: String,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        MacDashboardSummaryMetric(
            title: title,
            value: value,
            detail: detail,
            icon: icon,
            tint: tint,
            action: action
        )
    }
}

private struct MacDashboardSummaryMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textTertiary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacSpace.lg)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .overlay {
            Rectangle()
                .strokeBorder(MacColor.separator.opacity(0.55), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }
}

private struct MacDashboardDayHours: Identifiable {
    var id: String { label }
    let label: String
    let rostered: Double
    let approved: Double
}
#endif
