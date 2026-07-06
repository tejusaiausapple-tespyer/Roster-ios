import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct TasksView: View {
    @Environment(RosterRepository.self) private var repository
    @State private var weekOffset: Int = 0
    @State private var selectedDayKey: String = RosterCalendar.todayKey()
    @State private var selectedTask: RosterTask? = nil
    
    private var monday: Date {
        RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart())
    }
    
    private var bounds: (min: Int, max: Int) {
        BusinessRules.shiftWeekOffsetBounds()
    }
    
    private var selectedDayDate: Date {
        RosterCalendar.dateFromKey(selectedDayKey) ?? Date()
    }
    
    private var activeTasksForSelectedDay: [RosterTask] {
        let weekday = weekdayNumber(for: selectedDayDate)
        let uid = repository.currentUser?.id
        return repository.tasks
            .filter { $0.isActive(onDayKey: selectedDayKey, weekday: weekday) && $0.isAssigned(to: uid) }
            .sorted { a, b in
                let ac = isTaskCompleted(a), bc = isTaskCompleted(b)
                if ac != bc { return !ac }
                if a.priorityLevel.weight != b.priorityLevel.weight {
                    return a.priorityLevel.weight < b.priorityLevel.weight
                }
                return (a.dueTime ?? "99:99") < (b.dueTime ?? "99:99")
            }
    }
    
    private var totalTasksCount: Int {
        activeTasksForSelectedDay.count
    }
    
    private var completedTasksCount: Int {
        activeTasksForSelectedDay.filter { isTaskCompleted($0) }.count
    }
    
    private var pendingTasksCount: Int {
        totalTasksCount - completedTasksCount
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header (Stats & Week Selector Card)
                    VStack(spacing: 8) {
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                miniStat(value: "\(totalTasksCount)", label: "Tasks")
                                miniStat(value: "\(completedTasksCount)", label: "Completed",
                                         tint: completedTasksCount == totalTasksCount && totalTasksCount > 0 ? Theme.accent : Theme.textPrimary)
                                miniStat(value: "\(pendingTasksCount)", label: "Pending",
                                         tint: pendingTasksCount > 0 ? Theme.warning : Theme.textSecondary)
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
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .background(Theme.background)
                    
                    // Task List
                    if activeTasksForSelectedDay.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "checklist")
                                .font(.system(size: 48))
                                .foregroundStyle(Theme.textTertiary)
                            Text("No Tasks Scheduled")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Text("No tasks are assigned for this date.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(activeTasksForSelectedDay) { task in
                                    let isCompleted = isTaskCompleted(task)
                                    let completion = completionForTask(task)
                                    
                                    Button {
                                        selectedTask = task
                                    } label: {
                                        Card(accentColor: isCompleted ? Theme.accent : Theme.warning) {
                                            HStack(alignment: .top, spacing: 14) {
                                                VStack(alignment: .leading, spacing: 6) {
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

                                                    if let due = task.dueTime, !isCompleted {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "clock").font(.caption2)
                                                            Text("Due by \(due)")
                                                                .font(.caption.weight(.semibold))
                                                        }
                                                        .foregroundStyle(Theme.warning)
                                                    }

                                                    if completion?.isRedoRequested == true {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                                                .font(.caption)
                                                            Text("Redo requested")
                                                                .font(.caption.weight(.semibold))
                                                        }
                                                        .foregroundStyle(Theme.warning)
                                                    }

                                                    if let desc = task.description, !desc.isEmpty {
                                                        Text(desc)
                                                            .font(.subheadline)
                                                            .foregroundStyle(Theme.textSecondary)
                                                            .lineLimit(2)
                                                            .multilineTextAlignment(.leading)
                                                    }
                                                    
                                                    if isCompleted {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "checkmark.circle.fill")
                                                                .font(.caption)
                                                                .foregroundStyle(Theme.accent)
                                                            Text("Completed at \(formatTime(completion?.completedAt))")
                                                                .font(.caption)
                                                                .foregroundStyle(Theme.accent)
                                                        }
                                                        .padding(.top, 2)
                                                    }
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .font(.title3.weight(.bold))
                                                    .foregroundStyle(isCompleted ? Theme.accent : Theme.textTertiary)
                                                    .padding(.top, 2)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.screenPadding)
                            .padding(.bottom, 24)
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
            }
            .sheet(item: $selectedTask) { task in
                TaskCompletionDetailSheet(task: task, dateKey: selectedDayKey)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var markedKeys: Set<String> {
        // Mark days where a task relevant to this user was completed
        let uid = repository.currentUser?.id
        let myTaskIds = Set(repository.tasks.filter { $0.isAssigned(to: uid) }.compactMap { $0.id })
        return Set(repository.taskCompletions
            .filter { $0.completed && myTaskIds.contains($0.taskId) }
            .map { $0.date })
    }
    
    private func isTaskCompleted(_ task: RosterTask) -> Bool {
        repository.taskCompletions.contains { $0.taskId == task.id && $0.date == selectedDayKey && $0.completed }
    }
    
    private func completionForTask(_ task: RosterTask) -> TaskCompletion? {
        repository.taskCompletions.first { $0.taskId == task.id && $0.date == selectedDayKey }
    }
    
    private func weekdayNumber(for date: Date) -> Int {
        let raw = RosterCalendar.calendar.component(.weekday, from: date)
        if raw == 1 { return 7 }
        return raw - 1
    }
    
    private func miniStat(value: String, label: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TaskCompletionDetailSheet: View {
    let task: RosterTask
    let dateKey: String
    @Environment(RosterRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingCamera = false
    @State private var capturedImage: UIImage? = nil
    @State private var noteText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var fullscreenImageURL: URL? = nil
    
    private var isCompleted: Bool {
        repository.taskCompletions.contains { $0.taskId == task.id && $0.date == dateKey && $0.completed }
    }
    
    private var completion: TaskCompletion? {
        repository.taskCompletions.first { $0.taskId == task.id && $0.date == dateKey }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Title & Status
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(isCompleted ? "Completed" : "Pending")
                                    .font(.caption2.weight(.bold))
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isCompleted ? Theme.accent.opacity(0.15) : Theme.warning.opacity(0.15))
                                    .foregroundStyle(isCompleted ? Theme.accent : Theme.warning)
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            
                            Text(task.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            
                            if let desc = task.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.body)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().overlay(Theme.separator)
                        
                        // Reference photo section (instruction)
                        if let managerPhotoUrl = task.managerPhotoUrl, !managerPhotoUrl.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Reference / Instructions Photo")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                
                                Button {
                                    if let url = URL(string: managerPhotoUrl) {
                                        fullscreenImageURL = url
                                    }
                                } label: {
                                    AsyncImage(url: URL(string: managerPhotoUrl)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(maxHeight: 180)
                                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                        case .failure:
                                            HStack {
                                                Image(systemName: "photo.badge.exclamationmark")
                                                Text("Failed to load reference image")
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.textSecondary)
                                            .frame(maxWidth: .infinity, minHeight: 100)
                                            .background(Theme.card)
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                        case .empty:
                                            ProgressView()
                                                .frame(maxWidth: .infinity, minHeight: 100)
                                                .background(Theme.card)
                                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Divider().overlay(Theme.separator)
                        }
                        
                        // Staff completion detail section
                        if isCompleted, let comp = completion {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Completion Report")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Completed By")
                                            .font(.footnote)
                                            .foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        // Resolve the actual completer, not whoever is viewing.
                                        Text(repository.allUsers.first(where: { $0.id == comp.completedBy })?.fullName
                                             ?? (comp.completedBy == repository.currentUser?.id
                                                 ? repository.currentUser?.fullName : nil)
                                             ?? "Staff")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                    
                                    HStack {
                                        Text("Completed Time")
                                            .font(.footnote)
                                            .foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        Text(formatDateTime(comp.completedAt))
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                }
                                .padding()
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                
                                if let note = comp.note, !note.isEmpty {
                                    Text("Note: \(note)")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                if task.photoRequired {
                                    Text("Verification Photo")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .padding(.top, 4)

                                    // Staff photos are local-only: once the
                                    // week-end sweep clears the cache, show a
                                    // placeholder rather than re-downloading.
                                    TaskPhotoView(taskId: task.id ?? "", date: dateKey,
                                                  urlString: comp.staffPhotoUrl, localOnly: true)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // Completion action
                            VStack(alignment: .leading, spacing: 14) {
                                if let comp = completion, comp.isRedoRequested {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Redo requested by your manager", systemImage: "arrow.uturn.backward.circle.fill")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Theme.warning)
                                        if let reason = comp.redoReason, !reason.isEmpty {
                                            Text("Reason: \(reason)")
                                                .font(.footnote)
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(Theme.warning.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                }

                                if !task.photoRequired {
                                    Text("Mark as Done")
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("No photo needed for this task — just tick it off below.")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                } else {
                                    Text("Upload Verification Photo")
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                }

                                if !task.photoRequired {
                                    EmptyView()
                                } else if let capturedImage {
                                    Image(uiImage: capturedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                self.capturedImage = nil
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(.white)
                                                    .shadow(radius: 2)
                                            }
                                            .padding(8)
                                        }
                                } else {
                                    Button {
                                        showingCamera = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "camera.fill")
                                            Text("Open Camera")
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                                                .strokeBorder(Theme.brand, lineWidth: 1.5)
                                        )
                                        .foregroundStyle(Theme.brand)
                                    }
                                }
                                
                                TextField("Add a note (optional)", text: $noteText, axis: .vertical)
                                    .lineLimit(2...4)
                                    .padding(12)
                                    .background(Theme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(Theme.error)
                                        .padding(.top, 2)
                                }
                                
                                Button {
                                    submitCompletion()
                                } label: {
                                    HStack {
                                        if isSubmitting {
                                            ProgressView()
                                                .tint(.white)
                                                .padding(.trailing, 8)
                                        }
                                        Text("Complete Task")
                                    }
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background((task.photoRequired && capturedImage == nil) ? Color.gray : Theme.brandStrong)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                                }
                                .disabled((task.photoRequired && capturedImage == nil) || isSubmitting)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Task details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: $capturedImage)
            }
            .sheet(item: $fullscreenImageURL) { url in
                FullscreenImageView(url: url)
            }
        }
    }
    
    private func submitCompletion() {
        guard let taskId = task.id else { return }
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                try await repository.completeTask(
                    taskId: taskId, date: dateKey,
                    image: task.photoRequired ? capturedImage : nil,
                    note: noteText)
                isSubmitting = false
                Haptics.submitSuccess()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
                Haptics.submitError()
            }
        }
    }
    
    private func formatDateTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TaskPhotoView: View {
    let taskId: String
    let date: String
    let urlString: String?
    /// Staff mode: never hit Firebase — show the sandbox copy if it still
    /// exists, otherwise a "submitted" placeholder. Managers (default) may
    /// download once, after which the local cache serves every view.
    var localOnly: Bool = false
    @Environment(RosterRepository.self) private var repository
    @State private var image: UIImage? = nil
    @State private var isLoading = false
    
    @ViewBuilder
    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                .onAppear {
                    // Refresh from cache on load
                    if self.image == nil {
                        self.image = TaskPhotoCache.load(taskId: taskId, date: date)
                    }
                }
        } else if isLoading {
            ProgressView()
                .padding()
        } else if localOnly {
            // Staff: sandbox copy or placeholder — never a cloud download.
            submittedPlaceholder
                .onAppear {
                    if image == nil {
                        image = TaskPhotoCache.load(taskId: taskId, date: date)
                    }
                }
        } else if let urlString, !urlString.isEmpty {
            Color.clear
                .task {
                    isLoading = true
                    image = TaskPhotoCache.load(taskId: taskId, date: date)
                    if image == nil {
                        image = await repository.downloadAndCachePhoto(taskId: taskId, date: date, urlString: urlString)
                    }
                    isLoading = false
                }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Photo verified & cleared")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 8)
            .onAppear {
                // Check cache if download URL was deleted
                if self.image == nil {
                    self.image = TaskPhotoCache.load(taskId: taskId, date: date)
                }
            }
        }
    }

    private var submittedPlaceholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("Photo submitted")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 8)
    }
}

struct FullscreenImageView: View, Identifiable {
    let url: URL
    var id: URL { url }
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        ProgressView().tint(.white)
                    }
                }
            }
            .navigationTitle("Instruction Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}