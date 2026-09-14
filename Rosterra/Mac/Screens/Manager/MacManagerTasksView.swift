#if targetEnvironment(macCatalyst)
import SwiftUI
import PhotosUI
import UIKit

struct MacManagerTasksView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var weekOffset = 0
    @State private var selectedDayKey = RosterCalendar.todayKey()
    @State private var filter: TaskFilter = .all
    @State private var searchText = ""
    @State private var selectedTaskID: String?
    @State private var editorTarget: EditorTarget?
    @State private var redoTask: RosterTask?
    @State private var redoReason = ""
    @State private var taskToDelete: RosterTask?
    @State private var photoTarget: PhotoTarget?
    @State private var isWorking = false

    private enum TaskFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case pending = "Pending"
        case completed = "Completed"
        case overdue = "Overdue"
        case paused = "Paused"

        var id: String { rawValue }
    }

    private enum EditorTarget: Identifiable {
        case create
        case edit(RosterTask)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let task): return "edit-\(task.id ?? "task")"
            }
        }

        var task: RosterTask? {
            switch self {
            case .create: return nil
            case .edit(let task): return task
            }
        }
    }

    private struct PhotoTarget: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var monday: Date {
        RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart())
    }

    private var weekDays: [Date] {
        RosterCalendar.weekDays(for: monday)
    }

    private var bounds: (min: Int, max: Int) {
        BusinessRules.shiftWeekOffsetBounds()
    }

    private var selectedDayDate: Date {
        RosterCalendar.dateFromKey(selectedDayKey) ?? Date()
    }

    private var selectedWeekday: Int {
        let raw = RosterCalendar.calendar.component(.weekday, from: selectedDayDate)
        return raw == 1 ? 7 : raw - 1
    }

    private var tasksForDay: [RosterTask] {
        repo.tasks
            .filter {
                $0.isScheduled(
                    onDayKey: selectedDayKey,
                    weekday: selectedWeekday
                )
            }
            .sorted { lhs, rhs in
                if lhs.active != rhs.active { return lhs.active }
                let lhsCompleted = isCompleted(lhs)
                let rhsCompleted = isCompleted(rhs)
                if lhsCompleted != rhsCompleted { return !lhsCompleted }
                if lhs.priorityLevel.weight != rhs.priorityLevel.weight {
                    return lhs.priorityLevel.weight < rhs.priorityLevel.weight
                }
                if (lhs.dueTime ?? "99:99") != (rhs.dueTime ?? "99:99") {
                    return (lhs.dueTime ?? "99:99") < (rhs.dueTime ?? "99:99")
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var filteredTasks: [RosterTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasksForDay.filter { task in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .pending:
                matchesFilter = task.active && !isCompleted(task)
            case .completed:
                matchesFilter = isCompleted(task)
            case .overdue:
                matchesFilter = isOverdue(task)
            case .paused:
                matchesFilter = !task.active
            }

            let matchesSearch = query.isEmpty
                || task.title.localizedCaseInsensitiveContains(query)
                || (task.description?.localizedCaseInsensitiveContains(query) ?? false)
                || assigneeSummary(task).localizedCaseInsensitiveContains(query)

            return matchesFilter && matchesSearch
        }
    }

    private var selectedTask: RosterTask? {
        guard let selectedTaskID else { return filteredTasks.first }
        return filteredTasks.first { $0.id == selectedTaskID } ?? filteredTasks.first
    }

    private var completedCount: Int {
        tasksForDay.filter { isCompleted($0) }.count
    }

    private var pendingCount: Int {
        tasksForDay.filter { $0.active && !isCompleted($0) }.count
    }

    private var overdueCount: Int {
        tasksForDay.filter { isOverdue($0) }.count
    }

    private var pausedCount: Int {
        tasksForDay.filter { !$0.active }.count
    }

    var body: some View {
        MacScreen(
            title: "Team Tasks",
            subtitle: "\(formattedSelectedDate) · \(tasksForDay.count) scheduled"
        ) {
            GeometryReader { geometry in
                VStack(spacing: MacSpace.md) {
                    dateControls
                    filterControls
                    summaryStrip

                    HStack(spacing: 0) {
                        taskQueue
                            .frame(
                                width: min(
                                    440,
                                    max(360, geometry.size.width * 0.39)
                                )
                            )

                        Rectangle()
                            .fill(MacColor.separator)
                            .frame(width: 1)

                        if let selectedTask {
                            taskInspector(selectedTask)
                        } else {
                            MacEmptyState(
                                title: filteredTasks.isEmpty ? "No tasks found" : "Select a task",
                                subtitle: emptyMessage,
                                icon: filteredTasks.isEmpty ? "checklist.unchecked" : "checklist"
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .background(
                        MacColor.cardBackground,
                        in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                            .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
                }
                .padding(.horizontal, MacSpace.xl)
                .padding(.bottom, MacSpace.xl)
            }
        }
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    refreshToolbarButton
                    .accessibilityLabel("Refresh tasks")
                    .help("Refresh tasks")
                }

                ToolbarSpacer(.fixed, placement: .primaryAction)

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New task")
                    .help("New task")
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    refreshToolbarButton
                    .accessibilityLabel("Refresh tasks")

                    Button {
                        editorTarget = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New task")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            MacTaskEditorSheet(
                task: target.task,
                defaultDateKey: selectedDayKey
            )
            .macObserved(repo: repo, toasts: toasts)
        }
        .sheet(item: $photoTarget) { target in
            FullscreenImageView(url: target.url)
        }
        .alert("Request redo", isPresented: redoAlertPresented) {
            TextField("Reason", text: $redoReason)
            Button("Cancel", role: .cancel) {
                redoTask = nil
            }
            Button("Send request", role: .destructive) {
                requestRedo()
            }
            .disabled(redoReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The task reopens for this day and the staff member sees your reason.")
        }
        .alert("Delete this task?", isPresented: deleteAlertPresented) {
            Button("Cancel", role: .cancel) {
                taskToDelete = nil
            }
            Button("Delete task", role: .destructive) {
                deleteSelectedTask()
            }
        } message: {
            Text("The task is removed from every day it repeats. Completion history is retained.")
        }
        .onAppear {
            alignSelectedDayToDisplayedWeek()
            maintainSelection()
        }
        .onChange(of: filteredTasks.compactMap(\.id)) { _, _ in
            maintainSelection()
        }
    }

    private var refreshToolbarButton: some View {
        MacRefreshButton("Refresh tasks") {
            await repo.refreshFromServer()
        }
    }

    private var dateControls: some View {
        HStack(spacing: MacSpace.sm) {
            Button {
                moveWeek(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .macButton(.bordered, size: .small)
            .disabled(weekOffset <= bounds.min)
            .accessibilityLabel("Previous week")

            Button {
                weekOffset = 0
                selectedDayKey = RosterCalendar.todayKey()
            } label: {
                HStack(spacing: 6) {
                    Text(weekLabel)
                    if weekOffset != 0 || selectedDayKey != RosterCalendar.todayKey() {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .padding(.horizontal, MacSpace.md)
                .frame(minHeight: 36)
                .macGlassSurface(cornerRadius: MacRadius.pill)
            }
            .buttonStyle(.plain)
            .help("Return to today")

            Button {
                moveWeek(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .macButton(.bordered, size: .small)
            .disabled(weekOffset >= bounds.max)
            .accessibilityLabel("Next week")

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    dayButton(day)
                }
            }
            .padding(.leading, MacSpace.sm)

            Spacer(minLength: 0)
        }
        .padding(.top, MacSpace.md)
    }

    private var filterControls: some View {
        HStack(spacing: MacSpace.md) {
            HStack(spacing: 6) {
                ForEach(TaskFilter.allCases) { option in
                    filterButton(option)
                }
            }

            Spacer(minLength: MacSpace.lg)

            HStack(spacing: MacSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MacColor.textTertiary)
                TextField("Search task or assignee", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MacType.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MacColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, MacSpace.md)
            .frame(width: 300)
            .frame(minHeight: 40)
            .background(
                MacColor.cardBackground,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryMetric(
                title: "Scheduled",
                value: "\(tasksForDay.count)",
                icon: "checklist",
                tint: MacColor.textPrimary
            )
            summaryDivider
            summaryMetric(
                title: "Completed",
                value: "\(completedCount)",
                icon: "checkmark.circle.fill",
                tint: MacColor.success
            )
            summaryDivider
            summaryMetric(
                title: "Pending",
                value: "\(pendingCount)",
                icon: "hourglass",
                tint: pendingCount > 0 ? MacColor.warning : MacColor.textTertiary
            )
            summaryDivider
            summaryMetric(
                title: "Overdue",
                value: "\(overdueCount)",
                icon: "exclamationmark.triangle.fill",
                tint: overdueCount > 0 ? MacColor.error : MacColor.textTertiary
            )
            summaryDivider
            summaryMetric(
                title: "Paused",
                value: "\(pausedCount)",
                icon: "pause.circle.fill",
                tint: MacColor.textTertiary
            )
        }
        .padding(.vertical, MacSpace.sm)
        .macGlassSurface(cornerRadius: MacRadius.large)
    }

    private var taskQueue: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TASKS")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.textTertiary)
                Spacer()
                Text("\(filteredTasks.count)")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textSecondary)
            }
            .padding(.horizontal, MacSpace.lg)
            .frame(height: 44)
            .background(MacColor.tableHeaderBackground)

            if filteredTasks.isEmpty {
                MacEmptyState(
                    title: "No tasks found",
                    subtitle: emptyMessage,
                    icon: "checklist.unchecked"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(MacSpace.sm)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(MacColor.cardBackgroundSecondary)
    }

    private func taskRow(_ task: RosterTask) -> some View {
        let selected = selectedTaskID == task.id
            || (selectedTaskID == nil && filteredTasks.first?.id == task.id)
        let status = taskStatus(task)

        return Button {
            selectedTaskID = task.id
        } label: {
            VStack(alignment: .leading, spacing: MacSpace.sm) {
                HStack(alignment: .top, spacing: MacSpace.sm) {
                    Image(systemName: status.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(status.tint)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(task.title)
                                .font(MacType.bodyStrong)
                                .foregroundStyle(MacColor.textPrimary)
                                .lineLimit(2)
                            if task.priorityLevel == .high {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(MacColor.error)
                                    .help("High priority")
                            }
                        }

                        Text(assigneeSummary(task))
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: MacSpace.sm)

                    Text(status.label)
                        .font(MacType.badge)
                        .foregroundStyle(status.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(status.tint.opacity(0.10), in: Capsule())
                }

                HStack(spacing: MacSpace.md) {
                    Label(frequencyLabel(task), systemImage: "repeat")
                    if let due = task.dueTime {
                        Label(RosterFormat.time(due), systemImage: "clock")
                    }
                    Label(
                        task.photoRequired ? "Photo proof" : "Tick only",
                        systemImage: task.photoRequired ? "camera" : "checkmark.square"
                    )
                }
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .lineLimit(1)
            }
            .padding(MacSpace.md)
            .background(
                selected ? MacColor.tableRowSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                editorTarget = .edit(task)
            }
        )
        .contextMenu {
            Button {
                editorTarget = .edit(task)
            } label: {
                Label("Edit task", systemImage: "pencil")
            }
            Button {
                toggleActive(task)
            } label: {
                Label(
                    task.active ? "Pause task" : "Resume task",
                    systemImage: task.active ? "pause.circle" : "play.circle"
                )
            }
            Divider()
            Button(role: .destructive) {
                taskToDelete = task
            } label: {
                Label("Delete task", systemImage: "trash")
            }
        }
    }

    private func taskInspector(_ task: RosterTask) -> some View {
        let status = taskStatus(task)
        let completion = completion(for: task)

        return ScrollView {
            VStack(alignment: .leading, spacing: MacSpace.xl) {
                HStack(alignment: .top, spacing: MacSpace.lg) {
                    Image(systemName: status.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(status.tint)
                        .frame(width: 52, height: 52)
                        .background(status.tint.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: MacSpace.sm) {
                            Text(task.title)
                                .font(MacType.pageTitle)
                                .foregroundStyle(MacColor.textPrimary)
                            if task.priorityLevel != .normal {
                                priorityPill(task.priorityLevel)
                            }
                        }
                        Text("\(frequencyLabel(task)) · \(assigneeSummary(task))")
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    Spacer()

                    Button {
                        editorTarget = .edit(task)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .macButton(.prominent)
                }

                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textSecondary)
                        .textSelection(.enabled)
                        .padding(MacSpace.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            MacColor.cardBackgroundSecondary,
                            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                        )
                }

                HStack(spacing: MacSpace.md) {
                    inspectorMetric(
                        title: "Status",
                        value: status.label,
                        icon: status.icon,
                        tint: status.tint
                    )
                    inspectorMetric(
                        title: "Due",
                        value: task.dueTime.map(RosterFormat.time) ?? "No time",
                        icon: "clock",
                        tint: isOverdue(task) ? MacColor.error : MacColor.textPrimary
                    )
                    inspectorMetric(
                        title: "Completion",
                        value: task.photoRequired ? "Photo proof" : "Tick only",
                        icon: task.photoRequired ? "camera.fill" : "checkmark.square.fill",
                        tint: MacColor.info
                    )
                }

                HStack(alignment: .top, spacing: MacSpace.md) {
                    detailCard(title: "Schedule", icon: "calendar") {
                        inspectorRow("Repeats", frequencyLabel(task))
                        if task.frequency == "once" {
                            inspectorRow("Date", formattedTaskDate(task.date))
                        } else if task.frequency == "weekly" {
                            inspectorRow("Days", weekdaySummary(task.dayOfWeek))
                        }
                        if task.frequency != "once" {
                            inspectorRow("Ends", formattedTaskDate(task.endDate))
                        }
                    }

                    detailCard(title: "Assignment", icon: "person.2") {
                        inspectorRow("Assigned to", assigneeSummary(task))
                        inspectorRow("Priority", task.priorityLevel.label)
                        inspectorRow("Task state", task.active ? "Active" : "Paused")
                    }
                }

                if let urlString = task.managerPhotoUrl,
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    referencePhoto(url)
                }

                completionSection(task: task, completion: completion)

                HStack(spacing: MacSpace.md) {
                    Button {
                        toggleActive(task)
                    } label: {
                        Label(
                            task.active ? "Pause task" : "Resume task",
                            systemImage: task.active ? "pause.circle" : "play.circle"
                        )
                    }
                    .macButton(.bordered)
                    .disabled(isWorking)

                    Spacer()

                    Button {
                        taskToDelete = task
                    } label: {
                        Label("Delete task", systemImage: "trash")
                    }
                    .macButton(.destructive)
                    .disabled(isWorking)
                }
            }
            .padding(MacSpace.xxl)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.cardBackground)
    }

    @ViewBuilder
    private func completionSection(
        task: RosterTask,
        completion: TaskCompletion?
    ) -> some View {
        if let completion, completion.completed {
            detailCard(title: "Completion report", icon: "checkmark.seal.fill") {
                inspectorRow(
                    "Completed by",
                    repo.user(id: completion.completedBy)?.fullName ?? "Staff"
                )
                inspectorRow(
                    "Completed",
                    completion.completedAt.map(RosterFormat.dateTime) ?? "—"
                )
                if let note = completion.note, !note.isEmpty {
                    inspectorRow("Staff note", note)
                }

                if task.photoRequired {
                    Text("Verification photos")
                        .font(MacType.captionStrong)
                        .foregroundStyle(MacColor.textTertiary)
                        .padding(.top, MacSpace.sm)

                    TaskPhotoView(
                        taskId: task.id ?? "",
                        date: selectedDayKey,
                        urlStrings: completion.photoUrls
                    )

                    if !completion.photoUrls.isEmpty {
                        Button {
                            deleteCloudPhotos(completion)
                        } label: {
                            Label(
                                "Reviewed — remove cloud photos",
                                systemImage: "icloud.slash"
                            )
                        }
                        .macButton(.bordered)
                        .disabled(isWorking)
                    }
                }

                Button {
                    redoReason = ""
                    redoTask = task
                } label: {
                    Label("Request redo", systemImage: "arrow.uturn.backward")
                }
                .macButton(.bordered)
                .disabled(isWorking)
                .padding(.top, MacSpace.sm)
            }
        } else if let completion, completion.isRedoRequested {
            HStack(alignment: .top, spacing: MacSpace.md) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MacColor.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Redo requested")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    if let reason = completion.redoReason, !reason.isEmpty {
                        Text(reason)
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }
                    Text("Waiting for the staff member to resubmit.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }
                Spacer()
            }
            .padding(MacSpace.lg)
            .background(
                MacColor.warning.opacity(0.10),
                in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
            )
        } else {
            HStack(spacing: MacSpace.md) {
                Image(systemName: task.active ? "hourglass" : "pause.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(task.active ? MacColor.warning : MacColor.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.active ? "Waiting for completion" : "Task paused")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    Text(
                        task.active
                            ? "No completion has been submitted for this day."
                            : "Resume the task when it should appear for staff again."
                    )
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
                }
                Spacer()
            }
            .padding(MacSpace.lg)
            .background(
                MacColor.cardBackgroundSecondary,
                in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
            )
        }
    }

    private func referencePhoto(_ url: URL) -> some View {
        detailCard(title: "Reference photo", icon: "photo") {
            Button {
                photoTarget = PhotoTarget(url: url)
            } label: {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 220)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: MacRadius.medium,
                                    style: .continuous
                                )
                            )
                    case .failure:
                        Label("Unable to load reference photo", systemImage: "photo.badge.exclamationmark")
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Open full size")
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let key = RosterCalendar.dateString(from: day)
        let selected = key == selectedDayKey
        let today = key == RosterCalendar.todayKey()
        let scheduledCount = taskCount(on: day, key: key)

        return Button {
            selectedDayKey = key
        } label: {
            VStack(spacing: 2) {
                Text(weekdayShort(day))
                    .font(MacType.badge)
                Text("\(RosterCalendar.calendar.component(.day, from: day))")
                    .font(MacType.bodyStrong)
                Circle()
                    .fill(
                        scheduledCount > 0
                            ? (selected ? Color.white : MacColor.warning)
                            : Color.clear
                    )
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(selected ? Color.white : MacColor.textPrimary)
            .frame(width: 54, height: 54)
            .background(
                selected
                    ? MacColor.textPrimary
                    : (today ? MacColor.tableRowSelected : MacColor.cardBackground),
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(
                        selected ? Color.clear : MacColor.cardBorder,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(RosterFormat.date(key)), \(scheduledCount) tasks"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func filterButton(_ option: TaskFilter) -> some View {
        let selected = filter == option
        let count = filterCount(option)
        return Button {
            filter = option
        } label: {
            HStack(spacing: 6) {
                Text(option.rawValue)
                Text("\(count)")
                    .font(MacType.badge)
                    .foregroundStyle(
                        selected ? Color.white.opacity(0.8) : MacColor.textTertiary
                    )
            }
            .font(MacType.captionStrong)
            .foregroundStyle(selected ? Color.white : MacColor.textPrimary)
            .padding(.horizontal, MacSpace.md)
            .frame(minHeight: 36)
            .background(
                selected ? MacColor.textPrimary : MacColor.cardBackground,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(selected ? Color.clear : MacColor.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(MacColor.separator)
            .frame(width: 1, height: 38)
    }

    private func summaryMetric(
        title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: MacSpace.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
            Text(title)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
        }
        .padding(.horizontal, MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorMetric(
        title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.sm) {
            Label(title.uppercased(), systemImage: icon)
                .font(MacType.badge)
                .foregroundStyle(tint)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MacColor.cardBackgroundSecondary,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func detailCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            Label(title, systemImage: icon)
                .font(MacType.sectionHeader)
                .foregroundStyle(MacColor.textPrimary)
            content()
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            MacColor.cardBackgroundSecondary,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
            Spacer(minLength: MacSpace.md)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func priorityPill(_ priority: TaskPriority) -> some View {
        let tint = priority == .high ? MacColor.error : MacColor.textTertiary
        return MacStatusPill(
            text: priority.label,
            foreground: tint,
            background: tint.opacity(0.10),
            border: tint.opacity(0.25),
            icon: priority == .high ? "exclamationmark.circle.fill" : "arrow.down.circle"
        )
    }

    private func taskStatus(_ task: RosterTask) -> (
        label: String,
        icon: String,
        tint: Color
    ) {
        if !task.active {
            return ("Paused", "pause.circle.fill", MacColor.textTertiary)
        }
        if isCompleted(task) {
            return ("Completed", "checkmark.circle.fill", MacColor.success)
        }
        if completion(for: task)?.isRedoRequested == true {
            return ("Redo", "arrow.uturn.backward.circle.fill", MacColor.warning)
        }
        if isOverdue(task) {
            return ("Overdue", "exclamationmark.triangle.fill", MacColor.error)
        }
        return ("Pending", "hourglass", MacColor.warning)
    }

    private func completion(for task: RosterTask) -> TaskCompletion? {
        repo.taskCompletions.first {
            $0.taskId == task.id && $0.date == selectedDayKey
        }
    }

    private func isCompleted(_ task: RosterTask) -> Bool {
        completion(for: task)?.completed == true
    }

    private func isOverdue(_ task: RosterTask) -> Bool {
        guard task.active, !isCompleted(task), let due = task.dueTime else {
            return false
        }
        let today = RosterCalendar.todayKey()
        if selectedDayKey < today { return true }
        guard selectedDayKey == today else { return false }
        return RosterFormat.hhmm(Date()) > due
    }

    private func assigneeSummary(_ task: RosterTask) -> String {
        guard let ids = task.assignedTo, !ids.isEmpty else {
            return "All staff"
        }
        let names = ids.compactMap { repo.user(id: $0)?.firstName }
        if names.isEmpty { return "\(ids.count) selected" }
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
    }

    private func frequencyLabel(_ task: RosterTask) -> String {
        switch task.frequency {
        case "once": return "One-off"
        case "weekly": return "Weekly"
        default: return "Daily"
        }
    }

    private func weekdaySummary(_ days: [Int]?) -> String {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let selected = (days ?? []).compactMap { day in
            labels.indices.contains(day - 1) ? labels[day - 1] : nil
        }
        return selected.isEmpty ? "No days" : selected.joined(separator: ", ")
    }

    private func formattedTaskDate(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "No end date" }
        return RosterFormat.date(key)
    }

    private var formattedSelectedDate: String {
        RosterFormat.date(selectedDayKey)
    }

    private var weekLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        case let value where value > 1: return "In \(value) weeks"
        default: return "\(-weekOffset) weeks ago"
        }
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "No tasks match “\(searchText)”."
        }
        switch filter {
        case .all: return "Create a task for this date."
        default: return "No \(filter.rawValue.lowercased()) tasks for this date."
        }
    }

    private var redoAlertPresented: Binding<Bool> {
        Binding(
            get: { redoTask != nil },
            set: { if !$0 { redoTask = nil } }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        )
    }

    private func filterCount(_ option: TaskFilter) -> Int {
        switch option {
        case .all: return tasksForDay.count
        case .pending: return pendingCount
        case .completed: return completedCount
        case .overdue: return overdueCount
        case .paused: return pausedCount
        }
    }

    private func taskCount(on day: Date, key: String) -> Int {
        let raw = RosterCalendar.calendar.component(.weekday, from: day)
        let weekday = raw == 1 ? 7 : raw - 1
        return repo.tasks.filter {
            $0.isScheduled(onDayKey: key, weekday: weekday)
        }.count
    }

    private func weekdayShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = RosterCalendar.calendar
        formatter.timeZone = RosterCalendar.timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func moveWeek(_ amount: Int) {
        let next = weekOffset + amount
        guard next >= bounds.min, next <= bounds.max else { return }
        weekOffset = next
        selectedDayKey = RosterCalendar.dateString(
            from: RosterCalendar.addDays(amount * 7, to: selectedDayDate)
        )
    }

    private func alignSelectedDayToDisplayedWeek() {
        guard !weekDays.contains(where: {
            RosterCalendar.dateString(from: $0) == selectedDayKey
        }) else { return }
        selectedDayKey = RosterCalendar.dateString(from: monday)
    }

    private func maintainSelection() {
        if let selectedTaskID,
           filteredTasks.contains(where: { $0.id == selectedTaskID }) {
            return
        }
        selectedTaskID = filteredTasks.first?.id
    }

    private func toggleActive(_ task: RosterTask) {
        guard let id = task.id else { return }
        isWorking = true
        Task {
            do {
                try await repo.setTaskActive(id: id, active: !task.active)
                toasts.show(
                    task.active ? "Task paused" : "Task resumed",
                    style: .success
                )
            } catch {
                toasts.show(error.localizedDescription, style: .error)
            }
            isWorking = false
        }
    }

    private func requestRedo() {
        guard let task = redoTask,
              let completion = completion(for: task) else { return }
        let reason = redoReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }

        redoTask = nil
        isWorking = true
        Task {
            do {
                try await repo.requestTaskRedo(
                    completion: completion,
                    reason: reason
                )
                toasts.show("Redo requested", style: .success)
            } catch {
                toasts.show(error.localizedDescription, style: .error)
            }
            isWorking = false
        }
    }

    private func deleteCloudPhotos(_ completion: TaskCompletion) {
        isWorking = true
        Task {
            do {
                try await repo.deleteTaskCloudPhoto(completion: completion)
                toasts.show("Cloud photos removed", style: .success)
            } catch {
                toasts.show(error.localizedDescription, style: .error)
            }
            isWorking = false
        }
    }

    private func deleteSelectedTask() {
        guard let task = taskToDelete, let id = task.id else { return }
        taskToDelete = nil
        isWorking = true
        Task {
            do {
                try await repo.deleteTask(
                    id: id,
                    managerPhotoUrl: task.managerPhotoUrl
                )
                toasts.show("Task deleted", style: .info)
            } catch {
                toasts.show(error.localizedDescription, style: .error)
            }
            isWorking = false
        }
    }
}

private struct MacTaskEditorSheet: View {
    let task: RosterTask?
    let defaultDateKey: String

    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var frequency = "once"
    @State private var onceDate = Date()
    @State private var weekdays: Set<Int> = []
    @State private var assignToAll = true
    @State private var assignedIDs: Set<String> = []
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var priority: TaskPriority = .normal
    @State private var requiresPhoto = true
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var referenceImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var didPopulate = false

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var staffUsers: [AppUser] {
        repo.allUsers
            .filter {
                $0.role == .staff
                    && ($0.status == .active || assignedIDs.contains($0.id))
            }
            .sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (frequency != "weekly" || !weekdays.isEmpty)
            && (assignToAll || !assignedIDs.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .top, spacing: 0) {
                taskColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Rectangle()
                    .fill(MacColor.separator)
                    .frame(width: 1)
                    .padding(.vertical, MacSpace.lg)

                scheduleColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, MacSpace.xl)

            footer
        }
        .frame(width: 920)
        .frame(minHeight: 680)
        .background(MacColor.windowBackground)
        .onAppear(perform: populate)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    referenceImage = image
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: task == nil ? "checklist.checked" : "checklist")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MacColor.textPrimary)
                .frame(width: 42, height: 42)
                .macGlassSurface(cornerRadius: MacRadius.medium)

            VStack(alignment: .leading, spacing: 2) {
                Text(task == nil ? "New task" : "Edit task")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Text("Set the instructions, schedule and staff assignment.")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .macGlassSurface(cornerRadius: MacRadius.pill)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
    }

    private var taskColumn: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            sectionLabel("Task", icon: "text.alignleft")

            field("Title") {
                TextField("What needs to be done?", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(MacType.body)
            }

            field("Instructions") {
                TextField(
                    "Optional details for staff",
                    text: $descriptionText,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
                .font(MacType.body)
            }

            field("Priority") {
                optionRow(TaskPriority.allCases, selection: priority) { option in
                    Button {
                        priority = option
                    } label: {
                        Text(option.label)
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Photo proof")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("Staff must submit a verification photo.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $requiresPhoto)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(MacSpace.md)
            .background(
                MacColor.cardBackground,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }

            referencePhotoEditor
        }
        .padding(.trailing, MacSpace.lg)
    }

    private var scheduleColumn: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            sectionLabel("Schedule & assignment", icon: "calendar")

            field("Repeats") {
                HStack(spacing: 6) {
                    frequencyButton("One-off", value: "once")
                    frequencyButton("Daily", value: "daily")
                    frequencyButton("Weekly", value: "weekly")
                }
            }

            if frequency == "once" {
                field("Date") {
                    DatePicker(
                        "",
                        selection: $onceDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.large)
                    .environment(\.timeZone, RosterCalendar.timeZone)
                }
            } else if frequency == "weekly" {
                field("Days") {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            weekdayButton(day)
                        }
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Due time")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("Show a deadline on active days.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $hasDueTime)
                    .labelsHidden()
                    .toggleStyle(.switch)
                if hasDueTime {
                    DatePicker(
                        "",
                        selection: $dueTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, RosterCalendar.timeZone)
                }
            }

            if frequency != "once" {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("End date")
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)
                        Text("Optionally stop this recurring task.")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $hasEndDate)
                        .labelsHidden()
                        .toggleStyle(.switch)
                    if hasEndDate {
                        DatePicker(
                            "",
                            selection: $endDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, RosterCalendar.timeZone)
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Assign to all staff")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("Turn off to select specific people.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $assignToAll)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(MacSpace.md)
            .background(
                MacColor.cardBackground,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }

            if !assignToAll {
                field("Selected staff") {
                    Menu {
                        ForEach(staffUsers) { staff in
                            Button {
                                if assignedIDs.contains(staff.id) {
                                    assignedIDs.remove(staff.id)
                                } else {
                                    assignedIDs.insert(staff.id)
                                }
                            } label: {
                                Label(
                                    staff.fullName,
                                    systemImage: assignedIDs.contains(staff.id)
                                        ? "checkmark"
                                        : "circle"
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: MacSpace.sm) {
                            Image(systemName: "person.2")
                            Text(assignmentLabel)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textPrimary)
                        .padding(.horizontal, MacSpace.md)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            MacColor.cardBackground,
                            in: RoundedRectangle(
                                cornerRadius: MacRadius.medium,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: MacRadius.medium,
                                style: .continuous
                            )
                            .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.error)
                    .padding(MacSpace.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        MacColor.error.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    )
            }
        }
        .padding(.leading, MacSpace.lg)
    }

    @ViewBuilder
    private var referencePhotoEditor: some View {
        VStack(alignment: .leading, spacing: MacSpace.sm) {
            field("Reference photo") {
                Group {
                    if let referenceImage {
                        Image(uiImage: referenceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 150)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: MacRadius.medium,
                                    style: .continuous
                                )
                            )
                    } else if let urlString = task?.managerPhotoUrl,
                              !urlString.isEmpty,
                              let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Label("Existing photo will be kept", systemImage: "photo")
                                    .font(MacType.caption)
                                    .foregroundStyle(MacColor.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 130)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: MacRadius.medium,
                                style: .continuous
                            )
                        )
                    }
                }
            }

            HStack(spacing: MacSpace.sm) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label(
                        referenceImage == nil ? "Choose photo" : "Replace photo",
                        systemImage: "photo.on.rectangle"
                    )
                }
                .macButton(.bordered, size: .small)

                if referenceImage != nil {
                    Button {
                        referenceImage = nil
                        photoPickerItem = nil
                    } label: {
                        Label("Remove selection", systemImage: "xmark")
                    }
                    .macButton(.ghost, size: .small)
                }
            }

            Text("Optional instruction image. A new selection replaces the existing photo.")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: MacSpace.md) {
            Text(validationHint)
                .font(MacType.caption)
                .foregroundStyle(canSave ? MacColor.textTertiary : MacColor.warning)

            Spacer()

            Button("Cancel") { dismiss() }
                .macButton(.bordered)
                .keyboardShortcut(.cancelAction)

            MacAsyncButton(variant: .prominent) {
                await save()
            } label: {
                Text(task == nil ? "Create task" : "Save changes")
            }
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
        .background(.bar)
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title.uppercased(), systemImage: icon)
            .font(MacType.badge)
            .foregroundStyle(MacColor.textTertiary)
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionRow<Data: RandomAccessCollection, Content: View>(
        _ options: Data,
        selection: Data.Element,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Hashable {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                content(option)
                    .font(MacType.captionStrong)
                    .foregroundStyle(selected ? Color.white : MacColor.textPrimary)
                    .padding(.horizontal, MacSpace.md)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        selected ? MacColor.textPrimary : MacColor.cardBackground,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                selected ? Color.clear : MacColor.cardBorder,
                                lineWidth: 1
                            )
                    }
                    .buttonStyle(.plain)
            }
        }
    }

    private func frequencyButton(_ title: String, value: String) -> some View {
        let selected = frequency == value
        return Button {
            frequency = value
        } label: {
            Text(title)
                .font(MacType.captionStrong)
                .foregroundStyle(selected ? Color.white : MacColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    selected ? MacColor.textPrimary : MacColor.cardBackground,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            selected ? Color.clear : MacColor.cardBorder,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func weekdayButton(_ day: Int) -> some View {
        let selected = weekdays.contains(day)
        return Button {
            if selected {
                weekdays.remove(day)
            } else {
                weekdays.insert(day)
            }
        } label: {
            Text(Self.weekdayNames[day - 1])
                .font(MacType.captionStrong)
                .foregroundStyle(selected ? Color.white : MacColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    selected ? MacColor.textPrimary : MacColor.cardBackground,
                    in: RoundedRectangle(
                        cornerRadius: MacRadius.medium,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: MacRadius.medium,
                        style: .continuous
                    )
                    .strokeBorder(
                        selected ? Color.clear : MacColor.cardBorder,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
    }

    private var assignmentLabel: String {
        if assignedIDs.isEmpty { return "Select staff" }
        let names = staffUsers
            .filter { assignedIDs.contains($0.id) }
            .map(\.firstName)
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
    }

    private var validationHint: String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a task title."
        }
        if frequency == "weekly", weekdays.isEmpty {
            return "Select at least one weekday."
        }
        if !assignToAll, assignedIDs.isEmpty {
            return "Select at least one staff member."
        }
        return task == nil
            ? "Assigned staff are notified after creation."
            : "Staff are notified only if the assignment changes."
    }

    private func populate() {
        guard !didPopulate else { return }
        didPopulate = true

        guard let task else {
            onceDate = RosterCalendar.dateFromKey(defaultDateKey) ?? Date()
            dueTime = RosterCalendar.calendar.date(
                bySettingHour: 17,
                minute: 0,
                second: 0,
                of: onceDate
            ) ?? onceDate
            return
        }

        title = task.title
        descriptionText = task.description ?? ""
        frequency = task.frequency
        if let date = task.date,
           let parsed = RosterCalendar.dateFromKey(date) {
            onceDate = parsed
        }
        weekdays = Set(task.dayOfWeek ?? [])
        if let ids = task.assignedTo, !ids.isEmpty {
            assignToAll = false
            assignedIDs = Set(ids)
        }
        if let due = task.dueTime {
            let parts = due.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2,
               let parsed = RosterCalendar.calendar.date(
                bySettingHour: parts[0],
                minute: parts[1],
                second: 0,
                of: Date()
               ) {
                hasDueTime = true
                dueTime = parsed
            }
        }
        priority = task.priorityLevel
        requiresPhoto = task.photoRequired
        if let end = task.endDate,
           let parsed = RosterCalendar.dateFromKey(end) {
            hasEndDate = true
            endDate = parsed
        }
    }

    private func save() async {
        guard canSave else { return }
        errorMessage = nil

        do {
            try await repo.saveTask(
                id: task?.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: descriptionText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty,
                frequency: frequency,
                date: RosterCalendar.dateString(from: onceDate),
                dayOfWeek: weekdays.sorted(),
                assignedTo: assignToAll ? nil : Array(assignedIDs).sorted(),
                dueTime: hasDueTime ? RosterFormat.hhmm(dueTime) : nil,
                priority: priority.rawValue,
                requiresPhoto: requiresPhoto,
                endDate: frequency != "once" && hasEndDate
                    ? RosterCalendar.dateString(from: endDate)
                    : nil,
                referencePhoto: referenceImage
            )
            toasts.show(
                task == nil ? "Task created" : "Task updated",
                style: .success
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
