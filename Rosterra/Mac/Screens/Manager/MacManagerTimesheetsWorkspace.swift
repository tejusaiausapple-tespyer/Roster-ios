#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacManagerTimesheetsWorkspace: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var weekOffset = 0
    @State private var statusFilter: StatusFilter = .pending
    @State private var staffFilterID: String?
    @State private var selectedTimesheetID: String?
    @State private var rejectionReason = ""
    @State private var showingRejectionSheet = false
    @State private var showingBulkConfirmation = false
    @State private var isBulkApproving = false

    init() {}

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case pending
        case absent
        case approved
        case rejected

        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        func includes(_ status: TimesheetStatus) -> Bool {
            switch self {
            case .pending:
                return status == .pending || status == .absentReported
            case .absent:
                return status == .absentReported || status == .absent
            case .approved:
                return status == .approved
            case .rejected:
                return status == .rejected
            }
        }
    }

    private var bounds: (min: Int, max: Int) {
        (BusinessRules.shiftWeekOffsetBounds().min, 0)
    }

    private var monday: Date {
        RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart())
    }

    private var weekDays: [Date] {
        RosterCalendar.weekDays(for: monday)
    }

    private var weekKeys: [String] {
        weekDays.map { RosterCalendar.dateString(from: $0) }
    }

    private var dateRange: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return RosterCalendar.formatDateRange(start: first, end: last)
    }

    private var weekLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case -1: return "Last week"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    private var weekTimesheets: [Timesheet] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.timesheets.filter { timesheet in
            guard let date = repo.shiftsById[timesheet.shiftId]?.date else { return false }
            return date >= first && date <= last
        }
    }

    private var filteredTimesheets: [Timesheet] {
        weekTimesheets
            .filter { statusFilter.includes($0.status) }
            .filter { staffFilterID == nil || $0.staffId == staffFilterID }
            .sorted { lhs, rhs in
                (lhs.submittedAt ?? .distantPast) > (rhs.submittedAt ?? .distantPast)
            }
    }

    private var selectedTimesheet: Timesheet? {
        guard let selectedTimesheetID else { return nil }
        return repo.timesheets.first { $0.id == selectedTimesheetID }
    }

    private var pendingForBulkApproval: [Timesheet] {
        filteredTimesheets.filter { $0.status == .pending }
    }

    private var selectedStaffName: String {
        guard let staffFilterID else { return "All staff" }
        return repo.user(id: staffFilterID)?.fullName ?? "All staff"
    }

    var body: some View {
        MacScreen(
            title: "Timesheets",
            subtitle: "\(filteredTimesheets.count) in view"
        ) {
            VStack(spacing: 0) {
                controls

                HStack(spacing: MacSpace.lg) {
                    queuePanel
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 430)

                    inspectorPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, MacSpace.xl)
                .padding(.bottom, MacSpace.xl)
            }
        }
        .onAppear { maintainSelection() }
        .onChange(of: filteredTimesheets.map(\.id)) { _, _ in maintainSelection() }
        .sheet(isPresented: $showingRejectionSheet) {
            rejectionSheet
                .macObserved(repo: repo, toasts: toasts)
        }
        .alert(
            "Approve \(pendingForBulkApproval.count) timesheets?",
            isPresented: $showingBulkConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Approve All") {
                Task { await approveAllVisible() }
            }
        } message: {
            Text("Only worked-hours submissions in the current filtered view will be approved.")
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: MacSpace.md) {
            HStack(spacing: MacSpace.md) {
                weekNavigation

                Text(dateRange)
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: MacSpace.md)

                staffFilter

                if statusFilter == .pending, !pendingForBulkApproval.isEmpty {
                    Button {
                        showingBulkConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            if isBulkApproving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(
                                isBulkApproving
                                    ? "Approving…"
                                    : "Approve all \(pendingForBulkApproval.count)",
                                systemImage: "checkmark.circle"
                            )
                        }
                    }
                    .timesheetGlassPill()
                    .disabled(isBulkApproving)
                }
            }

            HStack(spacing: MacSpace.sm) {
                Spacer(minLength: 0)
                ForEach(StatusFilter.allCases) { filter in
                    statusButton(filter)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
    }

    private var weekNavigation: some View {
        HStack(spacing: MacSpace.sm) {
            Button {
                if weekOffset > bounds.min { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 18, height: 18)
            }
            .timesheetGlassPill()
            .disabled(weekOffset <= bounds.min)
            .help("Previous week")

            Button {
                weekOffset = 0
            } label: {
                Text(weekLabel)
                    .frame(minWidth: 78)
            }
            .timesheetGlassPill()
            .disabled(weekOffset == 0)
            .help(weekOffset == 0 ? "Current week" : "Return to current week")

            Button {
                if weekOffset < bounds.max { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 18, height: 18)
            }
            .timesheetGlassPill()
            .disabled(weekOffset >= bounds.max)
            .help("Next week")
        }
    }

    private var staffFilter: some View {
        Menu {
            Button("All staff") { staffFilterID = nil }
            Divider()
            ForEach(repo.staffMembers.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }) { staff in
                Button(staff.fullName) { staffFilterID = staff.id }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                Text(selectedStaffName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, MacSpace.md)
            .padding(.vertical, 7)
            .macGlassSurface(cornerRadius: MacRadius.pill)
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(MacColor.textPrimary)
    }

    private func statusButton(_ filter: StatusFilter) -> some View {
        let isSelected = statusFilter == filter
        let count = weekTimesheets.filter { filter.includes($0.status) }.count

        return Button {
            statusFilter = filter
        } label: {
            HStack(spacing: 6) {
                Text(filter.title)
                Text("\(count)")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.textTertiary)
            }
            .font(MacType.captionStrong)
            .foregroundStyle(MacColor.textPrimary)
            .padding(.horizontal, MacSpace.lg)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? MacColor.cardBackground : Color.clear)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? MacColor.cardBorder : MacColor.separator.opacity(0.7),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Queue

    private var queuePanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusFilter == .pending ? "Review queue" : statusFilter.title)
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Text(queueSummary)
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }
                Spacer()
                MacCountBadge(count: filteredTimesheets.count)
            }
            .padding(MacSpace.lg)

            if filteredTimesheets.isEmpty {
                MacEmptyState(
                    title: "Nothing here",
                    subtitle: emptyMessage,
                    icon: statusFilter == .pending ? "checkmark.seal" : "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MacSpace.sm) {
                        ForEach(filteredTimesheets) { timesheet in
                            queueRow(timesheet)
                        }
                    }
                    .padding(.horizontal, MacSpace.sm)
                    .padding(.bottom, MacSpace.sm)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var queueSummary: String {
        let hours = filteredTimesheets.reduce(0) { $0 + $1.workedHours }
        return "\(filteredTimesheets.count) records · \(RosterFormat.hours(hours))"
    }

    private var emptyMessage: String {
        switch statusFilter {
        case .pending: return "All submitted timesheets for \(weekLabel.lowercased()) are reviewed."
        case .absent: return "No absence records for \(weekLabel.lowercased())."
        case .approved: return "No approved timesheets for \(weekLabel.lowercased())."
        case .rejected: return "No rejected timesheets for \(weekLabel.lowercased())."
        }
    }

    private func queueRow(_ timesheet: Timesheet) -> some View {
        let staff = repo.user(id: timesheet.staffId)
        let shift = repo.shiftsById[timesheet.shiftId]
        let selected = selectedTimesheetID == timesheet.id
        let mismatch = shift.map { abs($0.scheduledHours - timesheet.workedHours) > 0.01 } ?? false

        return Button {
            selectedTimesheetID = timesheet.id
        } label: {
            VStack(alignment: .leading, spacing: MacSpace.sm) {
                HStack(spacing: MacSpace.sm) {
                    MacAvatar(name: staff?.fullName ?? "?", size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(staff?.fullName ?? "Staff member")
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)
                            .lineLimit(1)
                        Text(shift.map { RosterFormat.date($0.date) } ?? "Shift unavailable")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                    MacStatusPill(timesheetStatus: timesheet.status)
                }

                HStack(spacing: MacSpace.sm) {
                    if timesheet.status == .absentReported || timesheet.status == .absent {
                        Label("Did not attend", systemImage: "person.fill.xmark")
                            .foregroundStyle(MacColor.warning)
                    } else {
                        Text("\(timesheet.actualStart) – \(timesheet.actualEnd)")
                            .font(MacType.mono)
                        Spacer(minLength: 0)
                        Text(RosterFormat.hours(timesheet.workedHours))
                            .font(MacType.bodyStrong)
                        if mismatch {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MacColor.warning)
                                .help("Worked hours differ from rostered hours")
                        }
                    }
                }
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
            }
            .padding(MacSpace.md)
            .background(
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .fill(selected ? MacColor.tableRowSelected : MacColor.cardBackgroundSecondary)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(
                        selected ? MacColor.accent.opacity(0.45) : MacColor.cardBorder,
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("View details") { selectedTimesheetID = timesheet.id }
            if timesheet.status == .pending {
                Button("Approve") { Task { await approve(timesheet) } }
            } else if timesheet.status == .absentReported {
                Button("Confirm absence") { Task { await approve(timesheet) } }
            }
            if timesheet.status == .pending || timesheet.status == .absentReported {
                Button("Reject", role: .destructive) {
                    selectedTimesheetID = timesheet.id
                    rejectionReason = ""
                    showingRejectionSheet = true
                }
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorPanel: some View {
        if let timesheet = selectedTimesheet {
            inspector(timesheet)
        } else {
            MacEmptyState(
                title: "Select a timesheet",
                subtitle: "Choose a record from the queue to compare rostered and submitted hours.",
                icon: "doc.text.magnifyingglass"
            )
            .background(MacColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }
        }
    }

    private func inspector(_ timesheet: Timesheet) -> some View {
        let staff = repo.user(id: timesheet.staffId)
        let shift = repo.shiftsById[timesheet.shiftId]
        let isAbsence = timesheet.status == .absentReported || timesheet.status == .absent
        let isActionable = timesheet.status == .pending || timesheet.status == .absentReported
        let variance = timesheet.workedHours - (shift?.scheduledHours ?? 0)
        let rate = repo.liveHourlyRate(forStaffId: timesheet.staffId, shiftDateKey: shift?.date)

        return ScrollView {
            VStack(alignment: .leading, spacing: MacSpace.lg) {
                HStack(spacing: MacSpace.md) {
                    MacAvatar(name: staff?.fullName ?? "?", size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(staff?.fullName ?? "Staff member")
                            .font(MacType.pageTitle)
                            .foregroundStyle(MacColor.textPrimary)
                        Text(shift.map { "\(RosterFormat.date($0.date)) · \($0.department ?? "Shift")" } ?? "Shift unavailable")
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }
                    Spacer()
                    MacStatusPill(timesheetStatus: timesheet.status)
                }

                if isAbsence {
                    absenceCard(timesheet)
                } else {
                    HStack(spacing: MacSpace.md) {
                        timeCard(
                            title: "Rostered",
                            time: shift.map { "\(RosterFormat.time($0.rosteredStart)) – \(RosterFormat.time($0.rosteredEnd))" } ?? "Unavailable",
                            detail: shift.map { "\(RosterFormat.hours($0.scheduledHours)) · \($0.breakMinutes)m break" } ?? "No roster record",
                            icon: "calendar"
                        )
                        timeCard(
                            title: "Submitted",
                            time: "\(RosterFormat.time(timesheet.actualStart)) – \(RosterFormat.time(timesheet.actualEnd))",
                            detail: "\(RosterFormat.hours(timesheet.workedHours)) · \(timesheet.actualBreakMinutes)m break",
                            icon: "clock"
                        )
                    }

                    HStack(spacing: MacSpace.md) {
                        inspectorMetric("Worked", value: RosterFormat.hours(timesheet.workedHours))
                        inspectorMetric(
                            "Variance",
                            value: String(format: "%@%.1fh", variance > 0 ? "+" : "", variance),
                            tint: abs(variance) > 0.01 ? MacColor.warning : MacColor.success
                        )
                        inspectorMetric("Est. cost", value: Self.aud(timesheet.workedHours * rate))
                    }
                }

                if let notes = timesheet.staffNotes, !notes.isEmpty {
                    MacCard(
                        title: isAbsence ? "Absence reason" : "Staff notes",
                        icon: isAbsence ? "person.fill.xmark" : "note.text"
                    ) {
                        Text(notes)
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if timesheet.status == .rejected, let reason = timesheet.rejectedReason, !reason.isEmpty {
                    MacCard(title: "Rejection reason", icon: "exclamationmark.octagon") {
                        Text(reason)
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }
                }

                if isActionable {
                    HStack(spacing: MacSpace.md) {
                        Button("Reject…") {
                            rejectionReason = ""
                            showingRejectionSheet = true
                        }
                        .macButton(.destructive)

                        Spacer()

                        MacAsyncButton(variant: .success) {
                            await approve(timesheet)
                        } label: {
                            Label(
                                timesheet.status == .absentReported ? "Confirm absence" : "Approve timesheet",
                                systemImage: timesheet.status == .absentReported
                                    ? "person.fill.checkmark"
                                    : "checkmark.circle"
                            )
                        }
                    }
                    .padding(.top, MacSpace.sm)
                }
            }
            .padding(MacSpace.xl)
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func absenceCard(_ timesheet: Timesheet) -> some View {
        MacCard(title: timesheet.status == .absentReported ? "Absence reported" : "Absence confirmed", icon: "person.fill.xmark") {
            Text(
                timesheet.status == .absentReported
                    ? "This staff member reported that they did not attend the shift. Confirm the absence or reject the report."
                    : "This absence has been reviewed and confirmed."
            )
            .font(MacType.body)
            .foregroundStyle(MacColor.textSecondary)
        }
    }

    private func timeCard(title: String, time: String, detail: String, icon: String) -> some View {
        MacCard(title: title, icon: icon) {
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(MacType.monoLarge)
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func inspectorMetric(_ title: String, value: String, tint: Color = MacColor.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
            Text(value)
                .font(MacType.monoLarge)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private static func aud(_ value: Double) -> String {
        value.formatted(
            .currency(code: "AUD")
                .locale(Locale(identifier: "en_AU"))
                .precision(.fractionLength(2))
        )
    }

    // MARK: - Actions

    private var rejectionSheet: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            Text("Reject timesheet")
                .font(MacType.sectionHeader)
                .foregroundStyle(MacColor.textPrimary)
            Text("Explain what the staff member needs to correct before resubmitting.")
                .font(MacType.body)
                .foregroundStyle(MacColor.textSecondary)
            TextField("Reason for rejection", text: $rejectionReason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Button("Cancel") { showingRejectionSheet = false }
                    .macButton(.bordered)
                Spacer()
                MacAsyncButton(variant: .destructive) {
                    await rejectSelected()
                } label: {
                    Text("Reject timesheet")
                }
                .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 480)
    }

    private func maintainSelection() {
        let ids = Set(filteredTimesheets.map(\.id))
        if let selectedTimesheetID, ids.contains(selectedTimesheetID) { return }
        selectedTimesheetID = filteredTimesheets.first?.id
    }

    private func approve(_ timesheet: Timesheet) async {
        do {
            if timesheet.status == .absentReported {
                try await repo.confirmAbsence(id: timesheet.id, managerNotes: nil)
                toasts.show("Absence confirmed", style: .success)
            } else {
                try await repo.approveTimesheet(id: timesheet.id, managerNotes: nil)
                toasts.show("Timesheet approved", style: .success)
            }
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }

    private func approveAllVisible() async {
        guard !isBulkApproving else { return }
        isBulkApproving = true
        defer { isBulkApproving = false }

        let ids = pendingForBulkApproval.map(\.id)
        let result = await repo.approveTimesheets(ids: ids)

        if result.failedIds.isEmpty {
            toasts.show("\(result.approvedIds.count) timesheets approved", style: .success)
        } else {
            toasts.show("\(result.approvedIds.count) approved · \(result.failedIds.count) failed", style: .warning)
        }
    }

    private func rejectSelected() async {
        guard let timesheet = selectedTimesheet else { return }
        let reason = rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }

        do {
            try await repo.rejectTimesheet(id: timesheet.id, reason: reason, managerNotes: nil)
            showingRejectionSheet = false
            rejectionReason = ""
            toasts.show("Timesheet rejected", style: .warning)
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }
}

private extension View {
    @ViewBuilder
    func timesheetGlassPill() -> some View {
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
