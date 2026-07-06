import SwiftUI

/// Assign Daily Jobs from the permanent template library to one staff
/// member's shift, and watch live completion progress. Opened from the
/// Today's Roster rows on the manager dashboard.
struct DailyJobAssignSheet: View {
    let shift: Shift
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""
    @State private var newJobTitle = ""
    @State private var showingNewJob = false
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private var staffName: String {
        repo.user(id: shift.staffId)?.fullName ?? "Staff Member"
    }

    private var assignments: [DailyJobAssignment] {
        repo.dailyJobs(forShift: shift.id)
    }

    private var filteredTemplates: [DailyJobTemplate] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return repo.dailyJobTemplates }
        return repo.dailyJobTemplates.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !assignments.isEmpty {
                    Section("Progress — \(assignments.filter(\.completed).count)/\(assignments.count) done") {
                        ForEach(assignments) { assignment in
                            HStack {
                                Image(systemName: assignment.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(assignment.completed ? Theme.accent : Theme.textTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(assignment.title)
                                        .foregroundStyle(Theme.textPrimary)
                                    if assignment.completed, let at = assignment.completedAt {
                                        Text("Completed \(RosterFormat.dateTime(at))")
                                            .font(.caption)
                                            .foregroundStyle(Theme.accent)
                                    } else {
                                        Text("Pending")
                                            .font(.caption)
                                            .foregroundStyle(Theme.warning)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Job library") {
                    if repo.dailyJobTemplates.isEmpty {
                        Text("No jobs yet — add your first reusable job below.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(filteredTemplates) { template in
                        let templateId = template.id ?? ""
                        Button {
                            if selectedIds.contains(templateId) {
                                selectedIds.remove(templateId)
                            } else {
                                selectedIds.insert(templateId)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedIds.contains(templateId) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedIds.contains(templateId) ? Theme.brand : Theme.textTertiary)
                                Text(template.title)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                        }
                    }

                    if showingNewJob {
                        HStack {
                            TextField("New job title", text: $newJobTitle)
                                .onSubmit(addTemplate)
                            Button("Add", action: addTemplate)
                                .disabled(newJobTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            showingNewJob = true
                        } label: {
                            Label("Add Job", systemImage: "plus.circle.fill")
                                .foregroundStyle(Theme.brand)
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
            .searchable(text: $searchText, prompt: "Search jobs")
            .navigationTitle("Daily Jobs — \(staffName)")
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
                    .disabled(isSaving)
                }
            }
            .onAppear {
                selectedIds = Set(assignments.map(\.templateId))
            }
        }
    }

    private func addTemplate() {
        let title = newJobTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newJobTitle = ""
        Task {
            do {
                try await repo.addDailyJobTemplate(title: title)
                showingNewJob = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await repo.setDailyJobs(for: shift, templateIds: selectedIds)
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
