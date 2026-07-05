import SwiftUI
import FirebaseAuth

struct ManagerDashboardView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var showNewShiftEditor = false

    private var todayKey: String {
        RosterCalendar.todayKey()
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: Date())
    }
    
    private var weekday: Int {
        let raw = RosterCalendar.calendar.component(.weekday, from: Date())
        if raw == 1 { return 7 }
        return raw - 1
    }
    
    // MARK: - Computed Properties (Live Data)
    
    private var todaysShifts: [Shift] {
        repo.shifts
            .filter { $0.date == todayKey }
            .sorted { $0.rosteredStart < $1.rosteredStart }
    }

    /// Scheduled to be running right now (start ≤ now < end, Adelaide time).
    /// Placeholder until the Staff Portal gains a "Start Shift" action that
    /// records actual start times.
    private func isInProgress(_ shift: Shift, at now: Date = Date()) -> Bool {
        now >= shift.startDateTime && now < shift.endDateTime
    }
    
    private var activeStaffCount: Int {
        todaysShifts.filter { shift in
            repo.timesheets.contains(where: { $0.shiftId == shift.id })
        }.count
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
    
    private var recentCompletions: [TaskCompletion] {
        repo.taskCompletions
            .filter { $0.date == todayKey }
            .sorted { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Hero Header Card
                        headerCard
                        
                        // Live Metrics Grid
                        metricsGrid
                        
                        // Main Sections: 2-column on iPad/Mac, 1-column on iPhone
                        if UIDevice.current.userInterfaceIdiom == .phone {
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
                }
                .refreshable {
                    await repo.refreshFromServer()
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitlePill(title: "Dashboard", icon: "square.grid.2x2.fill")
                }
            }
            .sheet(isPresented: $showNewShiftEditor) {
                ManagerShiftEditorSheet(defaultDateKey: todayKey)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SURA INVESTMENTS PTY LTD")
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
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        
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
            metricCard(
                value: "\(pendingTimesheetsCount) Awaiting",
                label: "Pending Timesheets",
                icon: "doc.text.badge.clock",
                color: pendingTimesheetsCount > 0 ? Theme.warning : Theme.textSecondary
            )
        }
    }
    
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
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
            }
            Spacer()
        }
        .padding(12)
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
            
            HStack(spacing: 12) {
                actionButton(title: "New Shift", icon: "calendar.badge.plus", color: Theme.brand) {
                    showNewShiftEditor = true
                }
                NavigationLink {
                    ManagerPlaceholderView(tab: .tasks)
                } label: {
                    actionLabel(title: "New Task", icon: "checkmark.circle.badge.questionmark", color: Theme.accent)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    ManagerStaffView(embedInNavigationStack: false)
                } label: {
                    actionLabel(title: "Staff Directory", icon: "person.2.fill", color: Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title: title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
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
                VStack(spacing: 0) {
                    ForEach(Array(todaysShifts.enumerated()), id: \.element.id) { index, shift in
                        let staffMember = repo.allUsers.first(where: { $0.id == shift.staffId })
                        let hasTimesheet = repo.timesheets.contains(where: { $0.shiftId == shift.id })
                        let inProgress = isInProgress(shift)

                        rosterRow(
                            name: staffMember?.fullName ?? "Staff Member",
                            role: shift.department ?? "General",
                            time: "\(shift.rosteredStart) - \(shift.rosteredEnd)",
                            status: inProgress ? "In Progress" : (hasTimesheet ? "Submitted" : "Scheduled"),
                            isClockedIn: hasTimesheet,
                            inProgress: inProgress
                        )

                        if index < todaysShifts.count - 1 {
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
    
    private func rosterRow(name: String, role: String, time: String, status: String,
                           isClockedIn: Bool, inProgress: Bool = false) -> some View {
        // In-progress (scheduled to be running right now) takes visual
        // priority: brand highlight + pulsing-style dot. Otherwise green for
        // a submitted timesheet, grey for merely scheduled.
        let tint: Color = inProgress ? Theme.brand : (isClockedIn ? Theme.accent : Theme.textTertiary)

        return HStack(spacing: 12) {
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
            }

            Spacer()

            Text(status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.12)))
        }
        .padding(14)
        .background(inProgress ? Theme.brand.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            if inProgress {
                Rectangle().fill(Theme.brand).frame(width: 3)
            }
        }
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
                        let staffMember = repo.allUsers.first(where: { $0.id == completion.completedBy })
                        
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ManagerDashboardView()
        .environment(RosterRepository())
}