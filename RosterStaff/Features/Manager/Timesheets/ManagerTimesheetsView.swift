import SwiftUI

// Single, full-width, week-based timesheet review. No split screen: timesheets
// for the selected week flow into an adaptive card grid (1 column on iPhone, more
// as width grows). Tapping a card opens the detail as a sheet on every device.
// Liquid Glass (iOS/iPadOS/macOS 26+) is used on the navigation layer only.
struct ManagerTimesheetsView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var weekOffset = 0
    @State private var selectedStatusFilter: TimesheetFilterStatus = .pending
    @State private var selectedStaffFilter: String = "All staff"
    @State private var selectedTimesheet: Timesheet? = nil

    enum TimesheetFilterStatus: String, CaseIterable, Identifiable {
        case pending, approved, rejected
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    // MARK: - Week math

    private var now: Date { Date() }

    /// Back to the shift-window bound; no forward (there are no future timesheets).
    private var bounds: (min: Int, max: Int) {
        (BusinessRules.shiftWeekOffsetBounds(at: now).min, 0)
    }

    private var monday: Date { RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(now)) }
    private var weekDays: [Date] { RosterCalendar.weekDays(for: monday) }
    private var weekKeys: [String] { weekDays.map { RosterCalendar.dayFormatter.string(from: $0) } }

    private var dateRangeString: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let f = DateFormatter(); f.calendar = RosterCalendar.calendar; f.timeZone = RosterCalendar.timeZone; f.dateFormat = "d MMM"
        let y = DateFormatter(); y.calendar = RosterCalendar.calendar; y.timeZone = RosterCalendar.timeZone; y.dateFormat = "yyyy"
        return "\(f.string(from: first)) – \(f.string(from: last)) \(y.string(from: last))"
    }

    private var weekRelativeLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case -1: return "Last week"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    // MARK: - Data

    /// Shift ids that fall in the selected week (shifts are already loaded for
    /// the manager's window). Timesheets are matched to these.
    private var weekShiftIds: Set<String> {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return Set(repo.shifts.filter { $0.date >= first && $0.date <= last }.map { $0.id })
    }

    private var weekTimesheets: [Timesheet] {
        let ids = weekShiftIds
        return repo.timesheets.filter { ids.contains($0.shiftId) }
    }

    private func statusMatches(_ ts: Timesheet, _ status: TimesheetFilterStatus) -> Bool {
        switch status {
        case .pending: return ts.status == .pending
        case .approved: return ts.status == .approved
        case .rejected: return ts.status == .rejected
        }
    }

    private func count(for status: TimesheetFilterStatus) -> Int {
        weekTimesheets.filter { statusMatches($0, status) }.count
    }

    private var isStaffFilterActive: Bool { selectedStaffFilter != "All staff" }

    private var filteredTimesheets: [Timesheet] {
        weekTimesheets
            .filter { statusMatches($0, selectedStatusFilter) }
            .filter { ts in
                if selectedStaffFilter == "All staff" { return true }
                guard let staff = repo.allUsers.first(where: { $0.fullName == selectedStaffFilter }) else { return false }
                return ts.staffId == staff.id
            }
            .sorted { ($0.submittedAt ?? .distantPast) > ($1.submittedAt ?? .distantPast) }
    }

    private var weekWorkedHours: Double {
        weekTimesheets.reduce(0) { $0 + $1.workedHours }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let width = proxy.size.width

                ZStack {
                    VStack(spacing: 0) {
                        controlBar
                        timesheetScroll(containerWidth: width)
                        summaryBar
                    }
                    .frame(maxWidth: Theme.maxContentWidth)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Timesheets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitlePill(title: "Timesheets Review", icon: "clipboard.fill")
                }
            }
            .sheet(item: $selectedTimesheet) { ts in
                let shift = repo.shifts.first(where: { $0.id == ts.shiftId })
                ManagerTimesheetDetailSheet(timesheet: ts, shift: shift)
            }
        }
    }

    // MARK: - Control bar (glass)

    private var controlBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                weekNavCluster
                dateRangeText
                Spacer(minLength: 8)
                staffFilterChip
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(TimesheetFilterStatus.allCases) { status in
                    statusChip(status)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var dateRangeText: some View {
        Text(dateRangeString)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var weekNavCluster: some View {
        HStack(spacing: 2) {
            Button {
                if weekOffset > bounds.min { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(weekOffset > bounds.min ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(weekOffset <= bounds.min)
            .accessibilityLabel("Previous week")

            Button {
                weekOffset = 0
            } label: {
                HStack(spacing: 6) {
                    Text(weekRelativeLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(weekOffset == 0 ? Theme.textPrimary : Theme.brand)
                    if weekOffset != 0 {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.brand)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(weekOffset == 0)
            .accessibilityLabel(weekOffset == 0 ? "This week" : "Back to this week")

            Button {
                if weekOffset < bounds.max { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(weekOffset < bounds.max ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(weekOffset >= bounds.max)
            .accessibilityLabel("Next week")
        }
        .padding(.horizontal, 4)
        .glassCapsule()
    }

    private func statusChip(_ status: TimesheetFilterStatus) -> some View {
        let selected = selectedStatusFilter == status
        let n = count(for: status)

        return Button {
            selectedStatusFilter = status
            Haptics.selection()
        } label: {
            HStack(spacing: 5) {
                Text(status.title)
                Text("\(n)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? .white : Theme.brand)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? .white : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .modifier(StatusChipBackground(selected: selected))
        }
        .buttonStyle(ZoomButtonStyle())
        .accessibilityLabel("\(status.title), \(n)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Clean segmented-style pills: selected = solid brand, unselected = plain
    /// card pill with a hairline border (no frosted glass, which read as grey).
    private struct StatusChipBackground: ViewModifier {
        let selected: Bool
        func body(content: Content) -> some View {
            if selected {
                content
                    .background(Capsule(style: .continuous).fill(Theme.brandStrong))
            } else {
                content
                    .background(Capsule(style: .continuous).fill(Theme.card))
                    .overlay(Capsule(style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
            }
        }
    }

    /// Springy zoom-on-tap for the filter pills.
    private struct ZoomButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 1.08 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
        }
    }

    private var staffFilterChip: some View {
        Menu {
            Button("All staff") { selectedStaffFilter = "All staff" }
            ForEach(repo.allUsers.filter { $0.role == .staff }) { staff in
                Button(staff.fullName) { selectedStaffFilter = staff.fullName }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                Text(isStaffFilterActive ? selectedStaffFilter : "Staff")
                    .lineLimit(1)
                if isStaffFilterActive {
                    Circle().fill(Theme.brand).frame(width: 6, height: 6)
                } else {
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isStaffFilterActive ? Theme.brand : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(isStaffFilterActive ? Theme.brand.opacity(0.14) : Theme.card)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isStaffFilterActive ? Theme.brand.opacity(0.4) : Theme.separator, lineWidth: 1)
            )
        }
        .accessibilityLabel(isStaffFilterActive ? "Staff filter: \(selectedStaffFilter)" : "Filter by staff")
    }

    // MARK: - Content grid

    private func timesheetScroll(containerWidth: CGFloat) -> some View {
        ScrollView {
            if filteredTimesheets.isEmpty {
                emptyState
                    .padding(.top, 40)
                    .padding(.horizontal, 16)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filteredTimesheets) { ts in
                        Button {
                            selectedTimesheet = ts
                            Haptics.selection()
                        } label: {
                            timesheetCard(ts)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .refreshable { await repo.refreshFromServer() }
    }

    // Content layer — solid card (no glass).
    private func timesheetCard(_ ts: Timesheet) -> some View {
        let staff = repo.allUsers.first(where: { $0.id == ts.staffId })
        let shift = repo.shifts.first(where: { $0.id == ts.shiftId })
        let rosteredHours = shift?.scheduledHours ?? 0
        let actualHours = ts.workedHours
        let mismatch = abs(rosteredHours - actualHours) > 0.01
        let ds = StaffShiftDisplayStatus(rawValue: ts.status.rawValue) ?? .pending
        let style = Theme.style(for: ds)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(staff?.initials ?? "?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(style.tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(style.soft))

                VStack(alignment: .leading, spacing: 2) {
                    Text(staff?.fullName ?? "Staff Member")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let shift {
                        Text(RosterFormat.date(shift.date))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(ds.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(style.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(style.soft))
            }

            Divider().overlay(Theme.separator)

            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(String(format: "%.1fh", actualHours))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(mismatch ? Theme.warning : Theme.textPrimary)
                    Text("worked")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    // Break is already deducted from workedHours — surface it
                    // so the manager can confirm the deduction at a glance.
                    Text(ts.actualBreakMinutes > 0 ? "· \(ts.actualBreakMinutes)m break" : "· no break")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    if mismatch {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                    }
                }

                Spacer()

                if mismatch {
                    Text(String(format: "Rostered %.1fh", rosteredHours))
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else if let submitted = ts.submittedAt {
                    Text(submitted, style: .date)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(mismatch ? Theme.warning.opacity(0.35) : Theme.separator, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No \(selectedStatusFilter.title.lowercased()) timesheets")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            Text("for \(weekRelativeLabel.lowercased()) (\(dateRangeString))")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Bottom summary (glass)

    private var summaryBar: some View {
        let content = HStack(spacing: 16) {
            summaryChip(icon: "clipboard", text: "\(weekTimesheets.count) sheet\(weekTimesheets.count == 1 ? "" : "s")")
            summaryChip(icon: "clock", text: String(format: "%.0f hrs worked", weekWorkedHours))
            summaryChip(icon: "hourglass",
                        text: "\(count(for: .pending)) pending",
                        tint: count(for: .pending) > 0 ? Theme.warning : Theme.textPrimary)
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
    ManagerTimesheetsView()
        .environment(RosterRepository())
}
