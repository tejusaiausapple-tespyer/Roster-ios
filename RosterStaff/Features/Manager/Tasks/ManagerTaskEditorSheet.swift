import SwiftUI
import PhotosUI

/// Create/edit a task. Reference photos are optional instructions for staff;
/// they may come from the camera or the manager's photo library (verification
/// photos, by contrast, are camera-only on the staff side).
struct ManagerTaskEditorSheet: View {
    let task: RosterTask?          // nil = create
    let defaultDateKey: String
    @Environment(RosterRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var frequency = "once"
    @State private var onceDate = Date()
    @State private var weekdays: Set<Int> = []
    @State private var assignToAll = true
    @State private var assignedIds: Set<String> = []
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var priority: TaskPriority = .normal
    @State private var requiresPhoto = true
    @State private var hasEndDate = false
    @State private var endDate = Date()

    @State private var referenceImage: UIImage? = nil
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var showingCamera = false

    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var staffUsers: [AppUser] {
        repository.allUsers.filter { $0.role == .staff }.sorted { $0.fullName < $1.fullName }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (frequency != "weekly" || !weekdays.isEmpty)
            && (assignToAll || !assignedIds.isEmpty)
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    Toggle("Photo proof required", isOn: $requiresPhoto)
                }

                Section("Schedule") {
                    Picker("Repeats", selection: $frequency) {
                        Text("One-off").tag("once")
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                    }
                    .pickerStyle(.segmented)

                    if frequency == "once" {
                        DatePicker("Date", selection: $onceDate, displayedComponents: .date)
                    }
                    if frequency == "weekly" {
                        weekdayPicker
                    }
                    Toggle("Due time", isOn: $hasDueTime)
                    if hasDueTime {
                        DatePicker("Due by", selection: $dueTime, displayedComponents: .hourAndMinute)
                    }
                    if frequency != "once" {
                        Toggle("End date", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("Ends", selection: $endDate, displayedComponents: .date)
                        }
                    }
                }

                Section("Assign to") {
                    Toggle("All staff", isOn: $assignToAll)
                    if !assignToAll {
                        ForEach(staffUsers) { user in
                            Button {
                                if assignedIds.contains(user.id) {
                                    assignedIds.remove(user.id)
                                } else {
                                    assignedIds.insert(user.id)
                                }
                            } label: {
                                HStack {
                                    Text(user.fullName)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if assignedIds.contains(user.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.brand)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Reference photo (optional)") {
                    if let referenceImage {
                        Image(uiImage: referenceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
                        Button("Remove photo", role: .destructive) {
                            self.referenceImage = nil
                            self.photoPickerItem = nil
                        }
                    } else {
                        if task?.managerPhotoUrl?.isEmpty == false {
                            Label("Existing reference photo kept", systemImage: "photo")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Label("Choose from library", systemImage: "photo.on.rectangle")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: $referenceImage)
            }
            .onChange(of: photoPickerItem) {
                guard let photoPickerItem else { return }
                Task {
                    if let data = try? await photoPickerItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        referenceImage = image
                    }
                }
            }
            .onAppear(perform: populate)
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let selected = weekdays.contains(day)
                Button {
                    if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(Self.weekdayNames[day - 1])
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.brand : Theme.background)
                        .foregroundStyle(selected ? .white : Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func populate() {
        guard let task else {
            onceDate = RosterCalendar.dateFromKey(defaultDateKey) ?? Date()
            return
        }
        title = task.title
        descriptionText = task.description ?? ""
        frequency = task.frequency
        if let d = task.date, let parsed = RosterCalendar.dateFromKey(d) { onceDate = parsed }
        weekdays = Set(task.dayOfWeek ?? [])
        if let ids = task.assignedTo, !ids.isEmpty {
            assignToAll = false
            assignedIds = Set(ids)
        }
        if let due = task.dueTime {
            hasDueTime = true
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            if let parsed = formatter.date(from: due) { dueTime = parsed }
        }
        priority = task.priorityLevel
        requiresPhoto = task.photoRequired
        if let end = task.endDate, let parsed = RosterCalendar.dateFromKey(end) {
            hasEndDate = true
            endDate = parsed
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        Task {
            do {
                try await repository.saveTask(
                    id: task?.id,
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil : descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    frequency: frequency,
                    date: RosterCalendar.todayKey(onceDate),
                    dayOfWeek: weekdays.sorted(),
                    assignedTo: assignToAll ? nil : Array(assignedIds),
                    dueTime: hasDueTime ? timeFormatter.string(from: dueTime) : nil,
                    priority: priority.rawValue,
                    requiresPhoto: requiresPhoto,
                    endDate: (frequency != "once" && hasEndDate) ? RosterCalendar.todayKey(endDate) : nil,
                    referencePhoto: referenceImage
                )
                Haptics.submitSuccess()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
                Haptics.submitError()
            }
        }
    }
}
