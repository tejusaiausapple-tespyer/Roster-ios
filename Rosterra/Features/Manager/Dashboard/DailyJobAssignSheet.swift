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
    @State private var templatePendingDelete: DailyJobTemplate? = nil
    @State private var templatePendingRename: DailyJobTemplate? = nil
    @State private var renameText = ""
    /// "Keep repeating these jobs for this staff member" — when on, every new
    /// shift created for them auto-gets this same selection assigned.
    @State private var repeatDaily = false
    /// Scoped to this sheet's List only — toggled by the "Reorder" button to
    /// reveal drag handles on the Progress section without affecting the
    /// Job library section below it (which has no `.onMove`/`.onDelete`).
    @State private var editMode: EditMode = .inactive

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

    /// `selectedIds` as an order-preserving array instead of a Set (which has
    /// no defined iteration order) — this is what actually gets carried into
    /// the repeat rule and any newly-created day's assignments, so an
    /// already-assigned job keeps the position the manager dragged it to,
    /// and a freshly-checked one lands in the same order it's shown in the
    /// library list below (rather than an arbitrary Set order).
    private var orderedSelectedIds: [String] {
        let alreadyAssigned = assignments.map(\.templateId).filter { selectedIds.contains($0) }
        let newlyChecked = repo.dailyJobTemplates
            .compactMap(\.id)
            .filter { selectedIds.contains($0) && !alreadyAssigned.contains($0) }
        return alreadyAssigned + newlyChecked
    }

    var body: some View {
        NavigationStack {
            List {
                if !assignments.isEmpty {
                    Section {
                        ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                            HStack {
                                // Position in the manager-arranged order, not a
                                // stored field — always recomputed from
                                // `assignments`' current (order-sorted) index,
                                // so it stays sequential immediately as rows
                                // are dragged, before the reorder write even
                                // round-trips through Firestore.
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Theme.textTertiary.opacity(0.12)))
                                // No checkmark once completed — the "Completed
                                // [time]" text below already says so; matches
                                // the same redundant-icon removal on the staff
                                // Daily Jobs list (NotificationsSheet.swift).
                                if !assignment.completed {
                                    Image(systemName: "circle")
                                        .foregroundStyle(Theme.textTertiary)
                                }
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
                        .onMove(perform: moveAssignment)
                    } header: {
                        HStack {
                            Text("Progress — \(assignments.filter(\.completed).count)/\(assignments.count) done")
                            Spacer()
                            if assignments.count > 1 {
                                EditButton()
                                    .font(.footnote)
                                    .textCase(nil)
                            }
                        }
                    } footer: {
                        if assignments.count > 1 {
                            Text("Tap Edit, then drag \(Image(systemName: "line.3.horizontal")) to set the order staff should work through these jobs.")
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
                        HStack(spacing: 12) {
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
                            .buttonStyle(.plain)
                            .pointerHover()

                            Button {
                                renameText = template.title
                                templatePendingRename = template
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.brand)
                                    .padding(6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Rename \(template.title)")
                            .help("Rename \(template.title)")

                            Button {
                                templatePendingDelete = template
                            } label: {
                                Image(systemName: "trash")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.error)
                                    .padding(6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(template.title)")
                            .help("Delete \(template.title)")
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

                Section {
                    Toggle("Repeat daily for \(staffName)", isOn: $repeatDaily)
                } footer: {
                    Text(repeatDaily
                         ? "Every new shift created for \(staffName) will automatically get this same selection — no need to reassign each day."
                         : "Off by default: each new shift starts with no jobs assigned until you pick them here.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            .environment(\.editMode, $editMode)
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
                repeatDaily = repo.dailyJobRepeatRules[shift.staffId]?.enabled ?? false
            }
            .alert(
                "Delete job?",
                isPresented: Binding(
                    get: { templatePendingDelete != nil },
                    set: { if !$0 { templatePendingDelete = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    templatePendingDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let template = templatePendingDelete {
                        deleteTemplate(template)
                    }
                }
            } message: {
                if let title = templatePendingDelete?.title {
                    Text("Remove “\(title)” from the job library? Existing shift assignments keep their history.")
                } else {
                    Text("Remove this job from the library? Existing shift assignments keep their history.")
                }
            }
            .alert(
                "Rename job",
                isPresented: Binding(
                    get: { templatePendingRename != nil },
                    set: { if !$0 { templatePendingRename = nil } }
                )
            ) {
                TextField("Job title", text: $renameText)
                Button("Cancel", role: .cancel) {
                    templatePendingRename = nil
                }
                Button("Save") {
                    if let template = templatePendingRename {
                        renameTemplate(template)
                    }
                }
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Already-assigned shifts keep their existing title — only new assignments use the new name.")
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

    private func renameTemplate(_ template: DailyJobTemplate) {
        let title = renameText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let id = template.id else { return }
        templatePendingRename = nil
        Task {
            do {
                try await repo.renameDailyJobTemplate(id: id, title: title)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteTemplate(_ template: DailyJobTemplate) {
        guard let id = template.id else { return }
        templatePendingDelete = nil
        selectedIds.remove(id)
        Task {
            do {
                try await repo.deleteDailyJobTemplate(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Drag reorder in the Progress section — persists immediately (not
    /// batched into Save) so the new order sticks even if the manager just
    /// dismisses the sheet afterward instead of tapping Save.
    private func moveAssignment(from source: IndexSet, to destination: Int) {
        var reordered = assignments
        reordered.move(fromOffsets: source, toOffset: destination)
        Task {
            do {
                try await repo.reorderDailyJobs(orderedAssignmentIds: reordered.map(\.id), staffId: shift.staffId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        // The backfill below can touch many shifts concurrently — same
        // "don't strand an in-flight batch if the app gets backgrounded"
        // protection as bulkApprove (ManagerTimesheetsView.swift).
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "BackfillDailyJobRepeat") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }

        Task {
            defer {
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
            }
            do {
                let orderedIds = orderedSelectedIds
                try await repo.setDailyJobs(for: shift, templateIds: orderedIds)
                try await repo.setDailyJobRepeat(staffId: shift.staffId, templateIds: orderedIds, enabled: repeatDaily)
                if repeatDaily {
                    await repo.backfillDailyJobRepeat(
                        staffId: shift.staffId, templateIds: orderedIds, excludingShiftId: shift.id
                    )
                }
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
