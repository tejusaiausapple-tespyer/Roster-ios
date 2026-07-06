import SwiftUI
import FirebaseFirestore

// Layout mode is driven by the *measured container width* rather than size class
// alone, because iPad Split View / Slide Over report `.compact` just like an
// iPhone. This keeps the experience smooth across iPad fullscreen, portrait,
// Split View, Slide Over, and resized Mac windows.
private enum RosterLayoutMode {
    case agenda    // narrow: single-day list + week selector (the iPhone design)
    case weekGrid  // wide: 7-day scheduler grid
}

struct ManagerRosterView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var weekOffset = 0
    @State private var selectedDayKey = RosterCalendar.todayKey()
    @State private var activeSheet: ActiveSheet? = nil
    @State private var showNoStaffAlert = false
    @State private var toast: ToastMessage?
    /// In-flight guard: a second tap on Copy Last Week would duplicate the
    /// entire week's shifts.
    @State private var isCopyingWeek = false
    @State private var showPublishDialog = false
    /// Single shift awaiting the Publish Only / Publish & Lock choice.
    @State private var pendingPublishShift: Shift? = nil

    /// A single sheet source of truth. Using two separate `.sheet` modifiers on
    /// one view causes SwiftUI to present unreliably (slow / sometimes never,
    /// requiring an app restart), so create + edit share one enum-driven sheet.
    enum ActiveSheet: Identifiable {
        case create(dateKey: String)
        case edit(Shift)

        var id: String {
            switch self {
            case .create(let key): return "create-\(key)"
            case .edit(let shift): return "edit-\(shift.id)"
            }
        }
    }

    // Drag & Drop state
    @State private var dragOverDayKey: String? = nil
    @State private var activeDragDropAction: DragDropAction? = nil

    struct DragDropAction: Identifiable {
        let id = UUID()
        let shift: Shift
        let targetDateKey: String
    }

    // Bulk delete state
    @State private var bulkDeleteRequest: BulkDeleteRequest? = nil

    struct BulkDeleteRequest: Identifiable {
        let id = UUID()
        let staffId: String?   // nil = all staff in the week
        let label: String
        let count: Int
    }

    // Filters state
    /// Staff filter keyed by user id, not display name — names can collide
    /// or change mid-session. nil = all staff.
    @State private var selectedStaffFilterId: String? = nil
    @State private var selectedStatusFilter: String = "All statuses"

    private var hasStaff: Bool { repo.allUsers.contains { $0.role == .staff } }

    private var now: Date { Date() }
    private var bounds: (min: Int, max: Int) { BusinessRules.shiftWeekOffsetBounds(at: now) }
    private var monday: Date { RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(now)) }
    private var weekDays: [Date] { RosterCalendar.weekDays(for: monday) }
    private var weekKeys: [String] { weekDays.map { RosterCalendar.dayFormatter.string(from: $0) } }

    private var dateRangeString: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = RosterCalendar.calendar
        formatter.timeZone = RosterCalendar.timeZone
        formatter.dateFormat = "d MMM"
        let yearFormatter = DateFormatter()
        yearFormatter.calendar = RosterCalendar.calendar
        yearFormatter.timeZone = RosterCalendar.timeZone
        yearFormatter.dateFormat = "yyyy"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last)) \(yearFormatter.string(from: last))"
    }

    /// Relative label for the week currently being viewed (drives the center of
    /// the week navigator). Reflects `weekOffset` rather than always "This week".
    private var weekRelativeLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        case let n where n > 1: return "In \(n) weeks"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    /// Default date for the general "Add shift" button: today when today is in
    /// the viewed week, otherwise that week's start (Monday). Per-day "+" buttons
    /// pass their own specific date instead.
    private var defaultNewShiftDateKey: String {
        let today = RosterCalendar.todayKey()
        if weekKeys.contains(today) { return today }
        return weekKeys.first ?? today
    }

    // MARK: - Computed Properties (Filtered Data)

    private var weekShifts: [Shift] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.shifts
            .filter { $0.date >= first && $0.date <= last }
            .filter { filterByStaff($0) }
            .filter { filterByStatus($0) }
            .sorted { ($0.date, $0.rosteredStart) < ($1.date, $1.rosteredStart) }
    }

    private func filterByStaff(_ shift: Shift) -> Bool {
        guard let selectedStaffFilterId else { return true }
        return shift.staffId == selectedStaffFilterId
    }

    private func filterByStatus(_ shift: Shift) -> Bool {
        if selectedStatusFilter == "All statuses" { return true }
        let hasTimesheet = repo.timesheets.first(where: { $0.shiftId == shift.id })

        switch selectedStatusFilter {
        case "Approved":
            return hasTimesheet?.status == .approved
        case "Pending":
            return hasTimesheet?.status == .pending
        case "Drafts":
            return shift.status == .draft
        case "Published":
            return shift.status == .published && hasTimesheet == nil
        default:
            return true
        }
    }

    private func shifts(on key: String) -> [Shift] {
        weekShifts.filter { $0.date == key }
    }

    private var markedKeys: Set<String> {
        Set(weekShifts.map { $0.date })
    }

    private var isStaffFilterActive: Bool { selectedStaffFilterId != nil }

    private var selectedStaffFilterName: String {
        selectedStaffFilterId.flatMap { id in
            repo.user(id: id)?.fullName
        } ?? "All staff"
    }
    private var isStatusFilterActive: Bool { selectedStatusFilter != "All statuses" }

    // MARK: - Roster Metrics Math

    private var totalScheduledHours: Double {
        weekShifts.reduce(0.0) { $0 + $1.scheduledHours }
    }

    private var uniqueStaffCount: Int {
        Set(weekShifts.map { $0.staffId }).count
    }

    private var grossWages: Double {
        weekShifts.reduce(0.0) { sum, shift in
            let rate = repo.user(id: shift.staffId)?.hourlyRate ?? BusinessRules.defaultHourlyRate
            return sum + (shift.scheduledHours * rate)
        }
    }

    private var superannuation: Double {
        // Per-staff super where set, otherwise the SG default (12%).
        weekShifts.reduce(0.0) { sum, shift in
            let user = repo.user(id: shift.staffId)
            let rate = user?.hourlyRate ?? BusinessRules.defaultHourlyRate
            let superPercent = user?.superRate ?? BusinessRules.defaultSuperRatePercent
            return sum + (shift.scheduledHours * rate * superPercent / 100)
        }
    }

    private var totalLabourCost: Double {
        grossWages + superannuation
    }

    private var weeklyDraftsCount: Int {
        weekShifts.filter { $0.status == .draft }.count
    }

    // MARK: - Bulk delete eligibility

    /// All shifts in the visible week, ignoring the active staff/status filters
    /// (bulk delete operates on the real week contents, not the filtered view).
    private var allWeekShifts: [Shift] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.shifts.filter { $0.date >= first && $0.date <= last }
    }

    private var weekHasPublishedShifts: Bool {
        allWeekShifts.contains { $0.status == .published }
    }

    /// Delete is available for upcoming weeks; for the current week only while it
    /// is not yet published; never for past weeks (they are completed).
    private var canBulkDelete: Bool {
        if weekOffset < 0 { return false }                 // past week — completed
        if weekOffset == 0 { return !weekHasPublishedShifts } // current week — only if not published
        return true                                         // upcoming week
    }

    /// Staff who have at least one shift in the visible week (for per-staff delete).
    private var staffWithShiftsThisWeek: [AppUser] {
        let ids = Set(allWeekShifts.map { $0.staffId })
        return repo.allUsers
            .filter { ids.contains($0.id) }
            .sorted { $0.fullName < $1.fullName }
    }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private func layoutMode(for width: CGFloat) -> RosterLayoutMode {
        // iPhone always uses the agenda list (its design is intentionally kept).
        if isPhone { return .agenda }
        // iPad / Mac: switch on real width so Split View & Slide Over degrade well.
        return width >= 720 ? .weekGrid : .agenda
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let width = proxy.size.width
                let mode = layoutMode(for: width)

                ZStack {
                    switch mode {
                    case .weekGrid:
                        weekGridLayout(containerWidth: width)
                    case .agenda:
                        agendaLayout
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            // Keep the selected day inside the week being viewed: today when
            // viewing the current week, otherwise that week's first day. This
            // makes "Add Shift" default to the displayed week rather than
            // today's date after navigating weeks (a specifically tapped day
            // in the new week is respected, since tapping sets selectedDayKey).
            .onChange(of: weekOffset) { _, _ in
                guard !weekKeys.contains(selectedDayKey) else { return }
                let today = RosterCalendar.todayKey()
                selectedDayKey = weekKeys.contains(today) ? today : (weekKeys.first ?? today)
            }
            .navigationTitle("Roster Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitlePill(title: "Roster Planner", icon: "calendar.circle.fill")
                }
            }
            .confirmationDialog(
                "Manage Shift",
                isPresented: Binding(
                    get: { activeDragDropAction != nil },
                    set: { if !$0 { activeDragDropAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let action = activeDragDropAction {
                    Button("Move shift") {
                        moveShift(action.shift, to: action.targetDateKey)
                    }
                    Button("Copy shift") {
                        copyShift(action.shift, to: action.targetDateKey)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let action = activeDragDropAction {
                    let staff = repo.user(id: action.shift.staffId)?.fullName ?? "Staff"
                    Text("Move or copy \(staff)'s shift to this day?")
                }
            }
            .confirmationDialog(
                "Delete shifts",
                isPresented: Binding(
                    get: { bulkDeleteRequest != nil },
                    set: { if !$0 { bulkDeleteRequest = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let req = bulkDeleteRequest {
                    Button("Delete \(req.count) shift\(req.count == 1 ? "" : "s")", role: .destructive) {
                        performBulkDelete(req)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let req = bulkDeleteRequest {
                    Text("This permanently deletes \(req.label) for the week of \(dateRangeString). This cannot be undone.")
                }
            }
            .confirmationDialog(
                "Publish Roster",
                isPresented: $showPublishDialog,
                titleVisibility: .visible
            ) {
                Button("Publish Only") { publishWeeklyDrafts(lockWeek: false) }
                Button("Publish & Lock Availability") { publishWeeklyDrafts(lockWeek: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Publish \(weeklyDraftsCount) draft shift\(weeklyDraftsCount == 1 ? "" : "s")? \"Publish & Lock\" also freezes staff availability for this week so the published roster can't drift out of sync. You can unlock later from the ⋯ menu.")
            }
            .confirmationDialog(
                "Publish Shift",
                isPresented: Binding(
                    get: { pendingPublishShift != nil },
                    set: { if !$0 { pendingPublishShift = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let shift = pendingPublishShift {
                    Button("Publish Only") { publishSingleShift(shift, lockWeek: false) }
                    Button("Publish & Lock Availability") { publishSingleShift(shift, lockWeek: true) }
                }
                Button("Cancel", role: .cancel) { pendingPublishShift = nil }
            } message: {
                Text("\"Publish & Lock\" also freezes staff availability for that shift's week. You can unlock later from the ⋯ menu.")
            }
        }
        // Sheet is attached to the NavigationStack (a stable view) rather than
        // the GeometryReader, and kept separate from the confirmationDialogs, so
        // it presents reliably (a .sheet on a GeometryReader can fail to open).
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create(let dateKey):
                ManagerShiftEditorSheet(defaultDateKey: dateKey)
            case .edit(let shift):
                ManagerShiftEditorSheet(shift: shift, defaultDateKey: selectedDayKey)
            }
        }
        .alert("No staff members available", isPresented: $showNoStaffAlert) {
            Button("OK", role: .cancel) { showNoStaffAlert = false }
        } message: {
            Text("No staff members are available. Please add staff before creating shifts.")
        }
        .toast($toast)
    }

    // MARK: - iPad / macOS Week-Grid Layout

    private func weekGridLayout(containerWidth: CGFloat) -> some View {
        let compactControls = containerWidth < 980

        return VStack(spacing: 0) {
            controlBar(compact: compactControls)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)

            weekGrid(containerWidth: containerWidth)
        }
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            metricsBar
        }
    }

    // MARK: Control bar (glass, width-driven reflow)

    @ViewBuilder
    private func controlBar(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    weekNavCluster
                    dateRangeLabel
                    Spacer(minLength: 8)
                    addShiftButton
                }
                HStack(spacing: 10) {
                    deleteMenu
                    staffFilterChip
                    statusFilterChip
                    Spacer(minLength: 8)
                    moreMenu
                }
            }
        } else {
            HStack(spacing: 16) {
                weekNavCluster
                dateRangeLabel
                Spacer(minLength: 12)
                deleteMenu
                staffFilterChip
                statusFilterChip
                moreMenu
                addShiftButton
            }
        }
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
                selectedDayKey = RosterCalendar.todayKey()
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

    private var dateRangeLabel: some View {
        Text(dateRangeString)
            .font(.headline.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var deleteMenu: some View {
        if canBulkDelete && !allWeekShifts.isEmpty {
            Menu {
                Button(role: .destructive) {
                    requestBulkDelete(staffId: nil)
                } label: {
                    Label("All staff (\(allWeekShifts.count))", systemImage: "trash")
                }

                if !staffWithShiftsThisWeek.isEmpty {
                    Divider()
                    ForEach(staffWithShiftsThisWeek) { staff in
                        let count = allWeekShifts.filter { $0.staffId == staff.id }.count
                        Button(role: .destructive) {
                            requestBulkDelete(staffId: staff.id)
                        } label: {
                            Label("\(staff.fullName) (\(count))", systemImage: "trash")
                        }
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.error)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
                    .glassCapsule(interactive: true)
            }
            .accessibilityLabel("Delete shifts")
        }
    }

    private var staffFilterChip: some View {
        Menu {
            Button("All staff") { selectedStaffFilterId = nil }
            ForEach(repo.allUsers.filter { $0.role == .staff }) { staff in
                Button(staff.fullName) { selectedStaffFilterId = staff.id }
            }
        } label: {
            filterChipLabel(icon: "person.crop.circle", title: "Staff", active: isStaffFilterActive)
        }
        .accessibilityLabel(isStaffFilterActive ? "Staff filter: \(selectedStaffFilterName)" : "Filter by staff")
    }

    private var statusFilterChip: some View {
        Menu {
            Button("All statuses") { selectedStatusFilter = "All statuses" }
            Button("Approved") { selectedStatusFilter = "Approved" }
            Button("Pending") { selectedStatusFilter = "Pending" }
            Button("Drafts") { selectedStatusFilter = "Drafts" }
            Button("Published") { selectedStatusFilter = "Published" }
        } label: {
            filterChipLabel(icon: "line.3.horizontal.decrease.circle", title: "Status", active: isStatusFilterActive)
        }
        .accessibilityLabel(isStatusFilterActive ? "Status filter: \(selectedStatusFilter)" : "Filter by status")
    }

    private func filterChipLabel(icon: String, title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
            if active {
                Circle().fill(Theme.brand).frame(width: 6, height: 6)
            } else {
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(active ? Theme.brand : Theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .glassCapsule(tint: active ? Theme.brand.opacity(0.18) : nil, interactive: true)
    }

    private var moreMenu: some View {
        Menu {
            Button(action: copyLastWeek) {
                Label(isCopyingWeek ? "Copying…" : "Copy Last Week", systemImage: "doc.on.doc")
            }
            .disabled(isCopyingWeek)
            Button { showPublishDialog = true } label: {
                Label("Publish Week (\(weeklyDraftsCount))", systemImage: "paperplane")
            }
            .disabled(weeklyDraftsCount == 0)
            Divider()
            Button(action: toggleWeekAvailabilityLock) {
                Label(isWeekAvailabilityLocked ? "Unlock Staff Availability" : "Lock Staff Availability",
                      systemImage: isWeekAvailabilityLocked ? "lock.open" : "lock")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
                .glassCapsule(interactive: true)
        }
        .accessibilityLabel("More actions")
    }

    private var addShiftButton: some View {
        Button {
            if hasStaff {
                activeSheet = .create(dateKey: defaultNewShiftDateKey)
            } else {
                showNoStaffAlert = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add shift")
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .glassProminentSurface(in: Capsule(style: .continuous), tint: Theme.brandStrong)
        }
        .buttonStyle(.plain)
        .disabled(!hasStaff)
        .accessibilityLabel("Add shift")
    }

    // MARK: Week grid (pinned headers + shared vertical scroll)

    private func weekGrid(containerWidth: CGFloat) -> some View {
        let hPad: CGFloat = 24
        let dividerAllowance: CGFloat = 6 // ~6 hairline dividers between 7 columns
        let available = min(containerWidth, Theme.maxContentWidth) - hPad * 2 - dividerAllowance
        // The 7 day columns always fit the width — no horizontal scrolling.
        let colWidth = available / 7

        let grid = VStack(spacing: 0) {
            // Pinned day-header row (outside the vertical scroll).
            // A fixed height is required: `Divider()` inside an HStack is greedy
            // on the vertical axis and would otherwise stretch this row.
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    dayHeader(index: i).frame(width: colWidth)
                    if i < 6 { Divider().overlay(Theme.separator) }
                }
            }
            .frame(height: 84)

            Divider().overlay(Theme.separator)

            // Shared vertical scroll — all columns scroll together
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayColumn(index: i).frame(width: colWidth)
                        if i < 6 { Divider().overlay(Theme.separator) }
                    }
                }
            }
            .refreshable { await repo.refreshFromServer() }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        )

        return grid
            .padding(.horizontal, hPad)
            .padding(.bottom, 12)
    }

    private func dayHeader(index: Int) -> some View {
        let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayKey = weekKeys[index]
        let isToday = dayKey == RosterCalendar.todayKey()
        let dayNum = RosterCalendar.dateFromKey(dayKey)
            .map { RosterCalendar.calendar.component(.day, from: $0) } ?? 0
        let count = shifts(on: dayKey).count

        return VStack(spacing: 6) {
            Text(weekdayNames[index].uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(isToday ? Theme.brand : Theme.textTertiary)

            HStack(spacing: 8) {
                Text("\(dayNum)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isToday ? .white : Theme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        Group {
                            if isToday { Circle().fill(Theme.brandStrong) }
                        }
                    )

                Button {
                    if hasStaff {
                        activeSheet = .create(dateKey: dayKey)
                    } else {
                        showNoStaffAlert = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.brand)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(!hasStaff)
                .accessibilityLabel("Add shift on \(RosterFormat.date(dayKey))")
            }

            Text(count == 0 ? "—" : "\(count) shift\(count == 1 ? "" : "s")")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func dayColumn(index: Int) -> some View {
        let dayKey = weekKeys[index]
        let dayShifts = shifts(on: dayKey)
        let isTargeted = dragOverDayKey == dayKey

        return VStack(spacing: 10) {
            if dayShifts.isEmpty {
                columnEmptyState(dayKey: dayKey)
            } else {
                ForEach(dayShifts) { shift in
                    gridShiftCard(shift)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
        .background(isTargeted ? Theme.brand.opacity(0.08) : Color.clear)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isTargeted)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let draggedShiftId = items.first else { return false }
            handleShiftDrop(shiftId: draggedShiftId, targetDateKey: dayKey)
            return true
        } isTargeted: { targeted in
            if targeted {
                dragOverDayKey = dayKey
            } else if dragOverDayKey == dayKey {
                dragOverDayKey = nil
            }
        }
    }

    private func columnEmptyState(dayKey: String) -> some View {
        Button {
            if hasStaff {
                activeSheet = .create(dateKey: dayKey)
            } else {
                showNoStaffAlert = true
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
                Text("Add")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Theme.separator)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasStaff)
        .accessibilityLabel("Add shift on \(RosterFormat.date(dayKey))")
    }

    // Shift card — CONTENT layer, deliberately solid (no glass) for legibility.
    private func gridShiftCard(_ shift: Shift) -> some View {
        let staffMember = repo.user(id: shift.staffId)
        let ts = repo.timesheet(forShift: shift.id)

        let displayStatus: StaffShiftDisplayStatus = {
            if shift.status == .draft { return .draft }
            if let ts = ts {
                return StaffShiftDisplayStatus(rawValue: ts.status.rawValue) ?? .pending
            }
            return .scheduled
        }()

        let style = Theme.style(for: displayStatus)
        let isDraft = shift.status == .draft
        let isApproved = ts?.status == .approved

        return Button {
            activeSheet = .edit(shift)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(staffMember?.initials ?? "?")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(style.tint)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(style.soft))

                    Text(staffMember?.fullName ?? "Staff Member")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(shift.rosteredStart + " - " + shift.rosteredEnd)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)

                    if let dept = shift.department, !dept.isEmpty {
                        Text(dept.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                HStack {
                    Text(String(format: "%.1fh", shift.scheduledHours))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Circle()
                        .fill(style.tint)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .fill(isApproved ? Theme.accent.opacity(0.06) : Theme.background)
            )
            .overlay(
                Group {
                    if isDraft {
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(style.tint.opacity(0.6))
                    } else {
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .strokeBorder(style.tint.opacity(0.3), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        // Only draft shifts can be dragged (moved/copied). Once a shift is
        // published it is locked in place — but new shifts can still be added.
        .draggableIf(isDraft, shift.id)
        .contextMenu {
            Button {
                activeSheet = .edit(shift)
            } label: {
                Label("Edit Shift", systemImage: "pencil")
            }

            if isDraft {
                Button {
                    pendingPublishShift = shift
                } label: {
                    Label("Publish Shift", systemImage: "paperplane")
                }
            }

            Button(role: .destructive) {
                deleteShift(shift)
            } label: {
                Label("Delete Shift", systemImage: "trash")
            }
        }
    }

    // MARK: Bottom metrics bar (glass, wrapping)

    private var metricsBar: some View {
        let chips = HStack(spacing: 16) {
            metricChip(icon: "clock", text: String(format: "%.0f hrs", totalScheduledHours))
            metricChip(icon: "person.2", text: "\(uniqueStaffCount) staff")
            metricChip(icon: "doc.badge.ellipsis",
                       text: "\(weeklyDraftsCount) draft\(weeklyDraftsCount == 1 ? "" : "s")",
                       tint: weeklyDraftsCount > 0 ? Theme.warning : Theme.textPrimary)
            metricChip(icon: "dollarsign.circle", text: "Gross $\(String(format: "%.0f", grossWages))")
            metricChip(icon: "chart.bar", text: "Total $\(String(format: "%.0f", totalLabourCost)) inc. Super")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)

        return ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal, showsIndicators: false) { chips }
        }
        .glassCapsule()
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private func metricChip(icon: String, text: String, tint: Color = Theme.textPrimary) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: - iPhone / Agenda Layout (unchanged design)

    private var agendaLayout: some View {
        ZStack {
            VStack(spacing: 0) {
                headerSection

                ScrollView {
                    VStack(spacing: 12) {
                        let dayShifts = shifts(on: selectedDayKey)

                        if dayShifts.isEmpty {
                            emptyStateCard
                        } else {
                            ForEach(dayShifts) { shift in
                                shiftCardRow(shift)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }
                .refreshable {
                    await repo.refreshFromServer()
                }
            }
            createShiftFAB
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Stats Row
            HStack(spacing: 10) {
                miniStatCard(value: "\(weekShifts.count)", label: "Weekly Shifts")
                miniStatCard(value: String(format: "%.1fh", totalScheduledHours), label: "Weekly Hours")
                miniStatCard(value: "\(weeklyDraftsCount)", label: "Draft Shifts", tint: Theme.warning)
            }
            .padding(.horizontal, Theme.screenPadding)

            // Week Selector component
            WeekSelector(
                monday: monday,
                selectedKey: $selectedDayKey,
                markedKeys: markedKeys,
                canGoPrev: weekOffset > bounds.min,
                canGoNext: weekOffset < bounds.max,
                onPrev: { if weekOffset > bounds.min { weekOffset -= 1 } },
                onNext: { if weekOffset < bounds.max { weekOffset += 1 } },
                onToday: { weekOffset = 0; selectedDayKey = RosterCalendar.todayKey() },
                onSelect: { key in selectedDayKey = key }
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
            .padding(.horizontal, Theme.screenPadding)
        }
        .padding(.vertical, 10)
        .background(Theme.card)
    }

    private func miniStatCard(value: String, label: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.background))
    }

    private func shiftCardRow(_ shift: Shift) -> some View {
        let staffMember = repo.user(id: shift.staffId)
        let ts = repo.timesheet(forShift: shift.id)

        let displayStatus: StaffShiftDisplayStatus = {
            if shift.status == .draft { return .draft }
            if let ts = ts {
                return StaffShiftDisplayStatus(rawValue: ts.status.rawValue) ?? .pending
            }
            return .scheduled
        }()

        let style = Theme.style(for: displayStatus)
        let isDraft = shift.status == .draft

        return Button {
            activeSheet = .edit(shift)
        } label: {
            HStack(spacing: 14) {
                // Status vertical stripe
                RoundedRectangle(cornerRadius: 2)
                    .fill(style.tint)
                    .frame(width: 4)

                // Left avatar
                Text(staffMember?.initials ?? "?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(style.tint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(style.soft))

                VStack(alignment: .leading, spacing: 4) {
                    Text(staffMember?.fullName ?? "Staff Member")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    HStack(spacing: 12) {
                        Label(shift.rosteredStart + " - " + shift.rosteredEnd, systemImage: "clock")
                        if let dept = shift.department, !dept.isEmpty {
                            Label(dept, systemImage: "briefcase")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Right capsule label
                Text(displayStatus.rawValue.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(style.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(style.soft))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                Group {
                    if isDraft {
                        RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(style.tint.opacity(0.4))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteShift(shift)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                activeSheet = .edit(shift)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Theme.brand)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if isDraft {
                Button {
                    pendingPublishShift = shift
                } label: {
                    Label("Publish", systemImage: "paperplane")
                }
                .tint(Theme.accent)
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 6) {
                Text("No Shifts Scheduled")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("There are no shifts scheduled on this day.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                if hasStaff {
                    activeSheet = .create(dateKey: selectedDayKey)
                } else {
                    showNoStaffAlert = true
                }
            } label: {
                Text("Schedule a Shift")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .fill(Theme.brandStrong)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasStaff)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
    }

    private var createShiftFAB: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    if hasStaff {
                        activeSheet = .create(dateKey: selectedDayKey)
                    } else {
                        showNoStaffAlert = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .glassProminentSurface(in: Circle(), tint: Theme.brandStrong)
                        .shadow(color: Theme.brandStrong.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(!hasStaff)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Actions

    private func copyLastWeek() {
        guard !isCopyingWeek else { return }
        isCopyingWeek = true
        Task {
            defer { isCopyingWeek = false }
            do {
                let lastWeekMonday = RosterCalendar.addDays(-7, to: monday)
                let lastWeekDays = RosterCalendar.weekDays(for: lastWeekMonday)
                let lastWeekKeys = lastWeekDays.map { RosterCalendar.dayFormatter.string(from: $0) }
                guard let firstKey = lastWeekKeys.first, let lastKey = lastWeekKeys.last else { return }

                let db = Firestore.firestore()
                let snap = try await db.collection("shifts")
                    .whereField("date", isGreaterThanOrEqualTo: firstKey)
                    .whereField("date", isLessThanOrEqualTo: lastKey)
                    .getDocuments()

                let lastWeekShifts = snap.documents.compactMap { Shift(id: $0.documentID, data: $0.data()) }
                guard !lastWeekShifts.isEmpty else {
                    toast = ToastMessage(kind: .info, text: "No shifts last week to copy")
                    return
                }

                for oldShift in lastWeekShifts {
                    guard let oldDate = RosterCalendar.dateFromKey(oldShift.date) else { continue }
                    let newDate = RosterCalendar.addDays(7, to: oldDate)
                    let newDateKey = RosterCalendar.dayFormatter.string(from: newDate)

                    try await repo.saveShift(
                        id: nil,
                        staffId: oldShift.staffId,
                        date: newDateKey,
                        start: oldShift.rosteredStart,
                        end: oldShift.rosteredEnd,
                        breakMinutes: oldShift.breakMinutes,
                        location: oldShift.location,
                        department: oldShift.department,
                        notes: oldShift.notes,
                        status: .draft
                    )
                }
                toast = ToastMessage(kind: .success,
                                     text: "Copied \(lastWeekShifts.count) shift\(lastWeekShifts.count == 1 ? "" : "s") as drafts")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Copy failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    /// Monday key of the displayed week — the availability-lock unit.
    private var displayedWeekKey: String { weekKeys.first ?? RosterCalendar.weekStartKey(Date()) }

    private var isWeekAvailabilityLocked: Bool {
        repo.lockedAvailabilityWeeks.contains(displayedWeekKey)
    }

    private func toggleWeekAvailabilityLock() {
        let locking = !isWeekAvailabilityLocked
        Task {
            do {
                try await repo.setAvailabilityWeekLock(weekKey: displayedWeekKey, locked: locking)
                toast = ToastMessage(kind: .success,
                                     text: locking ? "Staff availability locked for this week"
                                                   : "Staff availability unlocked")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Lock update failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func publishWeeklyDrafts(lockWeek: Bool) {
        guard let first = weekKeys.first, let last = weekKeys.last else { return }
        let count = weeklyDraftsCount
        Task {
            do {
                try await repo.publishAllDrafts(from: first, to: last)
                if lockWeek {
                    try await repo.setAvailabilityWeekLock(weekKey: first, locked: true)
                }
                toast = ToastMessage(kind: .success,
                                     text: "Published \(count) shift\(count == 1 ? "" : "s")\(lockWeek ? " — availability locked" : "")")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Publish failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func publishSingleShift(_ shift: Shift, lockWeek: Bool) {
        pendingPublishShift = nil
        Task {
            do {
                try await repo.publishShift(shift)
                if lockWeek, let shiftDate = RosterCalendar.dateFromKey(shift.date) {
                    try await repo.setAvailabilityWeekLock(
                        weekKey: RosterCalendar.weekStartKey(shiftDate), locked: true)
                }
                // Same notification the batch publish sends (parity).
                await WorkerAPIClient.shared.sendNotification(event: "roster-published",
                                                              shiftIds: [shift.id])
                toast = ToastMessage(kind: .success,
                                     text: "Shift published\(lockWeek ? " — availability locked" : "")")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Publish failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func deleteShift(_ shift: Shift) {
        Task {
            do {
                try await repo.deleteShift(id: shift.id)
                Haptics.light()
            } catch {
                toast = ToastMessage(kind: .error, text: "Delete failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    // MARK: - Bulk Delete

    private func requestBulkDelete(staffId: String?) {
        let targets = staffId == nil
            ? allWeekShifts
            : allWeekShifts.filter { $0.staffId == staffId }
        guard !targets.isEmpty else { return }

        let label: String
        if let staffId, let name = repo.user(id: staffId)?.fullName {
            label = "\(targets.count) shift\(targets.count == 1 ? "" : "s") for \(name)"
        } else {
            label = "all \(targets.count) shift\(targets.count == 1 ? "" : "s")"
        }

        bulkDeleteRequest = BulkDeleteRequest(staffId: staffId, label: label, count: targets.count)
    }

    private func performBulkDelete(_ request: BulkDeleteRequest) {
        let targets = request.staffId == nil
            ? allWeekShifts
            : allWeekShifts.filter { $0.staffId == request.staffId }

        Task {
            var failures = 0
            for shift in targets {
                do { try await repo.deleteShift(id: shift.id) } catch { failures += 1 }
            }
            if failures > 0 {
                toast = ToastMessage(kind: .error,
                                     text: "Deleted \(targets.count - failures) of \(targets.count) shifts — \(failures) failed")
                Haptics.error()
            } else {
                toast = ToastMessage(kind: .success,
                                     text: "Deleted \(targets.count) shift\(targets.count == 1 ? "" : "s")")
                Haptics.success()
            }
        }
        bulkDeleteRequest = nil
    }

    // MARK: - Drag & Drop Helpers

    private func handleShiftDrop(shiftId: String, targetDateKey: String) {
        guard let shift = repo.shifts.first(where: { $0.id == shiftId }) else { return }
        // Published shifts are locked — only drafts can be moved/copied.
        guard shift.status == .draft else { return }
        if shift.date == targetDateKey { return }

        activeDragDropAction = DragDropAction(shift: shift, targetDateKey: targetDateKey)
    }

    private func moveShift(_ shift: Shift, to targetDateKey: String) {
        Task {
            do {
                try await repo.saveShift(
                    id: shift.id,
                    staffId: shift.staffId,
                    date: targetDateKey,
                    start: shift.rosteredStart,
                    end: shift.rosteredEnd,
                    breakMinutes: shift.breakMinutes,
                    location: shift.location,
                    department: shift.department,
                    notes: shift.notes,
                    status: shift.status
                )
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Move failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func copyShift(_ shift: Shift, to targetDateKey: String) {
        Task {
            do {
                try await repo.saveShift(
                    id: nil,
                    staffId: shift.staffId,
                    date: targetDateKey,
                    start: shift.rosteredStart,
                    end: shift.rosteredEnd,
                    breakMinutes: shift.breakMinutes,
                    location: shift.location,
                    department: shift.department,
                    notes: shift.notes,
                    status: .draft
                )
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Copy failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}

#Preview {
    ManagerRosterView()
        .environment(RosterRepository())
}

private extension View {
    /// Applies `.draggable` only when `condition` is true; otherwise the view is
    /// returned unchanged (and cannot be dragged). Used to lock published shifts.
    @ViewBuilder
    func draggableIf<T: Transferable>(_ condition: Bool, _ payload: T) -> some View {
        if condition {
            self.draggable(payload)
        } else {
            self
        }
    }
}
