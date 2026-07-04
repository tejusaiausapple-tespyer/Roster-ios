import SwiftUI

// Manager weekly analytics: scheduled vs worked hours, labour cost, timesheet
// status breakdown, and a per-staff summary. Computed from already-loaded
// shifts + timesheets. Week selector consistent with Roster/Timesheets.
struct ManagerReportsView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var weekOffset = 0

    private let superRate = 0.1125
    private let defaultRate = 25.0

    private var now: Date { Date() }
    private var bounds: (min: Int, max: Int) { BusinessRules.shiftWeekOffsetBounds(at: now) }
    private var monday: Date { RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(now)) }
    private var weekKeys: [String] { RosterCalendar.weekDays(for: monday).map { RosterCalendar.dayFormatter.string(from: $0) } }

    private var dateRangeString: String {
        let days = RosterCalendar.weekDays(for: monday)
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter(); f.calendar = RosterCalendar.calendar; f.timeZone = RosterCalendar.timeZone; f.dateFormat = "d MMM"
        return "\(f.string(from: first)) – \(f.string(from: last))"
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

    // MARK: - Data

    private var weekShifts: [Shift] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.shifts.filter { $0.date >= first && $0.date <= last }
    }
    private var weekShiftIds: Set<String> { Set(weekShifts.map { $0.id }) }
    private var weekTimesheets: [Timesheet] { repo.timesheets.filter { weekShiftIds.contains($0.shiftId) } }

    private func rate(_ staffId: String) -> Double {
        repo.allUsers.first(where: { $0.id == staffId })?.hourlyRate ?? defaultRate
    }

    private var scheduledHours: Double { weekShifts.reduce(0) { $0 + $1.scheduledHours } }
    private var workedHours: Double { weekTimesheets.filter { $0.status == .approved }.reduce(0) { $0 + $1.workedHours } }
    private var grossCost: Double { weekShifts.reduce(0) { $0 + $1.scheduledHours * rate($1.staffId) } }
    private var totalCost: Double { grossCost * (1 + superRate) }
    private var staffCount: Int { Set(weekShifts.map { $0.staffId }).count }
    private var pendingCount: Int { weekTimesheets.filter { $0.status == .pending }.count }
    private var approvedCount: Int { weekTimesheets.filter { $0.status == .approved }.count }
    private var rejectedCount: Int { weekTimesheets.filter { $0.status == .rejected }.count }

    private struct StaffRow: Identifiable {
        let id: String
        let name: String
        let scheduled: Double
        let worked: Double
        let cost: Double
    }

    private var perStaff: [StaffRow] {
        let groups = Dictionary(grouping: weekShifts, by: { $0.staffId })
        return groups.map { (staffId, shifts) in
            let name = repo.allUsers.first(where: { $0.id == staffId })?.fullName ?? "Staff"
            let sched = shifts.reduce(0) { $0 + $1.scheduledHours }
            let ids = Set(shifts.map { $0.id })
            let worked = weekTimesheets.filter { ids.contains($0.shiftId) && $0.status == .approved }.reduce(0) { $0 + $1.workedHours }
            return StaffRow(id: staffId, name: name, scheduled: sched, worked: worked, cost: sched * rate(staffId))
        }
        .sorted { $0.scheduled > $1.scheduled }
    }

    var embedInNavigationStack = true

    var body: some View {
        if embedInNavigationStack {
            NavigationStack { rootContent }
        } else {
            rootContent
        }
    }

    private var rootContent: some View {
        GeometryReader { _ in
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    controlBar
                    reportScroll
                    summaryBar
                }
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Reports", icon: "chart.bar.fill")
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            weekNavCluster
            Text(dateRangeString)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var weekNavCluster: some View {
        HStack(spacing: 2) {
            navArrow("chevron.left", enabled: weekOffset > bounds.min) {
                if weekOffset > bounds.min { weekOffset -= 1 }
            }
            Button {
                weekOffset = 0
            } label: {
                HStack(spacing: 6) {
                    Text(weekRelativeLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(weekOffset == 0 ? Theme.textPrimary : Theme.brand)
                    if weekOffset != 0 {
                        Image(systemName: "arrow.uturn.backward").font(.caption2.weight(.bold)).foregroundStyle(Theme.brand)
                    }
                }
                .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(weekOffset == 0)
            navArrow("chevron.right", enabled: weekOffset < bounds.max) {
                if weekOffset < bounds.max { weekOffset += 1 }
            }
        }
        .padding(.horizontal, 4)
        .glassCapsule()
    }

    private func navArrow(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.footnote.weight(.bold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Content

    private var reportScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metricsGrid
                statusCard
                perStaffCard
            }
            .padding(16)
        }
        .refreshable { await repo.refreshFromServer() }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)], spacing: 12) {
            metricCard("Scheduled", String(format: "%.0fh", scheduledHours), "calendar", Theme.brand)
            metricCard("Worked (approved)", String(format: "%.0fh", workedHours), "clock.fill", Theme.accent)
            metricCard("Labour cost", String(format: "$%.0f", totalCost), "dollarsign.circle.fill", Theme.brand)
            metricCard("Shifts", "\(weekShifts.count)", "calendar.badge.clock", Theme.textPrimary)
            metricCard("Staff rostered", "\(staffCount)", "person.2.fill", Theme.textPrimary)
            metricCard("Pending", "\(pendingCount)", "hourglass", pendingCount > 0 ? Theme.warning : Theme.textPrimary)
        }
    }

    private func metricCard(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
                Spacer()
            }
            Text(value).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TIMESHEET STATUS")
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
            Divider().overlay(Theme.separator)
            HStack(spacing: 12) {
                statusPill("Approved", approvedCount, Theme.accent)
                statusPill("Pending", pendingCount, Theme.warning)
                statusPill("Rejected", rejectedCount, Theme.error)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private func statusPill(_ label: String, _ count: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.headline.weight(.bold)).foregroundStyle(tint)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(tint.opacity(0.10)))
    }

    private var perStaffCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PER STAFF")
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
            Divider().overlay(Theme.separator)

            if perStaff.isEmpty {
                Text("No shifts this week")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                // Column headers
                HStack {
                    Text("Staff").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text("Sched").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: 56, alignment: .trailing)
                    Text("Worked").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: 60, alignment: .trailing)
                    Text("Cost").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary).frame(width: 70, alignment: .trailing)
                }
                ForEach(perStaff) { row in
                    HStack {
                        Text(row.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f", row.scheduled)).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary).frame(width: 56, alignment: .trailing)
                        Text(String(format: "%.1f", row.worked)).font(.caption.weight(.semibold)).foregroundStyle(row.worked > 0 ? Theme.accent : Theme.textTertiary).frame(width: 60, alignment: .trailing)
                        Text(String(format: "$%.0f", row.cost)).font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary).frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(Theme.separator.opacity(0.5))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    // MARK: - Summary footer

    private var summaryBar: some View {
        let content = HStack(spacing: 16) {
            summaryChip(icon: "calendar", text: String(format: "%.0f sched", scheduledHours))
            summaryChip(icon: "clock", text: String(format: "%.0f worked", workedHours))
            summaryChip(icon: "dollarsign.circle", text: String(format: "$%.0f inc. super", totalCost))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)

        return ViewThatFits(in: .horizontal) {
            content
            ScrollView(.horizontal, showsIndicators: false) { content }
        }
        .glassCapsule()
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func summaryChip(icon: String, text: String, tint: Color = Theme.textPrimary) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview {
    ManagerReportsView()
        .environment(RosterRepository())
}
