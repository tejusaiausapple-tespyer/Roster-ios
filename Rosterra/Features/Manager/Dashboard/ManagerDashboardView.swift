import SwiftUI
import FirebaseAuth

struct ManagerDashboardView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var activeSheet: DashboardSheet?

    private enum DashboardSheet: Identifiable {
        case newShift
        case newTask
        case assignJobs(Shift)
        case pendingTimesheets
        var id: String {
            switch self {
            case .newShift: return "newShift"
            case .newTask: return "newTask"
            case .assignJobs(let shift): return "assignJobs-\(shift.id)"
            case .pendingTimesheets: return "pendingTimesheets"
            }
        }
    }

    private var todayKey: String {
        RosterCalendar.todayKey()
    }
    
    private var formattedDate: String {
        RosterFormat.dateFull(Date())
    }
    
    private var weekday: Int {
        let raw = RosterCalendar.calendar.component(.weekday, from: Date())
        if raw == 1 { return 7 }
        return raw - 1
    }
    
    // MARK: - Computed Properties (Live Data)
    
    private var todaysShifts: [Shift] {
        repo.todaysShifts()
    }

    /// Lifecycle status per shift (Scheduled → In Progress → Pending →
    /// Awaiting Approval → Approved), derived by BusinessRules from the
    /// timesheet, the verified attendance record (actual clock-in/out),
    /// and the schedule — in that order.
    private func lifecycleStatus(for shift: Shift) -> ManagerShiftStatus {
        BusinessRules.managerShiftStatus(
            shift: shift,
            timesheet: repo.timesheets.first(where: { $0.shiftId == shift.id }),
            attendance: repo.attendance(forShift: shift.id)
        )
    }

    private func tint(for status: ManagerShiftStatus) -> Color {
        switch status {
        case .scheduled: return Theme.textTertiary
        case .inProgress: return Theme.brand
        case .pendingSubmission: return Theme.warning
        case .awaitingApproval: return Theme.style(for: .scheduled).tint // blue
        case .approved: return Theme.accent
        case .rejected: return Theme.error
        case .absence: return Theme.style(for: StaffShiftDisplayStatus.absentReported).tint
        }
    }
    
    /// Staff genuinely clocked in right now — mirrors the "Today's Roster
    /// Status" list below via the same lifecycleStatus(for:), rather than
    /// the old "has any timesheet record at all" check (which kept counting
    /// a shift as active long after it was approved/rejected).
    private var activeStaffCount: Int {
        todaysShifts.filter { lifecycleStatus(for: $0) == .inProgress }.count
    }
    
    private var totalScheduledHours: Double {
        todaysShifts.reduce(0.0) { $0 + $1.scheduledHours }
    }
    
    private var todaysTasks: [RosterTask] {
        repo.tasks.filter { task in
            if task.frequency == "once" {
                return task.date == todayKey
            } else if task.frequency == "weekly" {
                return task.dayOfWeek?.contains(weekday) ?? false
            } else {
                return true // daily
            }
        }
    }
    
    private var completedTasksCount: Int {
        todaysTasks.filter { task in
            repo.taskCompletions.contains { $0.taskId == task.id && $0.date == todayKey && $0.completed }
        }.count
    }
    
    private var pendingTimesheetsCount: Int {
        repo.timesheets.filter { $0.status == .pending }.count
    }
    
    private var todaysDailyJobAssignments: [DailyJobAssignment] {
        repo.dailyJobAssignments.filter { $0.date == todayKey }
    }

    private var dailyJobsDoneCount: Int {
        todaysDailyJobAssignments.filter(\.completed).count
    }

    private var recentCompletions: [TaskCompletion] {
        repo.taskCompletions
            .filter { $0.date == todayKey }
            .sorted { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let compact = PlatformUI.isCompactLayout(width: proxy.size.width)
                ZStack {
                    Theme.background.ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 20) {
                            // Data-layer errors (listener failures) were previously
                            // silent — the dashboard is the manager's landing screen,
                            // so surface them here.
                            if let loadError = repo.loadError {
                                Banner(kind: .error,
                                       title: "Some data failed to load",
                                       message: loadError)
                            }

                            // Hero Header Card
                            headerCard

                            // Shortcut into today's Daily Jobs, right below the welcome card.
                            dailyJobsCard

                            // Live Metrics Grid
                            metricsGrid

                            // Main Sections: 2-column when the window is wide enough,
                            // 1-column on iPhone and resized Mac / Split View.
                            if compact {
                                VStack(spacing: 20) {
                                    quickActionsSection
                                    activeRosterSection
                                    recentTasksSection
                                }
                            } else {
                                HStack(alignment: .top, spacing: 20) {
                                    VStack(spacing: 20) {
                                        quickActionsSection
                                        activeRosterSection
                                    }
                                    .frame(maxWidth: .infinity)

                                    VStack(spacing: 20) {
                                        recentTasksSection
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                        .contentLane()
                        .tracksTitlePillCollapse()
                    }
                    .platformScrollIndicators()
                    .macRefreshable {
                        await repo.refreshFromServer()
                    }
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .screenTitlePill("Dashboard", icon: "square.grid.2x2.fill", fraction: 0)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .newShift: ManagerShiftEditorSheet(defaultDateKey: todayKey)
                case .newTask: ManagerTaskEditorSheet(task: nil, defaultDateKey: todayKey)
                case .assignJobs(let shift): DailyJobAssignSheet(shift: shift)
                case .pendingTimesheets:
                    PendingTimesheetsSheet()
                        .phoneSheetDetents([.medium, .large])
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.appSettings.companyName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.brand)
                        .textCase(.uppercase)
                    
                    Text("Manager Portal")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.brand)
                    .padding(10)
                    .background(Circle().fill(Theme.brand.opacity(0.12)))
            }
            
            Divider().overlay(Theme.separator)
                .padding(.vertical, 4)
            
            Text(formattedDate)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
    }
    
    private var metricsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

        return LazyVGrid(columns: columns, spacing: 12) {
            metricCard(
                value: "\(activeStaffCount) / \(todaysShifts.count)",
                label: "Active Staff",
                icon: "person.fill.checkmark",
                color: Theme.accent
            )
            metricCard(
                value: String(format: "%.1fh", totalScheduledHours),
                label: "Hours Scheduled",
                icon: "clock.fill",
                color: Theme.brand
            )
            metricCard(
                value: "\(completedTasksCount) / \(todaysTasks.count)",
                label: "Tasks Completed",
                icon: "checklist.checked",
                color: Theme.accent
            )
            Button {
                activeSheet = .pendingTimesheets
            } label: {
                metricCard(
                    value: "\(pendingTimesheetsCount)",
                    label: "Pending Timesheets",
                    icon: "doc.badge.clock",
                    color: pendingTimesheetsCount > 0 ? Theme.warning : Theme.textSecondary
                )
            }
            .buttonStyle(.plain)
            .pointerHover()
            .accessibilityHint("Opens the list of staff with a pending timesheet")
        }
    }

    /// `minHeight` keeps all four cards the same height regardless of
    /// whether a given label wraps to one or two lines ("ACTIVE STAFF" vs
    /// "HOURS SCHEDULED") — without it each card's background sizes to its
    /// own intrinsic content instead of the grid row, so the shorter-label
    /// cards visibly shrink next to the wrapped ones.
    private func metricCard(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(Theme.card)
        )
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                actionButton(title: "New Shift", icon: "calendar.badge.plus", color: Theme.brand) {
                    activeSheet = .newShift
                }
                actionButton(title: "New Task", icon: "checkmark.circle.badge.questionmark", color: Theme.accent) {
                    activeSheet = .newTask
                }
                NavigationLink {
                    ManagerStaffView(embedInNavigationStack: false)
                } label: {
                    actionLabel(title: "Staff Directory", icon: "person.2.fill", color: Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .pointerHover()
            }
        }
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title: title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
        .pointerHover()
    }

    /// `minHeight` matches every quick-action card to the tallest possible
    /// title ("Staff Directory" wraps to 2 lines at the grid's narrower
    /// widths; "New Shift"/"New Task" don't) — without it, the wrapped card
    /// grows taller than its 1-line siblings in the same grid row.
    private func actionLabel(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(Theme.card)
        )
    }
    
    private var activeRosterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Roster Status")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            
            if todaysShifts.isEmpty {
                Text("No shifts scheduled for today.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .fill(Theme.card)
                    )
            } else {
                // Each shift is its own white card, rather than one shared
                // card with divider lines between rows — makes staff easier
                // to visually scan/separate at a glance.
                VStack(spacing: 10) {
                    ForEach(todaysShifts, id: \.id) { shift in
                        let staffMember = repo.user(id: shift.staffId)
                        let status = lifecycleStatus(for: shift)

                        Button {
                            activeSheet = .assignJobs(shift)
                        } label: {
                            rosterRow(
                                name: staffMember?.fullName ?? "Staff Member",
                                role: shift.department ?? "General",
                                time: "\(shift.rosteredStart) - \(shift.rosteredEnd)",
                                status: status.title,
                                tint: tint(for: status),
                                inProgress: status == .inProgress,
                                jobs: repo.dailyJobs(forShift: shift.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .pointerHover()
                        .accessibilityHint("Opens Daily Jobs assignment")
                    }
                }
            }
        }
    }

    /// Shortcut into today's Daily Jobs across every staff member — without
    /// this, the only way in was clicking a specific staff row under Today's
    /// Roster Status and scrolling to find it.
    private var dailyJobsCard: some View {
        NavigationLink {
            ManagerDailyJobsOverviewView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.title3)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 40, height: 40)
                    .background(Theme.brand.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Jobs")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(todaysDailyJobAssignments.isEmpty
                         ? "No jobs assigned today"
                         : "\(dailyJobsDoneCount)/\(todaysDailyJobAssignments.count) done across today's shifts")
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

    private func rosterRow(name: String, role: String, time: String, status: String,
                           tint: Color, inProgress: Bool = false,
                           jobs: [DailyJobAssignment] = []) -> some View {
        // Each row is its own white card. The in-progress shift still takes
        // visual priority, but via a bold name + inset brand accent stripe
        // rather than a tinted background wash — the card stays white.
        HStack(spacing: 0) {
            if inProgress {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.brand)
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .padding(.leading, 10)
            }

            HStack(spacing: 12) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(inProgress ? .bold : .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(role) • \(time)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if !jobs.isEmpty {
                        let done = jobs.filter(\.completed).count
                        HStack(spacing: 3) {
                            Image(systemName: done == jobs.count ? "checkmark.circle.fill" : "checklist")
                                .font(.caption2)
                            Text("Jobs \(done)/\(jobs.count)")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(done == jobs.count ? Theme.accent : Theme.warning)
                    }
                }

                Spacer()

                Text(status)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.12)))
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        )
    }
    
    private var recentTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Task Logs")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            
            if recentCompletions.isEmpty {
                Text("No task completions logged today.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .fill(Theme.card)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentCompletions.enumerated()), id: \.element.id) { index, completion in
                        let task = repo.tasks.first(where: { $0.id == completion.taskId })
                        let staffMember = repo.user(id: completion.completedBy)
                        
                        taskLogRow(
                            name: staffMember?.fullName ?? "Staff",
                            task: task?.title ?? "Task Completed",
                            time: formatTime(completion.completedAt),
                            verified: completion.completed,
                            hasPhoto: !(completion.staffPhotoUrl ?? "").isEmpty
                        )
                        
                        if index < recentCompletions.count - 1 {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                        .fill(Theme.card)
                )
            }
        }
    }
    
    private func taskLogRow(name: String, task: String, time: String, verified: Bool, hasPhoto: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: verified ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(verified ? Theme.accent : Theme.warning)
                .font(.subheadline)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Assigned to \(name)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(time)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                if verified {
                    Text(hasPhoto ? "Photo Verified" : "Completed")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(14)
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return RosterFormat.time(date)
    }
}

#Preview {
    ManagerDashboardView()
        .environment(RosterRepository())
}