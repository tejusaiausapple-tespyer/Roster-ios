import SwiftUI
import PhotosUI

/// Manager Tasks tab: day-by-day view of every task, live completion status,
/// creation/editing, and photo review (see docs/tasks-feature.md for the
/// photo lifecycle).
struct ManagerTasksView: View {
    @Environment(RosterRepository.self) private var repository
    @State private var weekOffset: Int = 0
    @State private var selectedDayKey: String = RosterCalendar.todayKey()
    @State private var filter: TaskFilter = .all
    @State private var activeSheet: TasksSheet?

    private enum TasksSheet: Identifiable {
        case editor(RosterTask?)
        case review(RosterTask)
        var id: String {
            switch self {
            case .editor(let t): return "editor-\(t?.id ?? "new")"
            case .review(let t): return "review-\(t.id ?? "review")"
            }
        }
    }

    enum TaskFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case completed = "Completed"
        case overdue = "Overdue"
    }

    private var monday: Date {
        RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart())
    }

    private var bounds: (min: Int, max: Int) {
        BusinessRules.shiftWeekOffsetBounds()
    }

    private var selectedDayDate: Date {
        RosterCalendar.dateFromKey(selectedDayKey) ?? Date()
    }

    private var weekday: Int {
        let raw = RosterCalendar.calendar.component(.weekday, from: selectedDayDate)
        return raw == 1 ? 7 : raw - 1
    }

    private var tasksForDay: [RosterTask] {
        repository.tasks
            .filter { $0.isActive(onDayKey: selectedDayKey, weekday: weekday) }
            .sorted { a, b in
                let ac = isCompleted(a), bc = isCompleted(b)
                if ac != bc { return !ac }
                if a.priorityLevel.weight != b.priorityLevel.weight {
                    return a.priorityLevel.weight < b.priorityLevel.weight
                }
                return (a.dueTime ?? "99:99") < (b.dueTime ?? "99:99")
            }
    }

    private var filteredTasks: [RosterTask] {
        switch filter {
        case .all: return tasksForDay
        case .pending: return tasksForDay.filter { !isCompleted($0) }
        case .completed: return tasksForDay.filter { isCompleted($0) }
        case .overdue: return tasksForDay.filter { isOverdue($0) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if filteredTasks.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredTasks) { task in
                                    taskCard(task)
                                }
                            }
                            .padding(.horizontal, Theme.screenPadding)
                            .padding(.bottom, 24)
                            .tracksTitlePillCollapse()
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitlePill(title: "Tasks", icon: "list.bullet.clipboard")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .editor(nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.brand)
                    }
                    .accessibilityLabel("New task")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editor(let task):
                    ManagerTaskEditorSheet(task: task, defaultDateKey: selectedDayKey)
                case .review(let task):
                    ManagerTaskDetailSheet(task: task, dateKey: selectedDayKey) {
                        activeSheet = .editor(task)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    miniStat(value: "\(tasksForDay.count)", label: "Tasks")
                    miniStat(value: "\(tasksForDay.filter { isCompleted($0) }.count)", label: "Done", tint: Theme.accent)
                    miniStat(value: "\(tasksForDay.filter { !isCompleted($0) }.count)", label: "Pending",
                             tint: tasksForDay.contains { !isCompleted($0) } ? Theme.warning : Theme.textSecondary)
                    miniStat(value: "\(tasksForDay.filter { isOverdue($0) }.count)", label: "Overdue",
                             tint: tasksForDay.contains { isOverdue($0) } ? Theme.error : Theme.textSecondary)
                }
                WeekSelector(
                    monday: monday,
                    selectedKey: $selectedDayKey,
                    canGoPrev: weekOffset > bounds.min,
                    canGoNext: weekOffset < bounds.max,
                    onPrev: { if weekOffset > bounds.min { weekOffset -= 1 } },
                    onNext: { if weekOffset < bounds.max { weekOffset += 1 } },
                    onToday: { weekOffset = 0; selectedDayKey = RosterCalendar.todayKey() },
                    onSelect: { key in selectedDayKey = key }
                )
                Picker("Filter", selection: $filter) {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .fill(Theme.card)
            )
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            EmptyStateView(
                icon: "checklist",
                title: filter == .all ? "No Tasks Scheduled" : "Nothing Here",
                message: filter == .all
                    ? "Tap + to create a task for this date."
                    : "No \(filter.rawValue.lowercased()) tasks for this date."
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func taskCard(_ task: RosterTask) -> some View {
        let completed = isCompleted(task)
        let overdue = isOverdue(task)
        let completion = completion(for: task)

        return Button {
            activeSheet = .review(task)
        } label: {
            Card(accentColor: completed ? Theme.accent : (overdue ? Theme.error : Theme.warning)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if task.priorityLevel == .high {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.error)
                                }
                                Text(task.title)
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            HStack(spacing: 8) {
                                chip(frequencyLabel(task), icon: "repeat")
                                if let due = task.dueTime {
                                    chip("Due \(due)", icon: "clock",
                                         tint: overdue ? Theme.error : Theme.textSecondary)
                                }
                                if !task.photoRequired {
                                    chip("Tick only", icon: "checkmark.square")
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(completed ? Theme.accent : Theme.textTertiary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        Text(assigneeSummary(task))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        if completed, let comp = completion {
                            Text(completerName(comp))
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        } else if let comp = completion, comp.isRedoRequested {
                            Text("Redo requested")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func isCompleted(_ task: RosterTask) -> Bool {
        repository.taskCompletions.contains { $0.taskId == task.id && $0.date == selectedDayKey && $0.completed }
    }

    private func completion(for task: RosterTask) -> TaskCompletion? {
        repository.taskCompletions.first { $0.taskId == task.id && $0.date == selectedDayKey }
    }

    private func isOverdue(_ task: RosterTask) -> Bool {
        guard !isCompleted(task), let due = task.dueTime else { return false }
        let todayKey = RosterCalendar.todayKey()
        if selectedDayKey < todayKey { return true }
        guard selectedDayKey == todayKey else { return false }
        return RosterFormat.hhmm(Date()) > due
    }

    private func frequencyLabel(_ task: RosterTask) -> String {
        switch task.frequency {
        case "once": return "One-off"
        case "weekly": return "Weekly"
        default: return "Daily"
        }
    }

    private func assigneeSummary(_ task: RosterTask) -> String {
        guard let ids = task.assignedTo, !ids.isEmpty else { return "All staff" }
        let names = ids.compactMap { id in
            repository.user(id: id)?.firstName
        }
        return names.isEmpty ? "All staff" : names.joined(separator: ", ")
    }

    private func completerName(_ comp: TaskCompletion) -> String {
        repository.user(id: comp.completedBy)?.firstName ?? "Staff"
    }

    private func chip(_ text: String, icon: String, tint: Color = Theme.textSecondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.background)
        .clipShape(Capsule())
    }

    private func miniStat(value: String, label: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .default).weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}
