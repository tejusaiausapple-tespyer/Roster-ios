import SwiftUI

struct RosterView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AppRouter.self) private var router

    @State private var weekOffset = 0
    @State private var selectedDayKey = RosterCalendar.todayKey()
    @State private var submitShift: Shift?
    @State private var absentShift: Shift?
    @State private var undoTarget: Timesheet?
    @State private var shareURL: URL?
    @State private var toastMessage: ToastMessage?

    private var now: Date { Date() }
    private var bounds: (min: Int, max: Int) { BusinessRules.shiftWeekOffsetBounds(at: now) }
    private var monday: Date { RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(now)) }
    private var weekDays: [Date] { RosterCalendar.weekDays(for: monday) }
    private var weekKeys: [String] { weekDays.map { RosterCalendar.dayFormatter.string(from: $0) } }

    private var weekShifts: [Shift] {
        guard let first = weekKeys.first, let last = weekKeys.last else { return [] }
        return repo.shifts
            .filter { $0.status == .published && $0.date >= first && $0.date <= last }
            .sorted { ($0.date, $0.rosteredStart) < ($1.date, $1.rosteredStart) }
    }

    private func shifts(on key: String) -> [Shift] {
        weekShifts.filter { $0.date == key }
    }

    private var markedKeys: Set<String> {
        Set(weekShifts.map { $0.date })
    }

    private var actionNeeded: [Shift] {
        weekShifts.filter { BusinessRules.needsStaffAction(shift: $0, timesheet: repo.timesheet(forShift: $0.id), at: now) }
    }

    private var totalScheduled: Double {
        weekShifts.reduce(0) { $0 + $1.scheduledHours }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if !actionNeeded.isEmpty {
                        actionNeededSection
                    }
                    ForEach(weekKeys, id: \.self) { key in
                        daySection(key)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .safeAreaInset(edge: .top) { header }
                .onChange(of: selectedDayKey) { _, key in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(key, anchor: .top)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitlePill(title: "Roster", icon: "calendar")
                }
            }
            .refreshable { await repo.refreshFromServer() }
            .sheet(item: $submitShift) { shift in
                SubmitHoursSheet(shift: shift, existing: repo.timesheet(forShift: shift.id),
                                 clock: repo.clockSession)
            }
            .sheet(item: $absentShift) { shift in
                ReportAbsenceSheet(shift: shift, existing: repo.timesheet(forShift: shift.id))
            }
            .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
            .confirmationDialog("Undo absence report?",
                                isPresented: Binding(get: { undoTarget != nil }, set: { if !$0 { undoTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Undo absence", role: .destructive) {
                    if let ts = undoTarget { Task { await undoAbsence(ts) } }
                }
                Button("Cancel", role: .cancel) { undoTarget = nil }
            } message: {
                Text("This removes your absence report so you can submit hours instead.")
            }
            .toast($toastMessage)
            .task(id: router.pendingSubmitShiftId) { await handlePendingSubmit() }
            .task(id: router.pendingAbsentShiftId) { await handlePendingAbsent() }
        }
    }

    // MARK: Header (stats + week selector)

    private var header: some View {
        VStack(spacing: 8) {
            // Stats & Week Selector Card
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    miniStat(value: "\(weekShifts.count)", label: "Shifts")
                    miniStat(value: RosterFormat.decimalHours(totalScheduled), label: "Hours")
                    miniStat(value: "\(actionNeeded.count)", label: "To do",
                             tint: actionNeeded.isEmpty ? Theme.textSecondary : Theme.warning)
                }
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
            
            // View Shift History (Separate Card Button - slightly larger)
            NavigationLink(destination: HistoryView()) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.brand)
                        .font(.body.weight(.semibold))
                    Text("View Shift History")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                        .fill(Theme.card)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private func miniStat(value: String, label: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.background))
    }

    // MARK: Action needed carousel

    private var actionNeededSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(actionNeeded) { shift in
                        actionChip(shift)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } header: {
            Text("Needs your attention")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warning)
                .textCase(nil)
                .padding(.horizontal, Theme.screenPadding)
        }
    }

    private func actionChip(_ shift: Shift) -> some View {
        let ts = repo.timesheet(forShift: shift.id)
        let isRejected = ts?.status == .rejected
        return Button {
            submitShift = shift
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(RosterFormat.dateShort(shift.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(RosterFormat.time(shift.rosteredStart))–\(RosterFormat.time(shift.rosteredEnd))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isRejected ? "Resubmit hours" : "Submit hours")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRejected ? Theme.error : Theme.brand)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill((isRejected ? Theme.error : Theme.brand).opacity(0.12)))
            }
            .padding(14)
            .frame(width: 170, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Day section

    @ViewBuilder
    private func daySection(_ key: String) -> some View {
        let dayShifts = shifts(on: key)
        Section {
            if dayShifts.isEmpty {
                emptyDayRow
            } else {
                ForEach(dayShifts) { shift in
                    shiftRow(shift)
                }
            }
        } header: {
            dayHeader(key, count: dayShifts.count)
                .id(key)
        }
    }

    private func dayHeader(_ key: String, count: Int) -> some View {
        HStack {
            Text(RosterFormat.date(key))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(key == RosterCalendar.todayKey() ? Theme.brand : Theme.textPrimary)
                .textCase(nil)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.card))
            }
            Spacer()
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    private var emptyDayRow: some View {
        Text("No shift")
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundStyle(Theme.separator)
            )
            .listRowInsets(EdgeInsets(top: 4, leading: Theme.screenPadding, bottom: 4, trailing: Theme.screenPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func shiftRow(_ shift: Shift) -> some View {
        let ts = repo.timesheet(forShift: shift.id)
        let canSubmit = BusinessRules.canSubmitHours(shift: shift, timesheet: ts, at: now)
        let canAbsence = BusinessRules.canReportAbsence(shift: shift, timesheet: ts, at: now)
        let canUndo = ts?.isStaffReportedAbsence ?? false

        return ShiftCard(
            shift: shift,
            timesheet: ts,
            variant: .standard,
            showDate: false,
            showsInlineActions: false
        )
        .listRowInsets(EdgeInsets(top: 6, leading: Theme.screenPadding, bottom: 6, trailing: Theme.screenPadding))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canSubmit {
                Button { submitShift = shift } label: {
                    Label(ts?.status == .rejected ? "Resubmit" : (ts != nil ? "Edit" : "Submit"),
                          systemImage: "square.and.pencil")
                }.tint(Theme.brand)
            }
            if canAbsence {
                Button { absentShift = shift } label: {
                    Label("Absent", systemImage: "person.fill.xmark")
                }.tint(Theme.warning)
            }
            if canUndo {
                Button { undoTarget = ts } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }.tint(Theme.textSecondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { Task { await addToCalendar(shift) } } label: {
                Label("Calendar", systemImage: "calendar.badge.plus")
            }.tint(Theme.accent)
        }
        .contextMenu {
            if canSubmit {
                Button { submitShift = shift } label: {
                    Label(ts?.status == .rejected ? "Resubmit hours" : "Submit hours", systemImage: "square.and.pencil")
                }
            }
            if canAbsence {
                Button { absentShift = shift } label: {
                    Label("Report absence", systemImage: "person.fill.xmark")
                }
            }
            if canUndo {
                Button(role: .destructive) { undoTarget = ts } label: {
                    Label("Undo absence", systemImage: "arrow.uturn.backward")
                }
            }
            Button { Task { await addToCalendar(shift) } } label: {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
            }
        }
    }

    // MARK: Deep links

    private func handlePendingSubmit() async {
        guard let id = router.pendingSubmitShiftId else { return }
        defer { router.pendingSubmitShiftId = nil }
        if let shift = await repo.fetchShift(id: id) {
            focusWeek(for: shift.date)
            submitShift = shift
        }
    }

    private func handlePendingAbsent() async {
        guard let id = router.pendingAbsentShiftId else { return }
        defer { router.pendingAbsentShiftId = nil }
        if let shift = await repo.fetchShift(id: id) {
            focusWeek(for: shift.date)
            absentShift = shift
        }
    }

    private func focusWeek(for dateKey: String) {
        guard let date = RosterFormat.parseISODate(dateKey) else { return }
        let target = RosterCalendar.weekStart(date)
        let base = RosterCalendar.weekStart(now)
        let weeks = RosterCalendar.calendar.dateComponents([.weekOfYear], from: base, to: target).weekOfYear ?? 0
        weekOffset = min(max(weeks, bounds.min), bounds.max)
        selectedDayKey = dateKey
    }

    // MARK: Actions

    private func undoAbsence(_ ts: Timesheet) async {
        undoTarget = nil
        do {
            try await repo.undoAbsenceReport(timesheetId: ts.id)
            Haptics.success()
            toastMessage = ToastMessage(kind: .success, text: "Absence report removed")
        } catch {
            toastMessage = ToastMessage(kind: .error, text: error.localizedDescription)
        }
    }

    private func addToCalendar(_ shift: Shift) async {
        let result = await CalendarService.addShift(shift, companyName: repo.appSettings.companyName)
        switch result {
        case .added:
            toastMessage = ToastMessage(kind: .success, text: "Added to Calendar"); Haptics.success()
        case .sharedFile(let url):
            shareURL = url
        case .failed(let message):
            toastMessage = ToastMessage(kind: .error, text: message); Haptics.error()
        }
    }
}
