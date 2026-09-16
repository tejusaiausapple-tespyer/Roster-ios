import SwiftUI

struct HomeView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AppRouter.self) private var router
    @Environment(TitlePillCollapse.self) private var titlePillCollapse
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var activeSheet: HomeSheet?

    private enum HomeSheet: Identifiable {
        case messages
        case share(URL)
        var id: String {
            switch self {
            case .messages: return "messages"
            case .share(let url): return "share-\(url.absoluteString)"
            }
        }
    }
    @State private var toastMessage: ToastMessage?

    private var now: Date { Date() }
    private var todayKey: String { RosterCalendar.todayKey(now) }

    private var dashboard: HomeDashboardSnapshot {
        HomeDashboardSnapshot(shifts: repo.shifts, todayKey: todayKey)
    }

    private var todayShifts: [Shift] { dashboard.todayShifts }
    private var upcomingShifts: [Shift] { dashboard.upcomingShifts }
    private var todayTasks: [RosterTask] {
        let rawWeekday = RosterCalendar.calendar.component(.weekday, from: now)
        let weekday = rawWeekday == 1 ? 7 : rawWeekday - 1
        let userID = repo.currentUser?.id
        return repo.tasks.filter {
            $0.isActive(onDayKey: todayKey, weekday: weekday) && $0.isAssigned(to: userID)
        }
    }
    private var completedTodayTaskCount: Int {
        let taskIDs = Set(todayTasks.compactMap(\.id))
        return repo.taskCompletions.filter {
            $0.date == todayKey && $0.completed && taskIDs.contains($0.taskId)
        }.count
    }
    private var missedTimesheetShifts: [Shift] {
        HomeDashboardSnapshot.missedTimesheetShifts(
            shifts: repo.shifts,
            timesheets: repo.timesheets,
            now: now
        )
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
        let companyName = headerCompanyName
        return NavigationStack {
            Group {
                if PlatformUI.isPhone {
                    phoneDashboard
                } else {
                    tabletDashboard
                }
            }
            .navigationTitle(PlatformUI.isPhone ? companyName : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if PlatformUI.isPhone {
                    ToolbarItem(placement: .principal) {
                        ScreenTitlePill(title: companyName, fraction: titlePillCollapse.fraction)
                            .accessibilityAddTraits(.isHeader)
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        ToolbarLeadingTitlePill(title: companyName)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        messagesButton
                    }
                }
            }
            .phoneHomeToolbarBehavior()
            .macRefreshable { await repo.refreshFromServer() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .messages: NotificationsSheet()
                case .share(let url): ShareSheet(items: [url])
                }
            }
            .toast($toastMessage)
        }
    }

    private var phoneDashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                phoneGreeting
                if repo.isLoading {
                    SkeletonCard()
                    SkeletonCard()
                } else {
                    phoneTodaySection
                    phoneDailyJobsCard
                    tasksDashboardCard
                    phoneHoursSection
                    phoneMissedTimesheetsSection
                    phoneUpcomingSection
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .tracksTitlePillCollapse()
        }
        .phoneHomeSwipeActions()
        .platformScrollIndicators()
        .phoneScrollEdgeFade()
        .background(Theme.background.ignoresSafeArea())
    }

    private var tabletDashboard: some View {
        TabScroll {
            if repo.isLoading {
                SkeletonCard()
                SkeletonCard()
            } else {
                companyHeader
                todaySection
                dailyJobsCard
                tasksDashboardCard
                hoursSection
                upcomingSection
            }
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

    private var phoneGreeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(RosterFormat.dateFull(now))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var messagesButton: some View {
        // Daily Jobs is a Home card (not a tab). This bell is messages-only.
        let badgeCount = repo.unreadMessageCount
        return Button {
            activeSheet = .messages
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.body.weight(.semibold))
                if badgeCount > 0 {
                    Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, badgeCount > 9 ? 3 : 0)
                        .background(Capsule().fill(Theme.error))
                        .offset(x: 5, y: -5)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Notifications, \(badgeCount) unread")
        .help("Notifications, \(badgeCount) unread")
    }

    // MARK: iPhone dashboard

    @ViewBuilder
    private var phoneTodaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            phoneSectionHeader("Today", systemImage: "sun.max.fill")
            if todayShifts.isEmpty {
                phoneDayOffCard
            } else {
                ForEach(todayShifts) { shift in
                    phoneTodayCard(shift)
                }
            }
        }
    }

    private var phoneDayOffCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 46, height: 46)
                .background(Theme.brand.opacity(0.11), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("You're off today")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let next = upcomingShifts.first {
                    Text("Next shift \(RosterFormat.weekdayLong(next.date)) at \(RosterFormat.time(next.rosteredStart))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("There are no upcoming published shifts.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: 4)

            Button {
                router.select(.roster)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.brand)
            .accessibilityLabel("View roster")
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        }
    }

    private func phoneTodayCard(_ shift: Shift) -> some View {
        let timesheet = repo.timesheet(forShift: shift.id)
        let status = BusinessRules.displayStatus(for: shift, timesheet: timesheet, at: now)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                phoneTodayHeader(status: status, shift: shift)

                Text("\(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { phoneShiftMeta(shift) }
                    VStack(alignment: .leading, spacing: 8) { phoneShiftMeta(shift) }
                }

                if let notes = shift.notes, !notes.isEmpty {
                    Label {
                        Text(notes)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "text.quote")
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
                }

                if let timesheet,
                   [.approved, .pending, .rejected].contains(timesheet.status) {
                    Label(
                        "Worked \(RosterFormat.hours(timesheet.workedHours)) · \(RosterFormat.time(timesheet.actualStart))–\(RosterFormat.time(timesheet.actualEnd))",
                        systemImage: "checkmark.seal"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            Divider().overlay(Theme.separator)

            if isClockable(shift) {
                ClockInCard(shift: shift, presentation: .embedded) {
                    openHours(for: shift)
                }
            } else {
                phoneShiftActionRow(shift, timesheet: timesheet)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill(Theme.card)
                .overlay {
                    LinearGradient(
                        colors: [Theme.brand.opacity(0.12), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(Theme.brand.opacity(0.20), lineWidth: 1)
        }
        .contextMenu { calendarMenu(shift) }
    }

    @ViewBuilder
    private func phoneTodayHeader(status: StaffShiftDisplayStatus, shift: Shift) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Label("Today's shift", systemImage: "briefcase.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    StatusPill(status)
                        .fixedSize(horizontal: true, vertical: false)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    Spacer(minLength: 4)
                    phoneCalendarButton(shift)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.brand)
        } else {
            HStack(alignment: .center, spacing: 10) {
                Label("Today's shift", systemImage: "briefcase.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                Spacer(minLength: 4)
                StatusPill(status)
                phoneCalendarButton(shift)
            }
        }
    }

    private func phoneCalendarButton(_ shift: Shift) -> some View {
        Button {
            Task { await addToCalendar(shift) }
        } label: {
            Image(systemName: "calendar.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Theme.brand.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.brand)
        .accessibilityLabel("Add shift to calendar")
    }

    @ViewBuilder
    private func phoneShiftMeta(_ shift: Shift) -> some View {
        if let location = shift.location, !location.isEmpty {
            Label(location, systemImage: "mappin.and.ellipse")
                .lineLimit(2)
        }
        Label(RosterFormat.hours(shift.scheduledHours), systemImage: "clock")
        if shift.breakMinutes > 0 {
            Label("\(shift.breakMinutes)m break", systemImage: "cup.and.saucer")
        }
    }

    @ViewBuilder
    private func phoneShiftActionRow(_ shift: Shift, timesheet: Timesheet?) -> some View {
        let canSubmit = BusinessRules.canSubmitHours(shift: shift, timesheet: timesheet, at: now)
        let canReport = BusinessRules.canReportAbsence(shift: shift, timesheet: timesheet, at: now)

        if canSubmit || canReport {
            let submitLabel = timesheet?.status == .rejected
                ? "Resubmit hours"
                : (timesheet == nil ? "Submit hours" : "Update hours")
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        phoneSubmitButton(submitLabel, shift: shift, visible: canSubmit)
                        phoneAbsenceButton(shift, visible: canReport)
                    }
                } else {
                    HStack(spacing: 10) {
                        phoneSubmitButton(submitLabel, shift: shift, visible: canSubmit)
                        phoneAbsenceButton(shift, visible: canReport)
                    }
                }
            }
        } else {
            Label("No action needed", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    @ViewBuilder
    private func phoneSubmitButton(_ label: String, shift: Shift, visible: Bool) -> some View {
        if visible {
            Button {
                openHours(for: shift)
            } label: {
                Label(label, systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
        }
    }

    @ViewBuilder
    private func phoneAbsenceButton(_ shift: Shift, visible: Bool) -> some View {
        if visible {
            Button {
                router.pendingAbsentShiftId = shift.id
                router.select(.roster)
            } label: {
                Label("Didn't attend", systemImage: "person.crop.circle.badge.xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Theme.warning)
        }
    }

    @ViewBuilder
    private var phoneDailyJobsCard: some View {
        let jobs = repo.activeDailyJobsForStaff
        if !jobs.isEmpty {
            let done = jobs.filter(\.completed).count
            let tint = repo.pendingDailyJobCount > 0 ? Theme.warning : Theme.accent

            NavigationLink {
                DailyJobsView()
            } label: {
                HStack(spacing: 14) {
                    Gauge(value: Double(done), in: 0...Double(max(jobs.count, 1))) {
                        Text("Daily jobs progress")
                    } currentValueLabel: {
                        Text("\(done)")
                            .font(.caption2.weight(.bold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(tint)
                    .frame(width: 46, height: 46)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily Jobs")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(done == jobs.count
                             ? "Everything is complete"
                             : "\(jobs.count - done) remaining · \(done) of \(jobs.count) done")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily Jobs, \(done) of \(jobs.count) complete")
        }
    }

    private var phoneHoursSection: some View {
        let m = metrics
        return VStack(alignment: .leading, spacing: 12) {
            phoneSectionHeader("Hours snapshot", systemImage: "chart.bar.fill")
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(RosterFormat.decimalHours(m.week))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("hours this week")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                if m.pendingCount > 0 || m.rejectedCount > 0 {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { phoneHoursStatus(m) }
                        VStack(alignment: .leading, spacing: 8) { phoneHoursStatus(m) }
                    }
                }

                Divider().overlay(Theme.separator)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 14) { phoneHoursBreakdown(m) }
                    } else {
                        HStack(spacing: 0) { phoneHoursBreakdown(m) }
                    }
                }
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
        }
    }

    private var tasksDashboardCard: some View {
        let completed = completedTodayTaskCount
        let remaining = max(0, todayTasks.count - completed)
        let tint = remaining > 0 ? Theme.warning : Theme.accent

        return NavigationLink {
            TasksView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: remaining > 0 ? "list.bullet.clipboard.fill" : "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.11), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Tasks")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(taskSummary(completed: completed, remaining: remaining))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 4)

                if !todayTasks.isEmpty {
                    Text("\(completed)/\(todayTasks.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tint.opacity(0.11), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tasks, \(taskSummary(completed: completed, remaining: remaining))")
    }

    private func taskSummary(completed: Int, remaining: Int) -> String {
        guard !todayTasks.isEmpty else { return "No tasks assigned today" }
        return remaining == 0
            ? "All \(completed) completed today"
            : "\(remaining) remaining · \(completed) completed"
    }

    @ViewBuilder
    private func phoneHoursStatus(_ metrics: HoursMetrics) -> some View {
        if metrics.pendingCount > 0 {
            Label(
                "\(RosterFormat.hours(metrics.pendingHours)) pending",
                systemImage: "hourglass"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.warning)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.warning.opacity(0.11), in: Capsule())
        }
        if metrics.rejectedCount > 0 {
            Label(
                "\(metrics.rejectedCount) need\(metrics.rejectedCount == 1 ? "s" : "") attention",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.error)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.error.opacity(0.10), in: Capsule())
        }
    }

    @ViewBuilder
    private func phoneHoursBreakdown(_ metrics: HoursMetrics) -> some View {
        phoneHoursMetric("Month", value: metrics.month)
        phoneMetricDivider
        phoneHoursMetric("Year", value: metrics.year)
        phoneMetricDivider
        phoneHoursMetric("All time", value: metrics.all)
    }

    private func phoneHoursMetric(_ label: String, value: Double) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center, spacing: 3) {
            Text("\(RosterFormat.decimalHours(value))h")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(RosterFormat.decimalHours(value)) hours")
    }

    @ViewBuilder
    private var phoneMetricDivider: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            Divider()
                .frame(height: 36)
                .overlay(Theme.separator)
        }
    }

    private var phoneMissedTimesheetsSection: some View {
        let shifts = missedTimesheetShifts
        let needsAction = !shifts.isEmpty
        let tint = needsAction ? Theme.warning : Theme.accent

        return VStack(alignment: .leading, spacing: 12) {
            phoneSectionHeader("Timesheets", systemImage: "clock.badge.exclamationmark")

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: needsAction ? "exclamationmark.clock.fill" : "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.11), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(needsAction ? "Missed submissions" : "Everything is up to date")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(needsAction
                             ? "\(shifts.count) timesheet\(shifts.count == 1 ? "" : "s") still need\(shifts.count == 1 ? "s" : "") your hours"
                             : "You have no missed timesheets.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer(minLength: 4)

                    if needsAction {
                        Text("\(shifts.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                            .accessibilityLabel("\(shifts.count) missed timesheets")
                    }
                }
                .padding(16)

                if needsAction {
                    Divider()
                        .padding(.leading, 74)
                        .overlay(Theme.separator)

                    ForEach(Array(shifts.enumerated()), id: \.element.id) { index, shift in
                        phoneMissedTimesheetRow(shift)
                        if index < shifts.count - 1 {
                            Divider()
                                .padding(.leading, 74)
                                .overlay(Theme.separator)
                        }
                    }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .strokeBorder(needsAction ? Theme.warning.opacity(0.25) : Theme.separator, lineWidth: 1)
            }
        }
    }

    private func phoneMissedTimesheetRow(_ shift: Shift) -> some View {
        Button {
            openHours(for: shift)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        missedTimesheetDetails(shift)
                        missedTimesheetSubmitLabel
                    }
                } else {
                    HStack(spacing: 14) {
                        missedTimesheetDetails(shift)
                        Spacer(minLength: 8)
                        missedTimesheetSubmitLabel
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Submit timesheet for \(RosterFormat.date(shift.date)), \(RosterFormat.time(shift.rosteredStart)) to \(RosterFormat.time(shift.rosteredEnd))"
        )
    }

    private func missedTimesheetDetails(_ shift: Shift) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(RosterFormat.date(shift.date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(missedTimesheetSubtitle(shift))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }

    private func missedTimesheetSubtitle(_ shift: Shift) -> String {
        let time = "\(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))"
        guard let location = shift.location, !location.isEmpty else { return time }
        return "\(time) · \(location)"
    }

    private var missedTimesheetSubmitLabel: some View {
        Label("Submit", systemImage: "arrow.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.warning)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.warning.opacity(0.11), in: Capsule())
    }

    @ViewBuilder
    private var phoneUpcomingSection: some View {
        if !upcomingShifts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                phoneSectionHeader("Up next", systemImage: "calendar") {
                    Button("View roster") { router.select(.roster) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }

                VStack(spacing: 0) {
                    ForEach(Array(upcomingShifts.enumerated()), id: \.element.id) { index, shift in
                        phoneUpcomingRow(shift)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    Task { await addToCalendar(shift) }
                                } label: {
                                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                }
                                .tint(Theme.brand)
                            }
                            .contextMenu { calendarMenu(shift) }
                        if index < upcomingShifts.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                                .overlay(Theme.separator)
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1)
                }
            }
        }
    }

    private func phoneUpcomingRow(_ shift: Shift) -> some View {
        Button {
            router.select(.roster)
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(RosterFormat.weekdayLong(shift.date).prefix(3).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.brand)
                    Text(RosterFormat.dateShort(shift.date).split(separator: " ").first.map(String.init) ?? "")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 46, height: 52)
                .background(Theme.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(RosterFormat.weekdayLong(shift.date)), \(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        if let location = shift.location, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .lineLimit(1)
                        }
                        Label(RosterFormat.hours(shift.scheduledHours), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(RosterFormat.weekdayLong(shift.date)), \(RosterFormat.dateShort(shift.date)), \(RosterFormat.time(shift.rosteredStart)) to \(RosterFormat.time(shift.rosteredEnd))"
        )
        .accessibilityHint("Opens the roster. Swipe for calendar actions on iOS 27.")
    }

    private func phoneSectionHeader<Trailing: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            trailing()
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func phoneSectionHeader(_ title: String, systemImage: String) -> some View {
        phoneSectionHeader(title, systemImage: systemImage) { EmptyView() }
    }

    // MARK: Greeting header

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

    // MARK: Daily Jobs

    /// Opens the full dedicated Daily Jobs page (no longer buried in the bell
    /// popup) — only shown when there's actually something assigned today.
    @ViewBuilder
    private var dailyJobsCard: some View {
        let jobs = repo.activeDailyJobsForStaff
        if !jobs.isEmpty {
            let done = jobs.filter(\.completed).count
            NavigationLink {
                DailyJobsView()
            } label: {
                HStack(spacing: 14) {
                    let tint = repo.pendingDailyJobCount > 0 ? Theme.warning : Theme.accent
                    Image(systemName: "checklist")
                        .font(.title3)
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Jobs")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(done)/\(jobs.count) done today")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                        .fill(Theme.card)
                )
            }
            .buttonStyle(.plain)
            .pointerHover()
        }
    }

    /// Clock in/out applies until hours are submitted: no timesheet yet, or
    /// there's an active/ended session for this shift awaiting submission.
    ///
    /// `RosterRepository.reconcileClockSessionFromServerIfNeeded` rebuilds a
    /// lost local session from verified attendance as soon as both `shifts`
    /// and `attendanceRecords` have loaded, so `repo.clockSession` is already
    /// the reconciled truth by the time this runs — this doesn't need its
    /// own server check.
    private func isClockable(_ shift: Shift) -> Bool {
        HomeDashboardSnapshot.isClockable(
            shiftId: shift.id,
            activeClockShiftId: repo.clockSession?.shiftId,
            hasTimesheet: repo.timesheet(forShift: shift.id) != nil
        )
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

    private func openHours(for shift: Shift) {
        router.pendingSubmitShiftId = shift.id
        router.select(.roster)
    }

    private func shiftActions(for shift: Shift) -> ShiftCardActions {
        ShiftCardActions(
            onSubmit: { openHours(for: shift) },
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
            activeSheet = .share(url)
        case .failed(let message):
            toastMessage = ToastMessage(kind: .error, text: message)
            Haptics.error()
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Pure, testable filtering for the Home dashboard. Keeping date/order rules
/// outside the view prevents the iPhone and iPad presentations from drifting.
struct HomeDashboardSnapshot {
    let todayShifts: [Shift]
    let upcomingShifts: [Shift]

    init(shifts: [Shift], todayKey: String, upcomingLimit: Int = 3) {
        todayShifts = shifts
            .filter { $0.date == todayKey && $0.status == .published }
            .sorted { $0.rosteredStart < $1.rosteredStart }

        upcomingShifts = Array(
            shifts
                .filter { $0.date > todayKey && $0.status == .published }
                .sorted { ($0.date, $0.rosteredStart) < ($1.date, $1.rosteredStart) }
                .prefix(upcomingLimit)
        )
    }

    static func isClockable(
        shiftId: String,
        activeClockShiftId: String?,
        hasTimesheet: Bool
    ) -> Bool {
        if activeClockShiftId == shiftId { return true }
        guard activeClockShiftId == nil else { return false }
        return !hasTimesheet
    }

    static func missedTimesheetShifts(
        shifts: [Shift],
        timesheets: [Timesheet],
        now: Date,
        limit: Int = 3
    ) -> [Shift] {
        let timesheetByShiftId = Dictionary(
            timesheets.map { ($0.shiftId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return Array(
            shifts
                .filter { shift in
                    guard shift.status == .published, shift.isSubmittable(at: now) else { return false }
                    guard let timesheet = timesheetByShiftId[shift.id] else { return true }
                    return timesheet.status == .draft
                }
                .sorted { ($0.date, $0.rosteredStart) > ($1.date, $1.rosteredStart) }
                .prefix(limit)
        )
    }
}
