import SwiftUI

struct HomeView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AppRouter.self) private var router

    @State private var showMessages = false
    @State private var shareURL: URL?
    @State private var toastMessage: ToastMessage?

    private var now: Date { Date() }
    private var todayKey: String { RosterCalendar.todayKey(now) }

    private var todayShifts: [Shift] {
        repo.shifts
            .filter { $0.date == todayKey && $0.status == .published }
            .sorted { $0.rosteredStart < $1.rosteredStart }
    }

    private var upcomingShifts: [Shift] {
        repo.shifts
            .filter { $0.date > todayKey && $0.status == .published }
            .sorted { ($0.date, $0.rosteredStart) < ($1.date, $1.rosteredStart) }
            .prefix(3)
            .map { $0 }
    }

    private var metrics: HoursMetrics {
        HoursMetrics.compute(timesheets: repo.timesheets, shifts: repo.shifts, now: now)
    }

    /// Manager → Company details → Company Name (`settings/app.companyName`).
    private var headerCompanyName: String {
        let name = repo.appSettings.companyName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? AppSettings.fallback.companyName : name
    }

    var body: some View {
        // Read headerCompanyName in the view body (not only inside the toolbar
        // closure) so the pill re-renders when settings/app streams in.
        let pillTitle = headerCompanyName
        return NavigationStack {
            TabScroll {
                if repo.isLoading {
                    SkeletonCard()
                    SkeletonCard()
                } else {
                    companyHeader
                    todaySection
                    hoursSection
                    upcomingSection
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Company name owns the header pill, left-aligned so long
                // names get room (truncated gracefully by the pill).
                ToolbarItem(placement: .topBarLeading) {
                    ScreenTitlePill(title: pillTitle, icon: "building.2.fill")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    messagesButton
                }
            }
            .refreshable { await repo.refreshFromServer() }
            .sheet(isPresented: $showMessages) {
                NotificationsSheet()
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .toast($toastMessage)
        }
    }

    // MARK: Greeting

    private var greetingTitle: String {
        if let user = repo.currentUser {
            return "\(greetingText) \(user.firstName)"
        }
        return greetingText
    }

    private var greetingText: String {
        let hour = RosterCalendar.calendar.component(.hour, from: now)
        return hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
    }

    private var messagesButton: some View {
        // Badge counts unread messages + pending Daily Jobs for the current shift.
        let badgeCount = repo.unreadMessageCount + repo.pendingDailyJobCount
        return Button {
            showMessages = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body.weight(.semibold))
                if badgeCount > 0 {
                    // Overlap the bell by ~a third — offset ≈ badge radius/2
                    // keeps it attached to the icon instead of floating.
                    Text("\(min(badgeCount, 9))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.error))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .accessibilityLabel("Notifications, \(badgeCount) unread")
    }

    // MARK: Greeting header (company name lives in the toolbar pill)

    private var companyHeader: some View {
        Text(greetingTitle)
            .font(.title2.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Today

    @ViewBuilder
    private var todaySection: some View {
        SectionHeader("Today", systemImage: "sun.max")
        if todayShifts.isEmpty {
            Card {
                EmptyStateView(icon: "moon.zzz",
                               title: "No shift today",
                               message: "Enjoy your day off. Your upcoming shifts are below.")
            }
        } else {
            ForEach(todayShifts) { shift in
                ShiftCard(
                    shift: shift,
                    timesheet: repo.timesheet(forShift: shift.id),
                    variant: .hero,
                    showDate: false,
                    actions: shiftActions(for: shift)
                )
                .contextMenu { calendarMenu(shift) }
                if isClockable(shift) {
                    ClockInCard(shift: shift) {
                        router.pendingSubmitShiftId = shift.id
                        router.select(.roster)
                    }
                }
            }
        }
    }

    /// Clock in/out applies until hours are submitted: no timesheet yet, or
    /// there's an active/ended session for this shift awaiting submission.
    private func isClockable(_ shift: Shift) -> Bool {
        if repo.clockSession?.shiftId == shift.id { return true }
        guard repo.clockSession == nil else { return false } // busy on another shift
        return repo.timesheet(forShift: shift.id) == nil
    }

    // MARK: Hours

    @ViewBuilder
    private var hoursSection: some View {
        SectionHeader("Approved hours", systemImage: "checkmark.seal")
        let m = metrics
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: RosterFormat.decimalHours(m.week), label: "This week", unit: "h", icon: "calendar")
            StatTile(value: RosterFormat.decimalHours(m.month), label: "This month", unit: "h", icon: "calendar.badge.clock")
            StatTile(value: RosterFormat.decimalHours(m.year), label: "This year", unit: "h", icon: "chart.bar")
            StatTile(value: RosterFormat.decimalHours(m.all), label: "All time", unit: "h", icon: "infinity")
        }
    }

    // MARK: Upcoming

    @ViewBuilder
    private var upcomingSection: some View {
        if !upcomingShifts.isEmpty {
            SectionHeader(title: "Upcoming", systemImage: "calendar") {
                Button("View roster") { router.select(.roster) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.brand)
            }
            ForEach(upcomingShifts) { shift in
                ShiftCard(
                    shift: shift,
                    timesheet: repo.timesheet(forShift: shift.id),
                    variant: .compact,
                    showDate: true,
                    showsInlineActions: false
                )
                .contextMenu { calendarMenu(shift) }
            }
        }
    }

    // MARK: Actions

    private func shiftActions(for shift: Shift) -> ShiftCardActions {
        ShiftCardActions(
            onSubmit: { router.pendingSubmitShiftId = shift.id; router.select(.roster) },
            onReportAbsence: { router.pendingAbsentShiftId = shift.id; router.select(.roster) },
            onUndoAbsence: nil,
            onAddToCalendar: { Task { await addToCalendar(shift) } }
        )
    }

    @ViewBuilder
    private func calendarMenu(_ shift: Shift) -> some View {
        Button {
            Task { await addToCalendar(shift) }
        } label: {
            Label("Add to Calendar", systemImage: "calendar.badge.plus")
        }
    }

    private func addToCalendar(_ shift: Shift) async {
        let company = repo.appSettings.companyName
        let result = await CalendarService.addShift(shift, companyName: company)
        switch result {
        case .added:
            toastMessage = ToastMessage(kind: .success, text: "Added to Calendar")
            Haptics.success()
        case .sharedFile(let url):
            shareURL = url
        case .failed(let message):
            toastMessage = ToastMessage(kind: .error, text: message)
            Haptics.error()
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
