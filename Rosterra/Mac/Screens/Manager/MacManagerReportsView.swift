#if targetEnvironment(macCatalyst)
import SwiftUI
import Charts

struct MacManagerReportsView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var weekOffset = 0

    private struct StaffRow: Identifiable {
        let id: String
        let name: String
        let scheduled: Double
        let worked: Double
        let cost: Double
    }

    private struct DailyHours: Identifiable {
        var id: String { dateKey }
        let dateKey: String
        let label: String
        let scheduled: Double
        let worked: Double
    }

    private var now: Date { Date() }
    private var bounds: (min: Int, max: Int) {
        BusinessRules.shiftWeekOffsetBounds(at: now)
    }
    private var monday: Date {
        RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(now))
    }
    private var weekDays: [Date] {
        RosterCalendar.weekDays(for: monday)
    }
    private var weekKeys: [String] {
        weekDays.map { RosterCalendar.dateString(from: $0) }
    }

    private var dateRangeString: String {
        RosterFormat.weekRange(monday: monday)
    }

    private var weekRelativeLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        case let value where value > 1: return "In \(value) weeks"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    private var weekShifts: [Shift] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.shifts.filter { $0.date >= first && $0.date <= last }
    }

    private var weekShiftIDs: Set<String> {
        Set(weekShifts.map(\.id))
    }

    private var weekTimesheets: [Timesheet] {
        repo.timesheets.filter { weekShiftIDs.contains($0.shiftId) }
    }

    private var scheduledHours: Double {
        weekShifts.reduce(0) { $0 + $1.scheduledHours }
    }

    private var workedHours: Double {
        weekTimesheets
            .filter { $0.status == .approved }
            .reduce(0) { $0 + $1.workedHours }
    }

    private var grossCost: Double {
        weekShifts.reduce(0) {
            $0 + $1.scheduledHours * rate($1.staffId, shiftDate: $1.date)
        }
    }

    private var totalCost: Double {
        weekShifts.reduce(0) {
            $0
                + $1.scheduledHours
                * rate($1.staffId, shiftDate: $1.date)
                * superMultiplier($1.staffId)
        }
    }

    private var superCost: Double {
        max(0, totalCost - grossCost)
    }

    private var staffCount: Int {
        Set(weekShifts.map(\.staffId)).count
    }

    private var approvedCount: Int {
        weekTimesheets.filter { $0.status == .approved }.count
    }

    private var pendingCount: Int {
        weekTimesheets.filter { $0.status == .pending }.count
    }

    private var rejectedCount: Int {
        weekTimesheets.filter { $0.status == .rejected }.count
    }

    private var unsubmittedCount: Int {
        max(0, weekShifts.count - Set(weekTimesheets.map(\.shiftId)).count)
    }

    private var hoursVariance: Double {
        workedHours - scheduledHours
    }

    private var approvalProgress: Double {
        guard !weekTimesheets.isEmpty else { return 0 }
        return Double(approvedCount) / Double(weekTimesheets.count)
    }

    private var dailyHours: [DailyHours] {
        weekDays.map { day in
            let key = RosterCalendar.dateString(from: day)
            let shifts = weekShifts.filter { $0.date == key }
            let shiftIDs = Set(shifts.map(\.id))
            let worked = weekTimesheets
                .filter { shiftIDs.contains($0.shiftId) && $0.status == .approved }
                .reduce(0) { $0 + $1.workedHours }

            return DailyHours(
                dateKey: key,
                label: weekdayLabel(day),
                scheduled: shifts.reduce(0) { $0 + $1.scheduledHours },
                worked: worked
            )
        }
    }

    private var perStaff: [StaffRow] {
        let groups = Dictionary(grouping: weekShifts, by: \.staffId)
        return groups.map { staffID, shifts in
            let shiftIDs = Set(shifts.map(\.id))
            let scheduled = shifts.reduce(0) { $0 + $1.scheduledHours }
            let worked = weekTimesheets
                .filter { shiftIDs.contains($0.shiftId) && $0.status == .approved }
                .reduce(0) { $0 + $1.workedHours }
            let cost = shifts.reduce(0.0) {
                $0 + $1.scheduledHours * rate(staffID, shiftDate: $1.date)
            }

            return StaffRow(
                id: staffID,
                name: repo.user(id: staffID)?.fullName ?? "Staff",
                scheduled: scheduled,
                worked: worked,
                cost: cost
            )
        }
        .sorted {
            if $0.scheduled == $1.scheduled {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.scheduled > $1.scheduled
        }
    }

    var body: some View {
        MacScreen(
            title: "Reports & Analytics",
            subtitle: "Weekly hours, labour costs and timesheet progress",
            actions: {
                MacAsyncButton(variant: .bordered, size: .small) {
                    await repo.refreshFromServer()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        ) {
            VStack(spacing: 0) {
                controlBar

                ScrollView {
                    VStack(alignment: .leading, spacing: MacSpace.lg) {
                        summaryStrip

                        HStack(alignment: .top, spacing: MacSpace.lg) {
                            hoursChartCard
                                .frame(maxWidth: .infinity)
                            timesheetStatusCard
                                .frame(width: 310)
                        }

                        staffBreakdown
                    }
                    .padding(.horizontal, MacSpace.xl)
                    .padding(.bottom, MacSpace.xl)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: MacSpace.sm) {
            Button {
                if weekOffset > bounds.min {
                    weekOffset -= 1
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .macButton(.bordered, size: .small)
            .disabled(weekOffset <= bounds.min)
            .accessibilityLabel("Previous week")

            Button {
                weekOffset = 0
            } label: {
                HStack(spacing: 6) {
                    Text(weekRelativeLabel)
                    if weekOffset != 0 {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .padding(.horizontal, MacSpace.md)
                .frame(minHeight: 36)
                .macGlassSurface(cornerRadius: MacRadius.pill)
            }
            .buttonStyle(.plain)
            .disabled(weekOffset == 0)
            .help(weekOffset == 0 ? "Current week" : "Return to current week")

            Button {
                if weekOffset < bounds.max {
                    weekOffset += 1
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .macButton(.bordered, size: .small)
            .disabled(weekOffset >= bounds.max)
            .accessibilityLabel("Next week")

            Text(dateRangeString)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .padding(.leading, MacSpace.sm)

            Spacer()

            Label("\(weekShifts.count) shifts", systemImage: "calendar.badge.clock")
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textSecondary)
            Label("\(staffCount) staff", systemImage: "person.2")
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textSecondary)
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.md)
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryMetric(
                title: "Scheduled",
                value: RosterFormat.hours(scheduledHours),
                detail: "\(weekShifts.count) shifts",
                icon: "calendar",
                tint: MacColor.textPrimary
            )
            summaryDivider
            summaryMetric(
                title: "Approved",
                value: RosterFormat.hours(workedHours),
                detail: varianceText,
                icon: "clock.fill",
                tint: MacColor.success
            )
            summaryDivider
            summaryMetric(
                title: "Gross wages",
                value: currency(grossCost),
                detail: "Before super",
                icon: "banknote",
                tint: MacColor.info
            )
            summaryDivider
            summaryMetric(
                title: "Total labour",
                value: currency(totalCost),
                detail: "\(currency(superCost)) super",
                icon: "dollarsign.circle.fill",
                tint: MacColor.warning
            )
        }
        .padding(.vertical, MacSpace.md)
        .background(
            MacColor.cardBackground,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var hoursChartCard: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hours by day")
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("Scheduled compared with approved time")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                }

                Spacer()

                chartLegend("Scheduled", color: MacColor.textTertiary)
                chartLegend("Approved", color: MacColor.success)
            }

            if weekShifts.isEmpty {
                MacEmptyState(
                    title: "No roster data",
                    subtitle: "There are no shifts in this week.",
                    icon: "chart.bar"
                )
                .frame(maxWidth: .infinity, minHeight: 230)
            } else {
                Chart {
                    ForEach(dailyHours) { day in
                        BarMark(
                            x: .value("Day", day.label),
                            y: .value("Hours", day.scheduled)
                        )
                        .foregroundStyle(by: .value("Series", "Scheduled"))
                        .position(by: .value("Series", "Scheduled"))

                        BarMark(
                            x: .value("Day", day.label),
                            y: .value("Hours", day.worked)
                        )
                        .foregroundStyle(by: .value("Series", "Approved"))
                        .position(by: .value("Series", "Approved"))
                    }
                }
                .chartForegroundStyleScale([
                    "Scheduled": MacColor.textTertiary.opacity(0.55),
                    "Approved": MacColor.success
                ])
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                            .foregroundStyle(MacColor.separator.opacity(0.7))
                        AxisValueLabel()
                            .foregroundStyle(MacColor.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel()
                            .foregroundStyle(MacColor.textSecondary)
                    }
                }
                .frame(height: 250)
            }
        }
        .padding(MacSpace.lg)
        .background(
            MacColor.cardBackground,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var timesheetStatusCard: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Timesheet status")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Text("\(weekTimesheets.count) submitted this week")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Approval progress")
                        .font(MacType.captionStrong)
                        .foregroundStyle(MacColor.textSecondary)
                    Spacer()
                    Text("\(Int((approvalProgress * 100).rounded()))%")
                        .font(MacType.monoStrong)
                        .foregroundStyle(MacColor.textPrimary)
                }
                ProgressView(value: approvalProgress)
                    .tint(MacColor.success)
            }

            statusRow(
                label: "Approved",
                count: approvedCount,
                icon: "checkmark.circle.fill",
                tint: MacColor.success
            )
            statusRow(
                label: "Pending",
                count: pendingCount,
                icon: "hourglass",
                tint: MacColor.warning
            )
            statusRow(
                label: "Rejected",
                count: rejectedCount,
                icon: "xmark.circle.fill",
                tint: MacColor.error
            )
            statusRow(
                label: "Not submitted",
                count: unsubmittedCount,
                icon: "clock.badge.questionmark",
                tint: MacColor.textTertiary
            )

            Spacer(minLength: 0)
        }
        .padding(MacSpace.lg)
        .frame(minHeight: 336, alignment: .top)
        .background(
            MacColor.cardBackground,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var staffBreakdown: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Staff breakdown")
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("Scheduled and approved hours with rostered gross cost")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                }
                Spacer()
                Text("\(perStaff.count) staff")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textSecondary)
            }
            .padding(MacSpace.lg)

            if perStaff.isEmpty {
                MacEmptyState(
                    title: "No staff rostered",
                    subtitle: "This week has no staff hours to report.",
                    icon: "person.2.slash"
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                staffTableHeader

                LazyVStack(spacing: 0) {
                    ForEach(perStaff) { row in
                        staffTableRow(row)
                    }
                }
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

    private var staffTableHeader: some View {
        HStack(spacing: MacSpace.md) {
            Text("STAFF")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SCHEDULED")
                .frame(width: 110, alignment: .trailing)
            Text("APPROVED")
                .frame(width: 110, alignment: .trailing)
            Text("VARIANCE")
                .frame(width: 100, alignment: .trailing)
            Text("GROSS COST")
                .frame(width: 120, alignment: .trailing)
        }
        .font(MacType.badge)
        .foregroundStyle(MacColor.textTertiary)
        .padding(.horizontal, MacSpace.lg)
        .frame(height: 42)
        .background(MacColor.tableHeaderBackground)
    }

    private func staffTableRow(_ row: StaffRow) -> some View {
        let variance = row.worked - row.scheduled
        return HStack(spacing: MacSpace.md) {
            HStack(spacing: MacSpace.md) {
                MacAvatar(name: row.name, size: 34)
                Text(row.name)
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(RosterFormat.hours(row.scheduled))
                .frame(width: 110, alignment: .trailing)
            Text(RosterFormat.hours(row.worked))
                .foregroundStyle(row.worked > 0 ? MacColor.success : MacColor.textTertiary)
                .frame(width: 110, alignment: .trailing)
            Text(signedHours(variance))
                .foregroundStyle(varianceColor(variance))
                .frame(width: 100, alignment: .trailing)
            Text(currency(row.cost))
                .foregroundStyle(MacColor.textPrimary)
                .frame(width: 120, alignment: .trailing)
        }
        .font(MacType.monoStrong)
        .padding(.horizontal, MacSpace.lg)
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MacColor.separator.opacity(0.7))
                .frame(height: 1)
        }
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(MacColor.separator)
            .frame(width: 1, height: 54)
    }

    private func summaryMetric(
        title: String,
        value: String,
        detail: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.textTertiary)
                Text(value)
                    .font(MacType.monoLarge)
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
        }
    }

    private func statusRow(
        label: String,
        count: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: MacSpace.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(label)
                .font(MacType.body)
                .foregroundStyle(MacColor.textPrimary)
            Spacer()
            Text("\(count)")
                .font(MacType.monoStrong)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.10), in: Capsule())
        }
    }

    private var varianceText: String {
        "\(signedHours(hoursVariance)) vs scheduled"
    }

    private func signedHours(_ value: Double) -> String {
        guard abs(value) >= 0.01 else { return "0h" }
        let prefix = value > 0 ? "+" : "−"
        return "\(prefix)\(RosterFormat.hours(abs(value)))"
    }

    private func varianceColor(_ value: Double) -> Color {
        if abs(value) < 0.01 { return MacColor.textTertiary }
        return value > 0 ? MacColor.warning : MacColor.error
    }

    private func rate(_ staffID: String, shiftDate: String) -> Double {
        repo.liveHourlyRate(forStaffId: staffID, shiftDateKey: shiftDate)
    }

    private func superMultiplier(_ staffID: String) -> Double {
        let percent = repo.user(id: staffID)?.superRate
            ?? BusinessRules.defaultSuperRatePercent
        return 1 + percent / 100
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = RosterCalendar.calendar
        formatter.timeZone = RosterCalendar.timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func currency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_AU")
        formatter.currencyCode = "AUD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
#endif
