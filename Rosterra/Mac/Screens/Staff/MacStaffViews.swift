#if targetEnvironment(macCatalyst)
import SwiftUI
import PhotosUI

// MARK: - Mac Staff Tasks View

struct MacStaffTasksView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var filter: TaskFilter = .pending
    @State private var selectedTask: RosterTask?
    @State private var completionNote: String = ""
    @State private var isSubmitting: Bool = false

    enum TaskFilter: String, CaseIterable {
        case pending = "Pending"
        case completed = "Completed"
        case all = "All Tasks"
    }

    init() {}

    private var currentUserId: String {
        repo.currentUser?.id ?? ""
    }

    private var filteredTasks: [RosterTask] {
        let tasks = repo.tasks.filter { $0.assignedStaffId == currentUserId || $0.assignedStaffId == nil }
        switch filter {
        case .pending: return tasks.filter { !repo.isTaskCompleted($0) }
        case .completed: return tasks.filter { repo.isTaskCompleted($0) }
        case .all: return tasks
        }
    }

    var body: some View {
        MacScreen(
            title: "My Tasks",
            subtitle: "\(filteredTasks.count) tasks available",
            actions: {
                Picker("Filter", selection: $filter) {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        ) {
            ScrollView {
                LazyVStack(spacing: MacSpace.md) {
                    if filteredTasks.isEmpty {
                        MacEmptyState(
                            title: "No Tasks Found",
                            subtitle: "There are no tasks matching the selected filter.",
                            icon: "checklist"
                        )
                    } else {
                        ForEach(filteredTasks) { task in
                            taskCard(task)
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }

    private func taskCard(_ task: RosterTask) -> some View {
        MacCard {
            HStack(spacing: MacSpace.lg) {
                Button {
                    Task {
                        try? await repo.toggleTaskCompletion(taskId: task.id, note: completionNote)
                    }
                } label: {
                    Image(systemName: repo.isTaskCompleted(task) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(repo.isTaskCompleted(task) ? MacColor.success : MacColor.cardBorder)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: MacSpace.sm) {
                        Text(task.title)
                            .font(MacType.sectionHeader)
                            .foregroundStyle(repo.isTaskCompleted(task) ? MacColor.textTertiary : MacColor.textPrimary)
                            .strikethrough(repo.isTaskCompleted(task))

                        if let priority = task.priority {
                            MacStatusPill(
                                text: priority.uppercased(),
                                foreground: priority == "high" ? MacColor.error : MacColor.warning,
                                background: (priority == "high" ? MacColor.error : MacColor.warning).opacity(0.12),
                                border: (priority == "high" ? MacColor.error : MacColor.warning).opacity(0.3)
                            )
                        }
                    }

                    if let details = task.description, !details.isEmpty {
                        Text(details)
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    HStack(spacing: MacSpace.md) {
                        if let dueDate = task.dueDate {
                            Text("Due: \(dueDate)")
                                .font(MacType.caption)
                                .foregroundStyle(MacColor.textTertiary)
                        }
                        if let location = task.locationName {
                            Text("Location: \(location)")
                                .font(MacType.caption)
                                .foregroundStyle(MacColor.textTertiary)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Mac Staff Availability View

struct MacStaffAvailabilityView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var availabilityState: [String: (available: Bool, note: String)] = [:]
    @State private var isSaving: Bool = false

    private let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    init() {}

    var body: some View {
        MacScreen(
            title: "My Availability",
            subtitle: "Set your weekly recurring availability for roster planning",
            actions: {
                MacAsyncButton(variant: .prominent, size: .small) {
                    await saveAvailability()
                } label: {
                    Text("Save Availability")
                }
            }
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    MacCard {
                        VStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                HStack(spacing: MacSpace.xl) {
                                    Text(day)
                                        .font(MacType.bodyStrong)
                                        .foregroundStyle(MacColor.textPrimary)
                                        .frame(width: 140, alignment: .leading)

                                    let isAvail = availabilityState[day]?.available ?? true
                                    Button(isAvail ? "Available" : "Unavailable") {
                                        let current = availabilityState[day] ?? (available: true, note: "")
                                        availabilityState[day] = (!current.available, current.note)
                                    }
                                    .macButton(isAvail ? .prominent : .bordered, size: .small)

                                    TextField("Note (e.g. after 1pm only)", text: Binding(
                                        get: { availabilityState[day]?.note ?? "" },
                                        set: { val in
                                            let current = availabilityState[day] ?? (available: true, note: "")
                                            availabilityState[day] = (current.available, val)
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(MacType.body)
                                }
                                .padding(.vertical, MacSpace.md)
                                .overlay(
                                    Rectangle()
                                        .fill(MacColor.separator)
                                        .frame(height: 1),
                                    alignment: .bottom
                                )
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
        .onAppear {
            loadAvailability()
        }
    }

    private func loadAvailability() {
        if let staffAvail = repo.staffAvailability.first(where: { $0.staffId == (repo.currentUser?.id ?? "") }) {
            for day in days {
                let lower = day.lowercased()
                let isAvail = staffAvail.isAvailable(onDay: lower)
                let note = staffAvail.notesForDay(lower) ?? ""
                availabilityState[day] = (isAvail, note)
            }
        }
    }

    private func saveAvailability() async {
        guard let userId = repo.currentUser?.id else { return }
        do {
            try await repo.saveStaffAvailability(staffId: userId, preferences: availabilityState)
            toasts.show("Availability preferences saved!", style: .success)
        } catch {
            toasts.show(error.localizedDescription, style: .error)
        }
    }
}

// MARK: - Mac Staff History View

struct MacStaffHistoryView: View {
    @Environment(RosterRepository.self) private var repo

    init() {}

    private var currentUserId: String {
        repo.currentUser?.id ?? ""
    }

    private var myTimesheets: [Timesheet] {
        repo.timesheets.filter { $0.staffId == currentUserId }
    }

    private var columns: [MacTableColumn] {
        [
            MacTableColumn(id: "date", title: "Date", width: 130, isSortable: true),
            MacTableColumn(id: "hours", title: "Hours", width: 120),
            MacTableColumn(id: "break", title: "Unpaid Break", width: 120),
            MacTableColumn(id: "status", title: "Status", width: 140),
            MacTableColumn(id: "notes", title: "Notes", maxWidth: .infinity)
        ]
    }

    var body: some View {
        MacScreen(
            title: "Timesheet History",
            subtitle: "\(myTimesheets.count) historical records"
        ) {
            VStack(spacing: 0) {
                MacTable(
                    columns: columns,
                    items: myTimesheets
                ) { timesheet in
                    HStack(spacing: 0) {
                        Text(repo.timesheetDate(timesheet))
                            .font(MacType.mono)
                            .foregroundStyle(MacColor.textPrimary)
                            .frame(width: 130, alignment: .leading)
                            .padding(.horizontal, MacSpace.md)

                        Text(String(format: "%.1fh", timesheet.totalHours))
                            .font(MacType.monoStrong)
                            .foregroundStyle(MacColor.textPrimary)
                            .frame(width: 120, alignment: .leading)
                            .padding(.horizontal, MacSpace.md)

                        Text("\(timesheet.breakMinutes) min")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textTertiary)
                            .frame(width: 120, alignment: .leading)
                            .padding(.horizontal, MacSpace.md)

                        MacStatusPill(timesheetStatus: timesheet.status)
                            .frame(width: 140, alignment: .leading)
                            .padding(.horizontal, MacSpace.md)

                        Text(timesheet.notes ?? "—")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, MacSpace.md)
                    }
                    .padding(.vertical, MacSpace.md)
                }
            }
            .padding(MacSpace.xl)
        }
    }
}

// MARK: - Mac Staff Payslips View

struct MacStaffPayslipsView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var selectedPayslip: StaffPayslip?
    @State private var exportingPDFData: Data?
    @State private var isExporting: Bool = false

    init() {}

    private var currentUserId: String {
        repo.currentUser?.id ?? ""
    }

    private var myPayslips: [StaffPayslip] {
        repo.payslips.filter { $0.staffId == currentUserId }
    }

    var body: some View {
        MacScreen(
            title: "My Payslips",
            subtitle: "\(myPayslips.count) published pay statements"
        ) {
            HStack(spacing: 0) {
                // Left: Payslip List
                VStack(spacing: 0) {
                    if myPayslips.isEmpty {
                        MacEmptyState(
                            title: "No Payslips Available",
                            subtitle: "Your payslips will appear here once published by management.",
                            icon: "doc.text"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: MacSpace.sm) {
                                ForEach(myPayslips) { payslip in
                                    Button {
                                        selectedPayslip = payslip
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(payslip.periodRangeFormatted)
                                                    .font(MacType.bodyStrong)
                                                    .foregroundStyle(MacColor.textPrimary)

                                                Text("Net Pay: $\(String(format: "%.2f", payslip.netPay))")
                                                    .font(MacType.monoStrong)
                                                    .foregroundStyle(MacColor.accent)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12))
                                                .foregroundStyle(MacColor.textTertiary)
                                        }
                                        .padding(MacSpace.md)
                                        .background(
                                            selectedPayslip?.id == payslip.id ? MacColor.tableRowSelected : MacColor.cardBackground,
                                            in: RoundedRectangle(cornerRadius: MacRadius.medium)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: MacRadius.medium)
                                                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(MacSpace.md)
                        }
                    }
                }
                .frame(width: 320)
                .background(MacColor.cardBackgroundSecondary)
                .overlay(
                    Rectangle()
                        .fill(MacColor.separator)
                        .frame(width: 1),
                    alignment: .trailing
                )

                // Right: Selected Payslip Inspector & PDF Export
                if let payslip = selectedPayslip {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MacSpace.xl) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pay Statement")
                                        .font(MacType.pageTitle)
                                        .foregroundStyle(MacColor.textPrimary)
                                    Text("Period: \(payslip.periodRangeFormatted)")
                                        .font(MacType.body)
                                        .foregroundStyle(MacColor.textSecondary)
                                }
                                Spacer()

                                Button {
                                    if let data = PayslipPDFService.generatePDFData(for: payslip, company: repo.companyDetails) {
                                        exportingPDFData = data
                                        isExporting = true
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.down.doc.fill")
                                        Text("Save PDF...")
                                    }
                                }
                                .macButton(.prominent, size: .medium)
                            }

                            // Figures Card
                            HStack(spacing: MacSpace.lg) {
                                MacStatCard(
                                    title: "Gross Pay",
                                    value: "$\(String(format: "%.2f", payslip.grossPay))",
                                    icon: "dollarsign.circle.fill",
                                    tint: MacColor.accent
                                )
                                MacStatCard(
                                    title: "Tax Withheld",
                                    value: "$\(String(format: "%.2f", payslip.taxWithheld))",
                                    icon: "building.columns.fill",
                                    tint: MacColor.warning
                                )
                                MacStatCard(
                                    title: "Net Payment",
                                    value: "$\(String(format: "%.2f", payslip.netPay))",
                                    icon: "banknote.fill",
                                    tint: MacColor.success
                                )
                            }

                            // Breakdown details
                            MacCard(title: "Earnings Breakdown", icon: "list.bullet") {
                                VStack(spacing: MacSpace.md) {
                                    ForEach(payslip.items, id: \.id) { item in
                                        HStack {
                                            Text(item.description)
                                                .font(MacType.body)
                                                .foregroundStyle(MacColor.textPrimary)
                                            Spacer()
                                            Text("\(String(format: "%.1f", item.hours)) hrs @ $\(String(format: "%.2f", item.rate))")
                                                .font(MacType.caption)
                                                .foregroundStyle(MacColor.textTertiary)
                                            Text("$\(String(format: "%.2f", item.total))")
                                                .font(MacType.monoStrong)
                                                .foregroundStyle(MacColor.textPrimary)
                                                .frame(width: 90, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(MacSpace.xxl)
                    }
                } else {
                    MacEmptyState(
                        title: "Select a Payslip",
                        subtitle: "Click on any payslip in the left panel to inspect its breakdown and download a PDF copy.",
                        icon: "doc.text.magnifyingglass"
                    )
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: PDFDocumentFile(data: exportingPDFData ?? Data()),
            contentType: .pdf,
            defaultFilename: "Payslip-\(selectedPayslip?.periodRangeFormatted ?? "export").pdf"
        ) { result in
            switch result {
            case .success:
                toasts.show("Payslip PDF saved successfully!", style: .success)
            case .failure(let error):
                toasts.show("Failed to save: \(error.localizedDescription)", style: .error)
            }
        }
    }
}

// MARK: - PDF File Document Helper

import UniformTypeIdentifiers

struct PDFDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
