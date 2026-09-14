#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Mac Manager Wage View

struct MacManagerWageView: View {
    @Environment(RosterRepository.self) private var repo

    init() {}

    var body: some View {
        MacScreen(
            title: "Wage Awards & Rates",
            subtitle: "Modern Award configurations and penalty rates"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    MacCard(title: "Penalty Rates Configuration", icon: "percent") {
                        VStack(spacing: MacSpace.md) {
                            HStack {
                                Text("Saturday Penalty Rate").font(MacType.body)
                                Spacer()
                                Text("125% (1.25x)").font(MacType.monoStrong)
                            }
                            HStack {
                                Text("Sunday Penalty Rate").font(MacType.body)
                                Spacer()
                                Text("150% (1.50x)").font(MacType.monoStrong)
                            }
                            HStack {
                                Text("Public Holiday Rate").font(MacType.body)
                                Spacer()
                                Text("225% (2.25x)").font(MacType.monoStrong)
                            }
                            HStack {
                                Text("Daily Overtime (>10h)").font(MacType.body)
                                Spacer()
                                Text("150% first 2h, then 200%").font(MacType.monoStrong)
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }
}

// MARK: - Mac Manager Jobs View

private enum MacJobsSection: String, CaseIterable, Identifiable {
    case staffJobs = "Staff Jobs"
    case allJobs = "All Jobs"

    var id: String { rawValue }
}

struct MacManagerJobsView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var section: MacJobsSection = .staffJobs
    @State private var selectedShiftID: String?
    @State private var editingShift: Shift?
    @State private var jobSearchText = ""
    @State private var editingTemplate: DailyJobTemplate?
    @State private var templatePendingDelete: DailyJobTemplate?
    @State private var assignmentPendingDelete: DailyJobAssignment?
    @State private var jobTitle = ""
    @State private var showingJobEditor = false

    init() {}

    private var todaysShifts: [Shift] {
        repo.todaysShifts()
    }

    private var selectedShift: Shift? {
        guard let selectedShiftID else { return todaysShifts.first }
        return todaysShifts.first { $0.id == selectedShiftID }
    }

    private var todaysJobs: [DailyJobAssignment] {
        let shiftIDs = Set(todaysShifts.map(\.id))
        return repo.dailyJobAssignments.filter { shiftIDs.contains($0.shiftId) }
    }

    private var completedCount: Int {
        todaysJobs.filter(\.completed).count
    }

    private var staffWithJobsCount: Int {
        Set(todaysJobs.map(\.staffId)).count
    }

    private var filteredTemplates: [DailyJobTemplate] {
        let query = jobSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return repo.dailyJobTemplates }
        return repo.dailyJobTemplates.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        MacScreen(
            title: "Jobs",
            subtitle: section == .staffJobs
                ? "Daily work assigned to today’s roster"
                : "Add and manage the complete reusable job list"
        ) {
            VStack(spacing: 0) {
                jobsActionBar

                Group {
                    if section == .staffJobs {
                        staffJobsWorkspace
                    } else {
                        allJobsWorkspace
                    }
                }
            }
        }
        .onAppear { maintainSelection() }
        .onChange(of: todaysShifts.map(\.id)) { _, _ in maintainSelection() }
        .sheet(item: $editingShift) { shift in
            DailyJobAssignSheet(shift: shift, showsOnlyUnassignedTemplates: true)
                .frame(width: 680)
                .frame(minHeight: 720)
                .macObserved(repo: repo, toasts: toasts)
        }
        .alert(
            editingTemplate == nil ? "Add job" : "Edit job",
            isPresented: $showingJobEditor
        ) {
            TextField("Job title", text: $jobTitle)
            Button("Cancel", role: .cancel) {
                editingTemplate = nil
                jobTitle = ""
            }
            Button(editingTemplate == nil ? "Add" : "Save") {
                saveTemplate()
            }
            .disabled(jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(editingTemplate == nil
                 ? "Add a reusable job that can be assigned to any staff shift."
                 : "Existing shift history keeps its original title. Future assignments use the updated title.")
        }
        .confirmationDialog(
            "Delete job?",
            isPresented: Binding(
                get: { templatePendingDelete != nil },
                set: { if !$0 { templatePendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: templatePendingDelete
        ) { template in
            Button("Delete “\(template.title)”", role: .destructive) {
                deleteTemplate(template)
            }
            Button("Cancel", role: .cancel) {}
        } message: { template in
            Text("This removes “\(template.title)” from All Jobs. Existing shift assignments keep their history.")
        }
        .alert(
            "Remove assigned job?",
            isPresented: Binding(
                get: { assignmentPendingDelete != nil },
                set: { if !$0 { assignmentPendingDelete = nil } }
            ),
            presenting: assignmentPendingDelete
        ) { assignment in
            Button("Remove", role: .destructive) {
                removeAssignment(assignment)
            }
            Button("Cancel", role: .cancel) {}
        } message: { assignment in
            Text("Remove “\(assignment.title)” from this staff member’s current shift? Daily repeat settings and the All Jobs list will not change.")
        }
    }

    private var jobsActionBar: some View {
        HStack(spacing: MacSpace.md) {
            Picker("Jobs view", selection: $section) {
                ForEach(MacJobsSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            if section == .staffJobs, let shift = selectedShift {
                Button {
                    editingShift = shift
                } label: {
                    Label("Add Jobs", systemImage: "plus")
                }
                .macButton(.prominent)
            } else if section == .allJobs {
                Button {
                    presentNewJob()
                } label: {
                    Label("Add new job", systemImage: "plus")
                }
                .macButton(.prominent)
            }

            MacAsyncButton(variant: .bordered) {
                await repo.refreshFromServer()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.top, MacSpace.md)
    }

    private var staffJobsWorkspace: some View {
        VStack(spacing: MacSpace.lg) {
            summaryStrip

            HStack(spacing: MacSpace.lg) {
                shiftsPanel
                    .frame(minWidth: 360, idealWidth: 410, maxWidth: 460)

                inspectorPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.top, MacSpace.md)
        .padding(.bottom, MacSpace.xl)
    }

    private var allJobsWorkspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: MacSpace.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Complete job list")
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("\(repo.dailyJobTemplates.count) reusable \(repo.dailyJobTemplates.count == 1 ? "job" : "jobs")")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }

                Spacer()

                HStack(spacing: MacSpace.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(MacColor.textTertiary)
                    TextField("Search jobs", text: $jobSearchText)
                        .textFieldStyle(.plain)
                        .font(MacType.body)
                    if !jobSearchText.isEmpty {
                        Button {
                            jobSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(MacColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, MacSpace.md)
                .frame(width: 300, height: 34)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: MacRadius.medium)
                        .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                }
            }
            .padding(MacSpace.lg)

            Rectangle().fill(MacColor.separator).frame(height: 1)

            if repo.dailyJobTemplates.isEmpty {
                MacEmptyState(
                    title: "No jobs yet",
                    subtitle: "Add your first reusable job, then assign it from Staff Jobs.",
                    icon: "checklist",
                    actionTitle: "Add job",
                    action: presentNewJob
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTemplates.isEmpty {
                MacEmptyState(
                    title: "No matching jobs",
                    subtitle: "Try another search term.",
                    icon: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: MacSpace.sm) {
                        ForEach(Array(filteredTemplates.enumerated()), id: \.element.id) { index, template in
                            templateRow(template, number: index + 1)
                        }
                    }
                    .padding(MacSpace.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.top, MacSpace.md)
        .padding(.bottom, MacSpace.xl)
    }

    private func templateRow(_ template: DailyJobTemplate, number: Int) -> some View {
        HStack(spacing: MacSpace.md) {
            Text("\(number)")
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 30, height: 30)
                .background(MacColor.cardBackground, in: Circle())
                .overlay {
                    Circle().strokeBorder(MacColor.cardBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
                Text("Reusable job · available for every staff shift")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }

            Spacer()

            Button {
                presentEditJob(template)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .macButton(.bordered, size: .small)

            Button {
                templatePendingDelete = template
            } label: {
                Image(systemName: "trash")
            }
            .macButton(.destructive, size: .small)
            .help("Delete \(template.title)")
        }
        .padding(MacSpace.lg)
        .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.medium)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium))
        .onTapGesture(count: 2) {
            presentEditJob(template)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                presentEditJob(template)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                templatePendingDelete = template
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryMetric(
                title: "Today’s shifts",
                value: "\(todaysShifts.count)",
                detail: "Rostered",
                icon: "calendar",
                tint: MacColor.info
            )
            summaryDivider
            summaryMetric(
                title: "Assigned jobs",
                value: "\(todaysJobs.count)",
                detail: "Across \(staffWithJobsCount) staff",
                icon: "checklist",
                tint: MacColor.accent
            )
            summaryDivider
            summaryMetric(
                title: "Completed",
                value: "\(completedCount)",
                detail: completionDetail,
                icon: "checkmark.circle.fill",
                tint: MacColor.success
            )
            summaryDivider
            summaryMetric(
                title: "Remaining",
                value: "\(max(0, todaysJobs.count - completedCount))",
                detail: "Still to do",
                icon: "clock.fill",
                tint: todaysJobs.count == completedCount ? MacColor.success : MacColor.warning
            )
        }
        .padding(.vertical, MacSpace.md)
        .background(MacColor.cardBackground, in: RoundedRectangle(cornerRadius: MacRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var completionDetail: String {
        guard !todaysJobs.isEmpty else { return "No jobs assigned" }
        let percent = Int((Double(completedCount) / Double(todaysJobs.count) * 100).rounded())
        return "\(percent)% complete"
    }

    private func summaryMetric(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: MacRadius.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(MacType.badge)
                    .tracking(0.4)
                    .foregroundStyle(MacColor.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(MacType.monoLarge)
                        .foregroundStyle(MacColor.textPrimary)
                    Text(detail)
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(MacColor.separator)
            .frame(width: 1, height: 48)
    }

    private var shiftsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today’s roster")
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Text("Select a shift to review its jobs")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }
                Spacer()
                Text("\(todaysShifts.count)")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(MacColor.accent.opacity(0.12), in: Capsule())
            }
            .padding(MacSpace.lg)

            Rectangle().fill(MacColor.separator).frame(height: 1)

            if todaysShifts.isEmpty {
                MacEmptyState(
                    title: "No shifts today",
                    subtitle: "Add a shift to the roster before assigning daily jobs.",
                    icon: "calendar.badge.exclamationmark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: MacSpace.sm) {
                        ForEach(todaysShifts) { shift in
                            shiftRow(shift)
                        }
                    }
                    .padding(MacSpace.sm)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func shiftRow(_ shift: Shift) -> some View {
        let staff = repo.user(id: shift.staffId)
        let jobs = repo.dailyJobs(forShift: shift.id)
        let done = jobs.filter(\.completed).count
        let selected = selectedShift?.id == shift.id

        return Button {
            selectedShiftID = shift.id
        } label: {
            HStack(spacing: MacSpace.md) {
                MacAvatar(name: staff?.fullName ?? "?", size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(staff?.fullName ?? "Staff member")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(1)
                    Text("\(shift.rosteredStart) – \(shift.rosteredEnd)")
                        .font(MacType.mono)
                        .foregroundStyle(MacColor.textSecondary)
                }
                Spacer(minLength: MacSpace.sm)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(jobs.isEmpty ? "No jobs" : "\(done)/\(jobs.count) done")
                        .font(MacType.captionStrong)
                        .foregroundStyle(progressTint(done: done, total: jobs.count))
                    if !jobs.isEmpty {
                        ProgressView(value: Double(done), total: Double(jobs.count))
                            .tint(progressTint(done: done, total: jobs.count))
                            .frame(width: 72)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacColor.textTertiary)
            }
            .padding(.horizontal, MacSpace.md)
            .padding(.vertical, 10)
            .background(
                selected ? MacColor.tableRowSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { editingShift = shift }
        )
        .contextMenu {
            Button("Add Jobs", systemImage: "plus") {
                editingShift = shift
            }
        }
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        if let shift = selectedShift {
            shiftInspector(shift)
        } else {
            VStack {
                MacEmptyState(
                    title: "Select a shift",
                    subtitle: "Choose a rostered staff member to review their daily jobs.",
                    icon: "checklist"
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.large)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }
        }
    }

    private func shiftInspector(_ shift: Shift) -> some View {
        let staff = repo.user(id: shift.staffId)
        let jobs = repo.dailyJobs(forShift: shift.id)
        let done = jobs.filter(\.completed).count

        return VStack(spacing: 0) {
            HStack(spacing: MacSpace.md) {
                MacAvatar(name: staff?.fullName ?? "?", size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(staff?.fullName ?? "Staff member")
                        .font(MacType.pageTitle)
                        .foregroundStyle(MacColor.textPrimary)
                    HStack(spacing: MacSpace.sm) {
                        Label("\(shift.rosteredStart) – \(shift.rosteredEnd)", systemImage: "clock")
                        if let department = shift.department, !department.isEmpty {
                            Text("·")
                            Text(department)
                        }
                    }
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
                }
                Spacer()
                Button {
                    editingShift = shift
                } label: {
                    Label("Add Jobs", systemImage: "plus")
                }
                .macButton(.prominent, size: .small)
            }
            .padding(MacSpace.xl)

            Rectangle().fill(MacColor.separator).frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY CHECKLIST")
                        .font(MacType.badge)
                        .tracking(0.5)
                        .foregroundStyle(MacColor.textTertiary)
                    Text(jobs.isEmpty ? "Nothing assigned" : "\(done) of \(jobs.count) completed")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                }
                Spacer()
                if !jobs.isEmpty {
                    Text("\(Int((Double(done) / Double(jobs.count) * 100).rounded()))%")
                        .font(MacType.monoLarge)
                        .foregroundStyle(progressTint(done: done, total: jobs.count))
                }
            }
            .padding(MacSpace.xl)

            if jobs.isEmpty {
                MacEmptyState(
                    title: "No jobs assigned",
                    subtitle: "Choose work from All Jobs for this staff member’s shift.",
                    icon: "checklist",
                    actionTitle: "Add jobs",
                    action: { editingShift = shift }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: MacSpace.sm) {
                        ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                            jobRow(job, number: index + 1)
                        }
                    }
                    .padding(.horizontal, MacSpace.xl)
                    .padding(.bottom, MacSpace.xl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func jobRow(_ job: DailyJobAssignment, number: Int) -> some View {
        HStack(spacing: MacSpace.md) {
            ZStack {
                Circle()
                    .fill(job.completed ? MacColor.success : MacColor.cardBackgroundSecondary)
                    .overlay {
                        Circle().strokeBorder(job.completed ? MacColor.success : MacColor.cardBorder, lineWidth: 1)
                    }
                if job.completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(number)")
                        .font(MacType.badge)
                        .foregroundStyle(MacColor.textTertiary)
                }
            }
            .frame(width: 30, height: 30)

            Text(job.title)
                .font(MacType.bodyStrong)
                .foregroundStyle(job.completed ? MacColor.textSecondary : MacColor.textPrimary)
                .strikethrough(job.completed, color: MacColor.textTertiary)

            Spacer()

            Text(job.completed ? "Done" : "Pending")
                .font(MacType.badge)
                .foregroundStyle(job.completed ? MacColor.success : MacColor.warning)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    (job.completed ? MacColor.success : MacColor.warning).opacity(0.1),
                    in: Capsule()
                )

            Button {
                assignmentPendingDelete = job
            } label: {
                Image(systemName: "trash")
            }
            .macButton(.destructive, size: .small)
            .help("Remove \(job.title) from this shift")
            .accessibilityLabel("Remove \(job.title) from this shift")
        }
        .padding(MacSpace.lg)
        .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.medium)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func progressTint(done: Int, total: Int) -> Color {
        guard total > 0 else { return MacColor.textTertiary }
        return done == total ? MacColor.success : MacColor.warning
    }

    private func maintainSelection() {
        let ids = todaysShifts.map(\.id)
        guard !ids.isEmpty else {
            selectedShiftID = nil
            return
        }
        if selectedShiftID == nil || !ids.contains(selectedShiftID!) {
            selectedShiftID = ids.first
        }
    }

    private func presentNewJob() {
        editingTemplate = nil
        jobTitle = ""
        showingJobEditor = true
    }

    private func presentEditJob(_ template: DailyJobTemplate) {
        editingTemplate = template
        jobTitle = template.title
        showingJobEditor = true
    }

    private func saveTemplate() {
        let title = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let template = editingTemplate
        editingTemplate = nil
        jobTitle = ""

        Task {
            do {
                if let template, let id = template.id {
                    try await repo.renameDailyJobTemplate(id: id, title: title)
                    toasts.show("Job updated.", style: .success)
                } else {
                    try await repo.addDailyJobTemplate(title: title)
                    toasts.show("Job added.", style: .success)
                }
            } catch {
                toasts.show("Couldn’t save the job. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func deleteTemplate(_ template: DailyJobTemplate) {
        templatePendingDelete = nil
        guard let id = template.id else { return }

        Task {
            do {
                try await repo.deleteDailyJobTemplate(id: id)
                toasts.show("Job deleted.", style: .success)
            } catch {
                toasts.show("Couldn’t delete the job. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func removeAssignment(_ assignment: DailyJobAssignment) {
        assignmentPendingDelete = nil
        guard let shift = repo.shift(id: assignment.shiftId) else {
            toasts.show("Couldn’t find this shift.", style: .error)
            return
        }

        let remainingTemplateIDs = repo.dailyJobs(forShift: shift.id)
            .filter { $0.id != assignment.id }
            .map(\.templateId)

        Task {
            do {
                try await repo.setDailyJobs(for: shift, templateIds: remainingTemplateIDs)
                toasts.show("Job removed from this shift.", style: .success)
            } catch {
                toasts.show("Couldn’t remove the job. \(error.localizedDescription)", style: .error)
            }
        }
    }
}

// MARK: - Mac Manager Locations View

struct MacManagerLocationsView: View {
    @Environment(RosterRepository.self) private var repo

    init() {}

    var body: some View {
        MacScreen(
            title: "Work Locations & Geofences",
            subtitle: "Configured workplace locations and clock-in boundaries"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    ForEach(repo.locations) { loc in
                        MacCard(title: loc.name, icon: "mappin.and.ellipse") {
                            VStack(alignment: .leading, spacing: MacSpace.sm) {
                                Text(loc.address).font(MacType.body).foregroundStyle(MacColor.textSecondary)
                                Text("Geofence Radius: \(Int(loc.radiusMeters))m").font(MacType.caption).foregroundStyle(MacColor.textTertiary)
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }
}

// MARK: - Mac Manager Company View

struct MacManagerCompanyView: View {
    @Environment(RosterRepository.self) private var repo

    init() {}

    var body: some View {
        MacScreen(
            title: "Company Identity & Details",
            subtitle: "Legal entity information used on official payslips and tax invoices"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    MacCard(title: "Entity Information", icon: "building.2.fill") {
                        VStack(alignment: .leading, spacing: MacSpace.md) {
                            HStack {
                                Text("Business Name").font(MacType.bodyStrong)
                                Spacer()
                                Text(repo.companyDetails?.name ?? "Rosterra").font(MacType.body)
                            }
                            HStack {
                                Text("Australian Business Number (ABN)").font(MacType.bodyStrong)
                                Spacer()
                                Text(repo.companyDetails?.abn ?? "Not configured").font(MacType.mono)
                            }
                            HStack {
                                Text("Business Address").font(MacType.bodyStrong)
                                Spacer()
                                Text(repo.companyDetails?.address ?? "Adelaide, SA").font(MacType.body)
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }
}
#endif
