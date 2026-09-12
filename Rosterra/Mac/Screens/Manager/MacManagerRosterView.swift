#if targetEnvironment(macCatalyst)
import SwiftUI
import FirebaseFirestore

// MARK: - Mac Manager Roster (PWA-aligned)

struct MacManagerRosterView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var weekOffset = 0
    @State private var viewMode: MacRosterViewMode = .week
    @State private var staffFilterId: String = "all"
    @State private var statusFilter: MacRosterStatusFilter = .all
    @State private var activeSheet: MacRosterSheet?
    @State private var shiftToDelete: Shift?
    @State private var dragOverDate: String?
    @State private var isMutatingShift = false
    @State private var isTogglingWeekLock = false

    init() {}

    private var bounds: (min: Int, max: Int) { BusinessRules.shiftWeekOffsetBounds() }
    private var monday: Date { RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(Date())) }
    private var weekDays: [Date] { RosterCalendar.weekDays(for: monday) }
    private var weekKeys: [String] { weekDays.map { RosterCalendar.dateString(from: $0) } }
    private var weekStartKey: String { weekKeys.first ?? RosterCalendar.weekStartKey() }

    private var activeStaff: [AppUser] {
        repo.staffMembers
            .filter { $0.status == .active }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private var visibleStaff: [AppUser] {
        if staffFilterId == "all" { return activeStaff }
        return activeStaff.filter { $0.id == staffFilterId }
    }

    private var dateRange: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let day = DateFormatter()
        day.calendar = RosterCalendar.calendar
        day.timeZone = RosterCalendar.timeZone
        day.locale = Locale(identifier: "en_AU")
        day.dateFormat = "d MMM"
        let year = DateFormatter()
        year.calendar = RosterCalendar.calendar
        year.timeZone = RosterCalendar.timeZone
        year.locale = Locale(identifier: "en_AU")
        year.dateFormat = "yyyy"
        return "\(day.string(from: first)) – \(day.string(from: last)) \(year.string(from: last))"
    }

    private var weekLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        case let n where n > 1: return "Week +\(n)"
        default: return "Week \(weekOffset)"
        }
    }

    private var filteredShifts: [Shift] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.shifts
            .filter { shift in
                shift.date >= first && shift.date <= last
                    && (staffFilterId == "all" || shift.staffId == staffFilterId)
                    && statusFilter.matches(shift.status)
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                if lhs.rosteredStart != rhs.rosteredStart { return lhs.rosteredStart < rhs.rosteredStart }
                let dobA = repo.user(id: lhs.staffId)?.dob ?? "9999-99-99"
                let dobB = repo.user(id: rhs.staffId)?.dob ?? "9999-99-99"
                return dobA < dobB
            }
    }

    private var kpiShifts: [Shift] {
        filteredShifts.filter { $0.status != .cancelled }
    }

    private var weekDrafts: [Shift] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.shifts.filter { $0.date >= first && $0.date <= last && $0.status == .draft }
    }

    private var draftCount: Int { weekDrafts.count }

    private var totalHours: Double {
        kpiShifts.reduce(0) { $0 + $1.scheduledHours }
    }

    private var grossWages: Double {
        kpiShifts.reduce(0) { sum, shift in
            sum + shift.scheduledHours * repo.liveHourlyRate(forStaffId: shift.staffId, shiftDateKey: shift.date)
        }
    }

    private var superannuation: Double {
        kpiShifts.reduce(0) { sum, shift in
            let rate = repo.liveHourlyRate(forStaffId: shift.staffId, shiftDateKey: shift.date)
            let percent = repo.user(id: shift.staffId)?.superRate ?? BusinessRules.defaultSuperRatePercent
            return sum + shift.scheduledHours * rate * percent / 100
        }
    }

    private var totalLabourCost: Double { grossWages + superannuation }

    private var rosteredStaffCount: Int {
        Set(kpiShifts.map(\.staffId)).count
    }

    private var missingRateNames: [String] {
        let ids = Set(kpiShifts.map(\.staffId))
        return ids.compactMap { id in
            guard repo.liveHourlyRate(forStaffId: id, shiftDateKey: weekStartKey) <= 0 else { return nil }
            return repo.user(id: id)?.fullName
        }
        .sorted()
    }

    private var isWeekAvailabilityLocked: Bool {
        repo.lockedAvailabilityWeeks.contains(weekStartKey)
    }

    private var defaultNewShiftDate: String {
        let today = RosterCalendar.todayKey()
        return weekKeys.contains(today) ? today : (weekKeys.first ?? today)
    }

    private var shiftsByDate: [String: [Shift]] {
        Dictionary(grouping: filteredShifts, by: \.date)
    }

    private var shiftsByStaff: [String: [Shift]] {
        Dictionary(grouping: filteredShifts, by: \.staffId)
    }

    var body: some View {
        MacScreen(
            title: "Roster",
            subtitle: "Adelaide time"
        ) {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: MacSpace.md) {
                        Text(dateRange)
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(MacColor.textPrimary)
                        toolbar
                    }
                    .padding(MacSpace.xl)
                    ScrollView([.horizontal, .vertical]) {
                        rosterBody
                            .frame(width: max(geometry.size.width - 48, viewMode == .week ? 1050 : 720))
                            .padding(MacSpace.xl)
                    }
                    .scrollIndicators(.hidden)
                    rosterSummary
                        .padding(.horizontal, MacSpace.xl)
                        .padding(.vertical, MacSpace.md)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
                .macObserved(repo: repo, toasts: toasts)
        }
        .confirmationDialog(
            "Delete Shift",
            isPresented: Binding(
                get: { shiftToDelete != nil },
                set: { if !$0 { shiftToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteShift(shiftToDelete) }
            }
            Button("Cancel", role: .cancel) { shiftToDelete = nil }
        } message: {
            Text("This shift and any linked timesheets will be deleted. This cannot be undone.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .macNewShiftRequested)) { _ in
            openCreate()
        }
    }

    // MARK: Header

    @ViewBuilder
    private var publishButton: some View {
        if draftCount > 0 {
            Button {
                activeSheet = .publish
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Publish \(draftCount)")
                }
            }
            .rosterToolbarGlassPill()
            .help("Publish \(draftCount) draft shift\(draftCount == 1 ? "" : "s")")
        }
    }

    private func lockButton(compact: Bool) -> some View {
        Button {
            guard !isTogglingWeekLock else { return }
            isTogglingWeekLock = true
            Task {
                await toggleWeekLock()
                isTogglingWeekLock = false
            }
        } label: {
            HStack(spacing: 4) {
                if isTogglingWeekLock {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isWeekAvailabilityLocked ? "lock.fill" : "lock.open")
                }
                if !compact {
                    Text(isWeekAvailabilityLocked ? "Availability locked" : "Lock availability")
                }
            }
        }
        .rosterToolbarGlassPill()
        .disabled(isTogglingWeekLock)
        .help(isWeekAvailabilityLocked
              ? "Staff availability is locked for this week — click to unlock"
              : "Lock staff availability for this week")
    }

    private func copyButton(compact: Bool) -> some View {
        Button {
            activeSheet = .copyWeek
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                if !compact {
                    Text("Copy last week")
                }
            }
        }
        .rosterToolbarGlassPill()
        .help("Copy last week's shifts into this week as drafts")
    }

    private var addShiftButton: some View {
        Button {
            openCreate()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add shift")
            }
        }
        .rosterToolbarGlassPill()
    }

    // MARK: Toolbar

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            ZStack {
                HStack(alignment: .center, spacing: MacSpace.md) {
                    weekStepper
                    viewModeControl
                    Spacer(minLength: MacSpace.md)
                    publishButton
                    staffFilterMenu
                    statusFilterMenu
                }

                HStack(spacing: MacSpace.sm) {
                    lockButton(compact: false)
                    copyButton(compact: false)
                    addShiftButton
                }
            }
            VStack(alignment: .leading, spacing: MacSpace.sm) {
                HStack(spacing: MacSpace.md) {
                    weekStepper
                    viewModeControl
                    Spacer(minLength: 0)
                    staffFilterMenu
                    statusFilterMenu
                }

                HStack(spacing: MacSpace.sm) {
                    Spacer()
                    publishButton
                    lockButton(compact: false)
                    copyButton(compact: false)
                    addShiftButton
                    Spacer()
                }
            }
        }
    }

    private var weekStepper: some View {
        HStack(spacing: MacSpace.sm) {
            Button {
                stepWeek(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .rosterToolbarGlassPill()
            .disabled(weekOffset <= bounds.min)
            .help("Previous week")

            Button(weekLabel) {
                weekOffset = 0
            }
            .font(MacType.captionStrong)
            .foregroundStyle(MacColor.textPrimary)
            .frame(minWidth: 88)
            .rosterToolbarGlassPill()
            .help("Jump to this week")

            Button {
                stepWeek(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .rosterToolbarGlassPill()
            .disabled(weekOffset >= bounds.max)
            .help("Next week")
        }
    }

    private var viewModeControl: some View {
        Picker("Roster view", selection: $viewMode) {
            ForEach(MacRosterViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 190)
    }

    private var staffFilterLabel: String {
        if staffFilterId == "all" { return "All staff" }
        return activeStaff.first(where: { $0.id == staffFilterId })?.fullName ?? "Staff"
    }

    private var staffFilterMenu: some View {
        Menu {
            Button("All staff") { staffFilterId = "all" }
            if !activeStaff.isEmpty { Divider() }
            ForEach(activeStaff) { staff in
                Button(staff.fullName) { staffFilterId = staff.id }
            }
        } label: {
            filterChip(icon: "person", title: staffFilterLabel)
        }
        .menuStyle(.borderlessButton)
        .help("Filter by staff member")
    }

    private var statusFilterMenu: some View {
        Menu {
            ForEach(MacRosterStatusFilter.allCases) { filter in
                Button(filter.title) { statusFilter = filter }
            }
        } label: {
            filterChip(icon: "line.3.horizontal.decrease.circle", title: statusFilter.title)
        }
        .menuStyle(.borderlessButton)
        .help("Filter by shift status")
    }

    private func filterChip(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacColor.textTertiary)
            Text(title)
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(MacColor.textTertiary)
        }
        .padding(.horizontal, MacSpace.md)
        .padding(.vertical, 7)
        .macGlassSurface(cornerRadius: MacRadius.pill)
        .contentShape(Capsule(style: .continuous))
    }

    // MARK: KPIs

    private var rosterSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: MacSpace.md) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MacSpace.xl) {
                        summaryTotals
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        summaryTotals
                    }
                }
                .padding(.horizontal, MacSpace.lg)
                .padding(.vertical, MacSpace.sm)
                .macGlassSurface(cornerRadius: MacRadius.pill)

                Spacer(minLength: MacSpace.sm)

                Label("Published shifts are locked", systemImage: "lock.fill")
                    .padding(.horizontal, MacSpace.md)
                    .padding(.vertical, MacSpace.sm)
                    .macGlassSurface(cornerRadius: MacRadius.pill)
            }
            .font(MacType.caption)
            .foregroundStyle(MacColor.textPrimary)

            if !missingRateNames.isEmpty {
                Label("Missing wage rate: \(missingRateNames.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.error)
                    .padding(.horizontal, MacSpace.md)
                    .padding(.vertical, MacSpace.sm)
                    .macGlassSurface(cornerRadius: MacRadius.pill)
            }
        }
    }

    @ViewBuilder
    private var summaryTotals: some View {
        Text("\(RosterFormat.hours(totalHours)) · \(rosteredStaffCount) staff · \(draftCount) drafts")
        Text("Gross \(MacRosterFormatting.aud(grossWages)) · Super \(MacRosterFormatting.aud(superannuation)) · Total \(MacRosterFormatting.aud(totalLabourCost))")
            .monospacedDigit()
    }

    private var kpiRow: some View {
        HStack(alignment: .top, spacing: MacSpace.md) {
            MacStatCard(
                title: "Total Rostered Hours",
                value: RosterFormat.hours(totalHours),
                subtitle: "scheduled this week",
                icon: "clock.fill",
                tint: MacColor.accent
            )

            MacRosterBudgetCard(
                gross: MacRosterFormatting.aud(grossWages),
                superannuation: MacRosterFormatting.aud(superannuation),
                total: MacRosterFormatting.aud(totalLabourCost),
                missingNames: missingRateNames
            )

            MacStatCard(
                title: "Active Rostered Staff",
                value: "\(rosteredStaffCount)",
                subtitle: "unique staff members",
                icon: "person.2.fill",
                tint: MacColor.info
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Body

    @ViewBuilder
    private var rosterBody: some View {
        if activeStaff.isEmpty {
            MacEmptyState(
                title: "No Active Staff",
                subtitle: "Add active team members in the Staff Directory to schedule shifts here.",
                icon: "person.2.slash"
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(MacColor.cardBackground, in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            )
        } else {
            switch viewMode {
            case .week:
                MacRosterWeekView(
                    weekDays: weekDays,
                    shiftsByDate: shiftsByDate,
                    dragOverDate: dragOverDate,
                    canDragShift: canDragShift,
                    onCreate: { openCreate(date: $0) },
                    onEdit: { activeSheet = .edit($0) },
                    onDelete: { shiftToDelete = $0 },
                    onDrop: handleShiftDrop,
                    onDragTargetChange: { date, hovering in
                        dragOverDate = hovering ? date : (dragOverDate == date ? nil : dragOverDate)
                    }
                )
            case .staff:
                MacRosterStaffView(
                    weekDays: weekDays,
                    staff: visibleStaff,
                    shiftsByStaff: shiftsByStaff,
                    weekStartKey: weekStartKey,
                    onCreate: { date, staffId in openCreate(date: date, staffId: staffId) },
                    onEdit: { activeSheet = .edit($0) }
                )
            case .day:
                MacRosterDayView(
                    weekDays: weekDays,
                    shiftsByDate: shiftsByDate,
                    onCreate: { openCreate(date: $0) },
                    onEdit: { activeSheet = .edit($0) },
                    onDelete: { shiftToDelete = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: MacRosterSheet) -> some View {
        switch sheet {
        case .create(let date, let staffId):
            MacShiftEditorModal(initialDate: date, initialStaffId: staffId)
        case .edit(let shift):
            MacShiftEditorModal(shift: shift)
        case .publish:
            MacRosterPublishSheet(
                draftCount: draftCount,
                onCancel: { activeSheet = nil },
                onPublish: { lock in
                    await publishDrafts(lockWeek: lock)
                }
            )
        case .copyWeek:
            MacRosterCopyWeekSheet(
                staff: activeStaff,
                destination: dateRange,
                monday: monday,
                onCancel: { activeSheet = nil },
                onCopy: { ids in await copyLastWeek(staffIDs: ids) }
            )
        case .drop(let shift, let targetDate):
            MacRosterDropSheet(
                shift: shift,
                targetDate: targetDate,
                onCancel: { activeSheet = nil },
                onMove: { await moveDroppedShift(shift, to: targetDate) },
                onCopy: { await copyDroppedShift(shift, to: targetDate) }
            )
        }
    }

    // MARK: Actions

    private func stepWeek(_ delta: Int) {
        weekOffset = min(max(weekOffset + delta, bounds.min), bounds.max)
    }

    private func openCreate(date: String? = nil, staffId: String? = nil) {
        activeSheet = .create(date: date ?? defaultNewShiftDate, staffId: staffId)
    }

    /// Publication locks cards in every week, including future rosters.
    private func canDragShift(_ shift: Shift) -> Bool {
        viewMode == .week && MacRosterCopyPlan.canDrag(shift)
    }

    private func handleShiftDrop(shiftId: String, targetDate: String) {
        dragOverDate = nil
        guard let shift = repo.shifts.first(where: { $0.id == shiftId }) else { return }
        guard canDragShift(shift) else {
            toasts.show("Only draft shifts can be moved or copied by dragging.", style: .warning)
            return
        }
        guard shift.date != targetDate else { return }
        activeSheet = .drop(shift: shift, targetDate: targetDate)
    }

    private func hasSameStaffOverlap(_ shift: Shift, on targetDate: String) -> Bool {
        repo.shifts.contains { other in
            other.id != shift.id
                && other.staffId == shift.staffId
                && other.date == targetDate
                && other.status != .cancelled
                && MacRosterShiftOverlap.overlaps(shift, other)
        }
    }

    private func moveDroppedShift(_ shift: Shift, to targetDate: String) async {
        guard !isMutatingShift else { return }
        guard let shift = repo.shifts.first(where: { $0.id == shift.id }), shift.status == .draft else {
            activeSheet = nil
            toasts.show("This shift is no longer a draft. The roster has been refreshed.", style: .warning)
            return
        }
        isMutatingShift = true
        defer { isMutatingShift = false }
        if hasSameStaffOverlap(shift, on: targetDate) {
            toasts.show("This staff member already has a shift at this time.", style: .error)
            return
        }
        do {
            try await repo.saveShift(
                id: shift.id,
                staffId: shift.staffId,
                date: targetDate,
                start: shift.rosteredStart,
                end: shift.rosteredEnd,
                breakMinutes: shift.breakMinutes,
                location: shift.location,
                department: shift.department,
                notes: shift.notes,
                status: .draft
            )
            activeSheet = nil
            toasts.show("Shift moved to \(RosterFormat.date(targetDate))", style: .success)
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }

    private func copyDroppedShift(_ shift: Shift, to targetDate: String) async {
        guard !isMutatingShift else { return }
        guard let shift = repo.shifts.first(where: { $0.id == shift.id }), shift.status == .draft else {
            activeSheet = nil
            toasts.show("This shift is no longer a draft. The roster has been refreshed.", style: .warning)
            return
        }
        isMutatingShift = true
        defer { isMutatingShift = false }
        if hasSameStaffOverlap(shift, on: targetDate) {
            toasts.show("This staff member already has a shift at this time.", style: .error)
            return
        }
        do {
            try await repo.saveShift(
                id: nil,
                staffId: shift.staffId,
                date: targetDate,
                start: shift.rosteredStart,
                end: shift.rosteredEnd,
                breakMinutes: shift.breakMinutes,
                location: shift.location,
                department: shift.department,
                notes: shift.notes,
                status: .draft
            )
            activeSheet = nil
            toasts.show("Shift copied to \(RosterFormat.date(targetDate))", style: .success)
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }

    private func toggleWeekLock() async {
        let locking = !isWeekAvailabilityLocked
        do {
            try await repo.setAvailabilityWeekLock(weekKey: weekStartKey, locked: locking)
            toasts.show(
                locking
                    ? "Week locked — staff availability is frozen"
                    : "Week unlocked — staff can update availability again",
                style: .success
            )
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }

    private func publishDrafts(lockWeek: Bool) async {
        guard let first = weekKeys.first, let last = weekKeys.last else { return }
        let count = draftCount
        do {
            try await repo.publishAllDrafts(from: first, to: last)
            if lockWeek {
                try await repo.setAvailabilityWeekLock(weekKey: weekStartKey, locked: true)
            }
            activeSheet = nil
            let lockNote = lockWeek ? " — availability locked for this week" : ""
            toasts.show("\(count) shift\(count == 1 ? "" : "s") published\(lockNote)", style: .success)
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }

    private func deleteShift(_ shift: Shift?) async {
        guard let shift else { return }
        do {
            try await repo.deleteShift(shift.id)
            toasts.show("Shift deleted", style: .info)
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
        shiftToDelete = nil
    }

    private func copyLastWeek(staffIDs: Set<String>?) async {
        let lastMonday = RosterCalendar.addDays(-7, to: monday)
        let lastWeekKeys = RosterCalendar.weekDays(for: lastMonday).map { RosterCalendar.dateString(from: $0) }
        guard let firstKey = lastWeekKeys.first, let lastKey = lastWeekKeys.last else { return }

        do {
            let db = Firestore.firestore()
            let lastSnap = try await db.collection("shifts")
                .whereField("date", isGreaterThanOrEqualTo: firstKey)
                .whereField("date", isLessThanOrEqualTo: lastKey)
                .getDocuments()
            let lastWeekShifts = lastSnap.documents.compactMap { Shift(id: $0.documentID, data: $0.data()) }
                .filter { $0.status != .cancelled && (staffIDs?.contains($0.staffId) ?? true) }

            guard !lastWeekShifts.isEmpty else {
                toasts.show("No shifts found in the previous week", style: .warning)
                return
            }

            let existingSnap = try await db.collection("shifts")
                .whereField("date", isGreaterThanOrEqualTo: RosterCalendar.dateString(from: RosterCalendar.addDays(-1, to: monday)))
                .whereField("date", isLessThanOrEqualTo: RosterCalendar.dateString(from: RosterCalendar.addDays(7, to: monday)))
                .getDocuments()
            let existing = existingSnap.documents.compactMap { Shift(id: $0.documentID, data: $0.data()) }
                .filter { $0.status != .cancelled }
            let plan = MacRosterCopyPlan(source: lastWeekShifts, existing: existing, staffIDs: staffIDs)

            var created = 0
            let skipped = plan.skipped
            var failed = 0
            for old in plan.drafts {
                do {
                    try await repo.saveShift(
                    id: nil,
                    staffId: old.staffId,
                    date: old.date,
                    start: old.rosteredStart,
                    end: old.rosteredEnd,
                    breakMinutes: old.breakMinutes,
                    location: old.location,
                    department: old.department,
                    notes: old.notes,
                    status: .draft
                )
                    created += 1
                } catch {
                    failed += 1
                }
            }

            if failed == 0 { activeSheet = nil }
            toasts.show("Copied \(created) drafts · \(skipped) duplicates or conflicts skipped · \(failed) failed\(failed > 0 ? ". Retry to copy remaining shifts." : "")", style: failed > 0 ? .warning : .success)
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }
}

// MARK: - Supporting types

/// Pure planning logic shared by the copy preview and commit path.
struct MacRosterCopyPlan {
    let drafts: [Shift]
    let skipped: Int

    static func canDrag(_ shift: Shift) -> Bool { shift.status == .draft }

    init(source: [Shift], existing: [Shift], staffIDs: Set<String>?) {
        var result: [Shift] = []
        var skippedCount = 0
        for sourceShift in source.sorted(by: { $0.id < $1.id }) {
            guard sourceShift.status != .cancelled,
                  staffIDs?.contains(sourceShift.staffId) ?? true else { continue }
            guard let date = RosterCalendar.dateFromKey(sourceShift.date) else {
                skippedCount += 1
                continue
            }
            var draft = sourceShift
            draft.date = RosterCalendar.dateString(from: RosterCalendar.addDays(7, to: date))
            draft.status = .draft
            draft.shiftStartAt = nil
            draft.submittableAfter = nil
            let overlaps = (existing + result).contains { other in
                guard other.status != .cancelled, other.staffId == draft.staffId else { return false }
                let start = BusinessRules.shiftStartDateTime(date: draft.date, time: draft.rosteredStart)
                let end = BusinessRules.shiftEndDateTime(date: draft.date, start: draft.rosteredStart, end: draft.rosteredEnd)
                let otherStart = BusinessRules.shiftStartDateTime(date: other.date, time: other.rosteredStart)
                let otherEnd = BusinessRules.shiftEndDateTime(date: other.date, start: other.rosteredStart, end: other.rosteredEnd)
                return start < otherEnd && otherStart < end
            }
            if overlaps { skippedCount += 1 }
            else { result.append(draft) }
        }
        drafts = result
        skipped = skippedCount
    }
}

private enum MacRosterViewMode: String, CaseIterable, Identifiable {
    case week, day, staff

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private enum MacRosterStatusFilter: String, CaseIterable, Identifiable {
    case all
    case draft
    case published
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All statuses"
        case .draft: return "Draft"
        case .published: return "Published"
        case .cancelled: return "Cancelled"
        }
    }

    func matches(_ status: ShiftStatus) -> Bool {
        switch self {
        case .all: return true
        case .draft: return status == .draft
        case .published: return status == .published
        case .cancelled: return status == .cancelled
        }
    }
}

private enum MacRosterSheet: Identifiable {
    case create(date: String, staffId: String?)
    case edit(Shift)
    case publish
    case copyWeek
    case drop(shift: Shift, targetDate: String)

    var id: String {
        switch self {
        case .create(let date, let staffId): return "create-\(date)-\(staffId ?? "none")"
        case .edit(let shift): return "edit-\(shift.id)"
        case .publish: return "publish"
        case .copyWeek: return "copy-week"
        case .drop(let shift, let targetDate): return "drop-\(shift.id)-\(targetDate)"
        }
    }
}

private enum MacRosterShiftOverlap {
    static func overlaps(_ first: Shift, _ second: Shift) -> Bool {
        func minutes(_ hhmm: String) -> Int {
            let parts = hhmm.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else { return 0 }
            return parts[0] * 60 + parts[1]
        }

        let firstStart = minutes(first.rosteredStart)
        var firstEnd = minutes(first.rosteredEnd)
        let secondStart = minutes(second.rosteredStart)
        var secondEnd = minutes(second.rosteredEnd)
        if firstEnd <= firstStart { firstEnd += 24 * 60 }
        if secondEnd <= secondStart { secondEnd += 24 * 60 }
        return firstStart < secondEnd && secondStart < firstEnd
    }
}

private enum MacRosterFormatting {
    static func aud(_ value: Double) -> String {
        value.formatted(.currency(code: "AUD").locale(Locale(identifier: "en_AU")))
    }

    static func firstName(of user: AppUser?) -> String {
        user?.firstName ?? "Staff"
    }
}

// MARK: - Budget KPI

private struct MacRosterBudgetCard: View {
    let gross: String
    let superannuation: String
    let total: String
    let missingNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: MacSpace.sm) {
                Text("Weekly Budget Forecast")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer(minLength: 0)
                Image(systemName: "banknote.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacColor.success)
                    .frame(width: 28, height: 28)
                    .background(MacColor.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    budgetMetric("Gross", value: gross)
                    budgetDivider
                    budgetMetric("Super", value: superannuation)
                    budgetDivider
                    budgetMetric("Total", value: total, emphasized: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    budgetRow("Gross", value: gross)
                    budgetRow("Super", value: superannuation)
                    budgetRow("Total", value: total, emphasized: true)
                }
            }

            Text("Labour cost this week (AUD)")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)

            if !missingNames.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Missing rate: \(missingNames.joined(separator: ", "))")
                        .lineLimit(2)
                }
                .font(MacType.badge)
                .foregroundStyle(MacColor.error)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
    }

    private func budgetMetric(_ label: String, value: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(emphasized ? MacColor.success : MacColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func budgetRow(_ label: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(emphasized ? MacColor.success : MacColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var budgetDivider: some View {
        Rectangle()
            .fill(MacColor.separator)
            .frame(width: 1, height: 32)
            .padding(.horizontal, MacSpace.sm)
    }
}

// MARK: - Week view

private struct MacRosterWeekView: View {
    let weekDays: [Date]
    let shiftsByDate: [String: [Shift]]
    let dragOverDate: String?
    let canDragShift: (Shift) -> Bool
    let onCreate: (String) -> Void
    let onEdit: (Shift) -> Void
    let onDelete: (Shift) -> Void
    let onDrop: (String, String) -> Void
    let onDragTargetChange: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    dayHeader(day)
                }
            }
            .overlay(Rectangle().fill(MacColor.separator).frame(height: 1), alignment: .bottom)

            HStack(alignment: .top, spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    dayColumn(day)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
    }

    private func dayHeader(_ day: Date) -> some View {
        let key = RosterCalendar.dateString(from: day)
        let isToday = key == RosterCalendar.todayKey()
        let count = shiftsByDate[key]?.count ?? 0

        return VStack(spacing: 4) {
            Text(RosterCalendar.dayOfWeek(from: day).uppercased())
                .font(MacType.captionStrong)
                .foregroundStyle(isToday ? MacColor.accent : MacColor.textTertiary)
            Text(RosterCalendar.dayOfMonth(from: day))
                .font(MacType.bodyStrong)
                .foregroundStyle(isToday ? MacColor.accent : MacColor.textPrimary)
            HStack(spacing: 6) {
                if count > 0 {
                    Text("\(count)")
                        .font(MacType.badge)
                        .foregroundStyle(isToday ? MacColor.accent : MacColor.textTertiary)
                }
                Button {
                    onCreate(key)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MacColor.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(MacColor.sidebarHover, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Add shift on \(RosterFormat.dateShort(key))")
            }
        }
        .padding(.vertical, MacSpace.md)
        .frame(maxWidth: .infinity)
        .background(isToday ? MacColor.accent.opacity(0.08) : MacColor.tableHeaderBackground)
        .overlay(Rectangle().fill(MacColor.separator.opacity(0.45)).frame(width: 1), alignment: .trailing)
    }

    private func dayColumn(_ day: Date) -> some View {
        let key = RosterCalendar.dateString(from: day)
        let isToday = key == RosterCalendar.todayKey()
        let isDropTarget = dragOverDate == key
        let shifts = shiftsByDate[key] ?? []

        return VStack(spacing: 8) {
            if shifts.isEmpty {
                Text("No shifts")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                    .padding(.top, MacSpace.sm)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(shifts) { shift in
                    MacRosterWeekShiftCard(
                        shift: shift,
                        canDrag: canDragShift(shift),
                        onEdit: { onEdit(shift) },
                        onDelete: { onDelete(shift) }
                    )
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .top)
        .background(
            isDropTarget
                ? MacColor.accent.opacity(0.10)
                : (isToday ? MacColor.accent.opacity(0.04) : Color.clear)
        )
        .overlay(Rectangle().fill(MacColor.separator.opacity(0.3)).frame(width: 1), alignment: .trailing)
        .overlay {
            if isDropTarget {
                Rectangle()
                    .strokeBorder(MacColor.accent.opacity(0.45), lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let shiftId = items.first else { return false }
            onDrop(shiftId, key)
            return true
        } isTargeted: { targeted in
            onDragTargetChange(key, targeted)
        }
    }
}

private struct MacRosterWeekShiftCard: View {
    @Environment(RosterRepository.self) private var repo
    let shift: Shift
    let canDrag: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    /// Fixed card height so Approved / Pending / Draft badges don't change size.
    private static let cardHeight: CGFloat = 92
    private static let badgeRowHeight: CGFloat = 18

    var body: some View {
        let staff = repo.user(id: shift.staffId)
        let timesheet = repo.timesheet(forShift: shift.id)
        let colors = MacRosterShiftStyle.colors(shiftStatus: shift.status, timesheetStatus: timesheet?.status)
        let name = staff?.fullName ?? "Staff member"

        let card = VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(name)
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)
                if canDrag {
                    Spacer(minLength: 0)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MacColor.textTertiary)
                } else {
                    Spacer(minLength: 0)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(MacColor.textSecondary)
                }
            }

            Text("\(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))")
                .font(MacType.mono)
                .foregroundStyle(MacColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)

            HStack(alignment: .center, spacing: 6) {
                Text(RosterFormat.hours(shift.scheduledHours))
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                Spacer(minLength: 0)
                statusBadge(timesheet: timesheet, colors: colors)
            }
            .frame(height: Self.badgeRowHeight, alignment: .center)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: Self.cardHeight, maxHeight: Self.cardHeight, alignment: .topLeading)
        .background(hovering ? MacColor.tableRowHover : MacColor.cardBackground, in: RoundedRectangle(cornerRadius: MacRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.small, style: .continuous)
                .strokeBorder(hovering ? MacColor.accent : MacColor.cardBorder, style: StrokeStyle(lineWidth: 1, dash: canDrag ? [4, 3] : []))
        )
        .contentShape(RoundedRectangle(cornerRadius: MacRadius.small, style: .continuous))

        return Button(action: onEdit) { card }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .macDraggableIf(canDrag, shift.id)
            .contextMenu {
                Button("Edit Shift", action: onEdit)
                Button("Delete Shift", role: .destructive, action: onDelete)
            }
            .help(
                canDrag
                    ? "Drag to another day to move or copy · \(staff?.fullName ?? name)"
                    : "Locked in place · \(staff?.fullName ?? name)"
            )
    }

    @ViewBuilder
    private func statusBadge(
        timesheet: Timesheet?,
        colors: (background: Color, border: Color, badge: Color)
    ) -> some View {
        if let timesheet {
            Text(MacStatusStyle.forTimesheet(timesheet.status).label)
                .font(MacType.badge)
                .foregroundStyle(colors.badge)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(colors.badge.opacity(0.16), in: Capsule())
        } else if shift.status == .draft {
            Text("Draft")
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MacColor.textTertiary.opacity(0.12), in: Capsule())
        } else if shift.status == .cancelled {
            Text("Cancelled")
                .font(MacType.badge)
                .foregroundStyle(MacColor.error)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MacColor.error.opacity(0.12), in: Capsule())
        } else {
            // Invisible placeholder keeps height identical when no badge is shown.
            Text("Approved")
                .font(MacType.badge)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .hidden()
                .accessibilityHidden(true)
        }
    }
}

private enum MacRosterShiftStyle {
    static func colors(shiftStatus: ShiftStatus, timesheetStatus: TimesheetStatus?) -> (background: Color, border: Color, badge: Color) {
        if let timesheetStatus {
            switch timesheetStatus {
            case .approved:
                return (MacColor.success.opacity(0.12), MacColor.success.opacity(0.35), MacColor.success)
            case .pending:
                return (MacColor.warning.opacity(0.12), MacColor.warning.opacity(0.35), MacColor.warning)
            case .rejected, .absent, .absentReported:
                return (MacColor.error.opacity(0.10), MacColor.error.opacity(0.30), MacColor.error)
            case .draft:
                break
            }
        }
        switch shiftStatus {
        case .draft:
            return (MacColor.textTertiary.opacity(0.12), MacColor.cardBorder, MacColor.textTertiary)
        case .published, .completed:
            return (MacColor.accent.opacity(0.12), MacColor.accent.opacity(0.30), MacColor.accent)
        case .cancelled:
            return (MacColor.error.opacity(0.08), MacColor.error.opacity(0.22), MacColor.error)
        }
    }
}

// MARK: - Staff view

private struct MacRosterStaffView: View {
    @Environment(RosterRepository.self) private var repo

    let weekDays: [Date]
    let staff: [AppUser]
    let shiftsByStaff: [String: [Shift]]
    let weekStartKey: String
    let onCreate: (String, String) -> Void
    let onEdit: (Shift) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("STAFF", width: 200, alignment: .leading)
                ForEach(weekDays, id: \.self) { day in
                    let key = RosterCalendar.dateString(from: day)
                    let isToday = key == RosterCalendar.todayKey()
                    VStack(spacing: 2) {
                        Text(RosterCalendar.dayOfWeek(from: day).uppercased())
                            .font(MacType.captionStrong)
                            .foregroundStyle(isToday ? MacColor.accent : MacColor.textTertiary)
                        Text(RosterCalendar.dayOfMonth(from: day))
                            .font(MacType.caption)
                            .foregroundStyle(isToday ? MacColor.accent : MacColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MacSpace.sm)
                }
                headerCell("HOURS", width: 88, alignment: .trailing)
                headerCell("COST", width: 100, alignment: .trailing)
            }
            .background(MacColor.tableHeaderBackground)
            .overlay(Rectangle().fill(MacColor.separator).frame(height: 1), alignment: .bottom)

            ForEach(staff) { member in
                staffRow(member)
            }
        }
        .frame(maxWidth: .infinity)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
    }

    private func headerCell(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title)
            .font(MacType.captionStrong)
            .foregroundStyle(MacColor.textTertiary)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, MacSpace.sm)
            .padding(.vertical, MacSpace.sm)
    }

    private func staffRow(_ member: AppUser) -> some View {
        let shifts = shiftsByStaff[member.id] ?? []
        let shiftByDate = Dictionary(shifts.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let total = shifts.reduce(0.0) { $0 + $1.scheduledHours }
        let cost = shifts.reduce(0.0) { sum, shift in
            sum + shift.scheduledHours * repo.liveHourlyRate(forStaffId: member.id, shiftDateKey: shift.date)
        }
        let displayRate = repo.liveHourlyRate(forStaffId: member.id, shiftDateKey: weekStartKey)

        return HStack(spacing: 0) {
            HStack(spacing: MacSpace.sm) {
                MacRosterAvatar(name: member.fullName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.fullName)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(1)
                    if displayRate > 0 {
                        Text(String(format: "$%.2f/hr (%@)", displayRate, member.employmentType == .casual ? "Casual" : "Perm"))
                            .font(MacType.badge)
                            .foregroundStyle(MacColor.textTertiary)
                    } else {
                        Text("No rate set")
                            .font(MacType.badge)
                            .foregroundStyle(MacColor.error)
                    }
                }
            }
            .padding(.horizontal, MacSpace.md)
            .padding(.vertical, MacSpace.sm)
            .frame(width: 200, alignment: .leading)

            ForEach(weekDays, id: \.self) { day in
                let key = RosterCalendar.dateString(from: day)
                Group {
                    if let shift = shiftByDate[key] {
                        Button {
                            onEdit(shift)
                        } label: {
                            VStack(spacing: 2) {
                                Text(RosterFormat.time(shift.rosteredStart))
                                    .font(MacType.mono)
                                    .foregroundStyle(MacColor.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(RosterFormat.hours(shift.scheduledHours))
                                    .font(MacType.caption)
                                    .foregroundStyle(MacColor.textSecondary)
                            }
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                (shift.status == .draft ? MacColor.textTertiary.opacity(0.12) : MacColor.accent.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: MacRadius.small, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            onCreate(key, member.id)
                        } label: {
                            Text("+")
                                .font(MacType.bodyStrong)
                                .foregroundStyle(MacColor.textTertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: MacRadius.small, style: .continuous)
                                        .strokeBorder(MacColor.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
            }

            Text(total > 0 ? RosterFormat.hours(total) : "—")
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 88, alignment: .trailing)
                .padding(.horizontal, MacSpace.sm)

            Group {
                if total > 0 && cost > 0 {
                    Text(MacRosterFormatting.aud(cost))
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.success)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else if total > 0 {
                    Text("No rate")
                        .font(MacType.captionStrong)
                        .foregroundStyle(MacColor.error)
                } else {
                    Text("—")
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textTertiary)
                }
            }
            .frame(width: 100, alignment: .trailing)
            .padding(.horizontal, MacSpace.sm)
        }
        .overlay(Rectangle().fill(MacColor.separator.opacity(0.5)).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Day view

private struct MacRosterDayView: View {
    @Environment(RosterRepository.self) private var repo

    let weekDays: [Date]
    let shiftsByDate: [String: [Shift]]
    let onCreate: (String) -> Void
    let onEdit: (Shift) -> Void
    let onDelete: (Shift) -> Void

    var body: some View {
        VStack(spacing: MacSpace.md) {
            ForEach(weekDays, id: \.self) { day in
                let key = RosterCalendar.dateString(from: day)
                let isToday = key == RosterCalendar.todayKey()
                let dayShifts = shiftsByDate[key] ?? []

                VStack(alignment: .leading, spacing: MacSpace.md) {
                    HStack {
                        Text("\(RosterCalendar.dayOfWeek(from: day)), \(RosterFormat.dateShort(key))")
                            .font(MacType.sectionHeader)
                            .foregroundStyle(isToday ? MacColor.accent : MacColor.textPrimary)
                        if isToday {
                            Text("Today")
                                .font(MacType.badge)
                                .foregroundStyle(MacColor.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MacColor.accent.opacity(0.14), in: Capsule())
                        }
                        Spacer()
                        Button {
                            onCreate(key)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add")
                            }
                        }
                        .macButton(.ghost, size: .small)
                    }

                    if dayShifts.isEmpty {
                        Text("No shifts")
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textTertiary)
                            .padding(.vertical, MacSpace.sm)
                    } else {
                        VStack(spacing: MacSpace.sm) {
                            ForEach(dayShifts) { shift in
                                let staff = repo.user(id: shift.staffId)
                                let timesheet = repo.timesheet(forShift: shift.id)
                                HStack(spacing: MacSpace.md) {
                                    Button {
                                        onEdit(shift)
                                    } label: {
                                        HStack(spacing: MacSpace.md) {
                                            MacAvatar(name: staff?.fullName ?? "?", size: 32)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(staff?.fullName ?? "Staff member")
                                                    .font(MacType.bodyStrong)
                                                    .foregroundStyle(MacColor.textPrimary)
                                                Text("\(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd)) · \(RosterFormat.hours(shift.scheduledHours))")
                                                    .font(MacType.caption)
                                                    .foregroundStyle(MacColor.textSecondary)
                                            }
                                            Spacer()
                                            if let timesheet {
                                                MacStatusPill(timesheetStatus: timesheet.status)
                                            } else {
                                                MacStatusPill(
                                                    text: shift.status.rawValue.capitalized,
                                                    foreground: shift.status == .draft ? MacColor.textSecondary : MacColor.accent,
                                                    background: (shift.status == .draft ? MacColor.textTertiary : MacColor.accent).opacity(0.12),
                                                    border: (shift.status == .draft ? MacColor.cardBorder : MacColor.accent.opacity(0.3))
                                                )
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        onDelete(shift)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(MacColor.error)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete shift")
                                }
                                .padding(MacSpace.md)
                                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
                                .contextMenu {
                                    Button("Edit Shift") { onEdit(shift) }
                                    Button("Delete Shift", role: .destructive) { onDelete(shift) }
                                }
                            }
                        }
                    }
                }
                .padding(MacSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacColor.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                        .strokeBorder(isToday ? MacColor.accent.opacity(0.35) : MacColor.cardBorder, lineWidth: 1)
                )
            }
        }
    }
}

private struct MacRosterAvatar: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(MacType.badge)
            .foregroundStyle(MacColor.accent)
            .frame(width: 28, height: 28)
            .background(MacColor.accent.opacity(0.14), in: Circle())
    }
}

// MARK: - Publish confirm

private struct MacRosterCopyWeekSheet: View {
    let staff: [AppUser]
    let destination: String
    let monday: Date
    let onCancel: () -> Void
    let onCopy: (Set<String>?) async -> Void
    @State private var allStaff = true
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var isCopying = false
    @State private var source: [Shift] = []
    @State private var existing: [Shift] = []
    @State private var loading = true
    @State private var loadError: String?

    private var plan: MacRosterCopyPlan {
        MacRosterCopyPlan(source: source, existing: existing, staffIDs: allStaff ? nil : selected)
    }

    private var matchingStaff: [AppUser] {
        staff.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            Text("Copy last week")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(MacColor.textPrimary)
            Text("Create drafts for \(destination)")
                .font(MacType.body)
                .foregroundStyle(MacColor.textSecondary)
            Picker("Staff to copy", selection: $allStaff) {
                Text("All staff").tag(true)
                Text("Selected staff").tag(false)
            }
            .pickerStyle(.segmented)

            if !allStaff {
                TextField("Search staff", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search staff to copy")
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matchingStaff) { person in
                            Button {
                                if selected.contains(person.id) { selected.remove(person.id) }
                                else { selected.insert(person.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(person.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selected.contains(person.id) ? MacColor.accent : MacColor.textSecondary)
                                    Text(person.fullName).font(MacType.body)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(selected.contains(person.id) ? "Selected" : "Not selected")
                            .padding(.vertical, MacSpace.sm)
                            Divider()
                        }
                        if matchingStaff.isEmpty {
                            Text("No matching staff")
                                .foregroundStyle(MacColor.textSecondary)
                                .padding()
                        }
                    }
                }
                .frame(height: 220)
                Text("\(selected.count) staff selected")
                    .font(MacType.caption)
            }

            Label("Existing shifts stay unchanged. Duplicates and overlapping shifts are skipped; new shifts are drafts.", systemImage: "doc.on.doc")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if loading {
                ProgressView("Checking last week's roster…")
            } else if let loadError {
                Text(loadError).foregroundStyle(MacColor.error)
                Button("Try again") { Task { await loadPreview() } }
            } else {
                Text("\(plan.drafts.count) drafts to create · \(plan.skipped) duplicates or conflicts to skip")
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
            }
            HStack {
                Button("Cancel", action: onCancel)
                    .macButton(.bordered)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    isCopying = true
                    Task {
                        await onCopy(allStaff ? nil : selected)
                        await loadPreview()
                        isCopying = false
                    }
                } label: {
                    HStack {
                        if isCopying { ProgressView().controlSize(.small) }
                        Text(isCopying ? "Copying…" : "Copy as drafts")
                    }
                }
                .macButton(.prominent)
                .keyboardShortcut(.defaultAction)
                .disabled(loading || loadError != nil || plan.drafts.isEmpty || (!allStaff && selected.isEmpty))
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 480)
        .disabled(isCopying)
        .interactiveDismissDisabled(isCopying)
        .task { await loadPreview() }
    }

    @MainActor
    private func loadPreview() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let start = RosterCalendar.dateString(from: RosterCalendar.addDays(-8, to: monday))
            let end = RosterCalendar.dateString(from: RosterCalendar.addDays(7, to: monday))
            let snapshot = try await Firestore.firestore().collection("shifts")
                .whereField("date", isGreaterThanOrEqualTo: start)
                .whereField("date", isLessThanOrEqualTo: end)
                .getDocuments()
            let shifts = snapshot.documents.compactMap { Shift(id: $0.documentID, data: $0.data()) }
            let previousStart = RosterCalendar.dateString(from: RosterCalendar.addDays(-7, to: monday))
            let currentStart = RosterCalendar.dateString(from: monday)
            source = shifts.filter { $0.date >= previousStart && $0.date < currentStart }
            // Include adjacent dates so overnight overlaps are visible.
            existing = shifts.filter { $0.date >= RosterCalendar.dateString(from: RosterCalendar.addDays(-1, to: monday)) }
        } catch {
            loadError = "Unable to load the copy preview. \(error.localizedDescription)"
        }
    }
}

private struct MacRosterPublishSheet: View {
    let draftCount: Int
    let onCancel: () -> Void
    let onPublish: (Bool) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack {
                Text("Publish Roster")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundStyle(MacColor.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("Publish \(draftCount) draft shift\(draftCount == 1 ? "" : "s")? Staff will be able to see these shifts immediately.")
                .font(MacType.body)
                .foregroundStyle(MacColor.textSecondary)

            Text("Publish & Lock also freezes staff availability for this roster week, so the published roster can't drift out of sync. You can unlock the week later from the roster toolbar.")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .macButton(.bordered)
                MacAsyncButton(variant: .prominent) {
                    await onPublish(false)
                } label: {
                    Text("Publish Only")
                }
                MacAsyncButton(variant: .success) {
                    await onPublish(true)
                } label: {
                    Text("Publish & Lock")
                }
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 480)
    }
}

private struct MacRosterDropSheet: View {
    @Environment(RosterRepository.self) private var repo

    let shift: Shift
    let targetDate: String
    let onCancel: () -> Void
    let onMove: () async -> Void
    let onCopy: () async -> Void

    var body: some View {
        let staff = repo.user(id: shift.staffId)?.fullName ?? "Staff"
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack {
                Text("Move or copy shift?")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundStyle(MacColor.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("Choose whether to move this shift to the selected day or copy it.")
                .font(MacType.body)
                .foregroundStyle(MacColor.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(staff)")
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
                Text("\(RosterFormat.dateShort(shift.date)) → \(RosterFormat.dateShort(targetDate))")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textSecondary)
                Text("\(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))")
                    .font(MacType.mono)
                    .foregroundStyle(MacColor.textTertiary)
            }
            .padding(MacSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .macButton(.bordered)
                MacAsyncButton(variant: .secondary) {
                    await onCopy()
                } label: {
                    Text("Copy shift")
                }
                MacAsyncButton(variant: .prominent) {
                    await onMove()
                } label: {
                    Text("Move shift")
                }
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 440)
    }
}

private extension View {
    @ViewBuilder
    func rosterToolbarGlassPill() -> some View {
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

    @ViewBuilder
    func macDraggableIf<T: Transferable>(_ condition: Bool, _ payload: T) -> some View {
        if condition {
            self.draggable(payload)
        } else {
            self
        }
    }
}
#endif
