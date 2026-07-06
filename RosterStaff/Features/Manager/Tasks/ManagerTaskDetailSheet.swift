import SwiftUI

/// Manager review of a single task on a given day: completion report,
/// verification photo (downloaded once, then served from app storage),
/// redo requests, cloud-photo cleanup, and task admin actions.
struct ManagerTaskDetailSheet: View {
    let task: RosterTask
    let dateKey: String
    var onEdit: () -> Void
    @Environment(RosterRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var showingRedoPrompt = false
    @State private var redoReason = ""
    @State private var showingDeleteTaskConfirm = false
    @State private var isWorking = false
    @State private var errorMessage: String? = nil
    @State private var fullscreenImageURL: URL? = nil

    private var completion: TaskCompletion? {
        repository.taskCompletions.first { $0.taskId == task.id && $0.date == dateKey }
    }

    private var isCompleted: Bool {
        completion?.completed == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        taskInfo
                        Divider().overlay(Theme.separator)
                        if isCompleted, let comp = completion {
                            completionReport(comp)
                        } else if let comp = completion, comp.isRedoRequested {
                            redoBanner(comp)
                        } else {
                            pendingBanner
                        }
                        Divider().overlay(Theme.separator)
                        adminActions
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.error)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Task review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $fullscreenImageURL) { url in
                FullscreenImageView(url: url)
            }
            .alert("Request redo", isPresented: $showingRedoPrompt) {
                TextField("Reason", text: $redoReason)
                Button("Send", role: .destructive) { requestRedo() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The task reopens for this day and the staff member sees your reason. The submitted photo is removed from the cloud.")
            }
            .confirmationDialog("Delete this task?", isPresented: $showingDeleteTaskConfirm, titleVisibility: .visible) {
                Button("Delete task", role: .destructive) { deleteTask() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the task from every day it repeats on. Completion history is kept.")
            }
        }
    }

    // MARK: - Sections

    private var taskInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusLabel)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
                if task.priorityLevel != .normal {
                    Text(task.priorityLevel.label)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.card)
                        .foregroundStyle(task.priorityLevel == .high ? Theme.error : Theme.textSecondary)
                        .clipShape(Capsule())
                }
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

            HStack(spacing: 12) {
                if let due = task.dueTime {
                    Label("Due \(due)", systemImage: "clock")
                }
                Label(task.photoRequired ? "Photo proof" : "Tick to complete",
                      systemImage: task.photoRequired ? "camera" : "checkmark.square")
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completionReport(_ comp: TaskCompletion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion Report")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 8) {
                reportRow("Completed By",
                          repository.allUsers.first(where: { $0.id == comp.completedBy })?.fullName ?? "Staff")
                reportRow("Completed Time", formatDateTime(comp.completedAt))
                if let note = comp.note, !note.isEmpty {
                    reportRow("Staff Note", note)
                }
            }
            .padding()
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))

            if task.photoRequired {
                Text("Verification Photo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                TaskPhotoView(taskId: task.id ?? "", date: dateKey, urlString: comp.staffPhotoUrl)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))

                if let url = comp.staffPhotoUrl, !url.isEmpty {
                    Button {
                        deleteCloudPhoto(comp)
                    } label: {
                        Label("Reviewed — delete photo from cloud", systemImage: "icloud.slash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.brand)
                    .disabled(isWorking)

                    Text("Frees Firebase Storage. Your local copy stays for 90 days; unreviewed photos are auto-removed 14 days after first download.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Label("Cloud photo deleted — showing local copy", systemImage: "checkmark.icloud")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Button {
                redoReason = ""
                showingRedoPrompt = true
            } label: {
                Label("Request redo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Theme.warning)
            .disabled(isWorking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func redoBanner(_ comp: TaskCompletion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Redo requested", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.warning)
            if let reason = comp.redoReason, !reason.isEmpty {
                Text("Reason: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("Waiting for the staff member to resubmit.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
    }

    private var pendingBanner: some View {
        Label("Not completed yet for this day.", systemImage: "hourglass")
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
    }

    private var adminActions: some View {
        VStack(spacing: 10) {
            Button {
                onEdit()
            } label: {
                Label("Edit task", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)

            Button {
                toggleActive()
            } label: {
                Label(task.active ? "Pause task" : "Resume task",
                      systemImage: task.active ? "pause.circle" : "play.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)

            Button(role: .destructive) {
                showingDeleteTaskConfirm = true
            } label: {
                Label("Delete task", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
        }
    }

    // MARK: - Actions

    private func requestRedo() {
        guard let comp = completion else { return }
        run {
            try await repository.requestTaskRedo(completion: comp, reason: redoReason)
        }
    }

    private func deleteCloudPhoto(_ comp: TaskCompletion) {
        run {
            try await repository.deleteTaskCloudPhoto(completion: comp)
        }
    }

    private func toggleActive() {
        guard let id = task.id else { return }
        run(dismissOnSuccess: true) {
            try await repository.setTaskActive(id: id, active: !task.active)
        }
    }

    private func deleteTask() {
        guard let id = task.id else { return }
        run(dismissOnSuccess: true) {
            try await repository.deleteTask(id: id, managerPhotoUrl: task.managerPhotoUrl)
        }
    }

    private func run(dismissOnSuccess: Bool = false, _ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await work()
                isWorking = false
                Haptics.submitSuccess()
                if dismissOnSuccess { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
                Haptics.submitError()
            }
        }
    }

    // MARK: - Helpers

    private var statusLabel: String {
        if isCompleted { return "Completed" }
        if completion?.isRedoRequested == true { return "Redo" }
        return "Pending"
    }

    private var statusColor: Color {
        if isCompleted { return Theme.accent }
        return Theme.warning
    }

    private func reportRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
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
