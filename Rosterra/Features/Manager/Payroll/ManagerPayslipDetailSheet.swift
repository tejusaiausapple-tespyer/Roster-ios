import SwiftUI
import PDFKit

/// Full payroll editor for one payslip: employee info, hours, earnings,
/// deductions, super, live totals, live PDF preview, and the manual
/// Draft → Review → Approve → Submit workflow.
///
/// Reads the payslip live from the repository (by id) so concurrent updates
/// land, but edits accumulate in a local copy until Save.
struct ManagerPayslipDetailSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    let payslipId: String

    @State private var slip: Payslip?
    @State private var seeded = false
    @State private var isDirty = false
    @State private var isWorking = false
    @State private var toast: ToastMessage?
    @State private var confirmAction: WorkflowAction?
    @State private var showPDFPreview = false

    enum WorkflowAction: Identifiable {
        case approve, submit, correct
        var id: String { String(describing: self) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let slip {
                    editor(for: slip)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(slip?.staffName ?? "Payslip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else if isDirty, slip?.status.isEditable == true {
                        Button("Save") { save() }
                    }
                }
            }
            .toast($toast)
            .onAppear { seedIfNeeded() }
            .onChange(of: repo.payslips) { seedFromRepo(force: !isDirty) }
            .confirmationDialog(confirmTitle, isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ), titleVisibility: .visible) {
                confirmButtons
            } message: {
                Text(confirmMessage)
            }
            .sheet(isPresented: $showPDFPreview) {
                if let slip {
                    PayslipPDFSheet(slip: slip, isManager: true)
                }
            }
        }
    }

    // MARK: Editor

    @ViewBuilder
    private func editor(for slip: Payslip) -> some View {
        let editable = slip.status.isEditable
        let totals = slip.totals
        Form {
            statusSection(slip)
            employeeSection(slip)
            hoursSection(editable: editable)
            earningsSection(slip, editable: editable)
            deductionsSection(editable: editable)
            superSection(slip, totals: totals)
            summarySection(totals)
            pdfSection(slip)
            workflowSection(slip)
            auditSection(slip)
        }
        .scrollContentBackground(.hidden)
        .disabled(isWorking)
    }

    private func statusSection(_ slip: Payslip) -> some View {
        Section {
            HStack {
                PayslipStatusPill(status: slip.status)
                Spacer()
                Text(RosterFormat.weekRange(monday: RosterCalendar.dateFromKey(slip.periodStart) ?? Date()))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            if slip.baseHourlyRate <= 0, slip.status.isEditable {
                Label {
                    Text("No hourly rate resolved from the wage assignment. Set an award classification, a rate override, or an ordinary-hours line with a dollar rate in Staff → Wage Assignment, then tap “Regenerate from timesheets” — or type the base rate below.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                }
            }
            if !slip.status.isEditable && slip.status != .archived {
                Text(slip.status == .submitted
                     ? "Submitted payslips are locked and visible to \(slip.staffName). Issue a corrected copy to make changes."
                     : "Approved payslips are locked — submit to publish, or issue a corrected copy.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func employeeSection(_ slip: Payslip) -> some View {
        let employeeId = repo.displayEmployeeId(for: slip)
        return Section("Employee") {
            LabeledContent("Name", value: slip.staffName)
            LabeledContent("Employee ID", value: employeeId.isEmpty ? "—" : employeeId)
            if !slip.position.isEmpty { LabeledContent("Position", value: slip.position) }
            LabeledContent("Employment type",
                           value: EmploymentType(rawValue: slip.employmentType)?.label ?? "—")
            if !slip.awardName.isEmpty {
                LabeledContent("Award", value: slip.awardCode.isEmpty ? slip.awardName : "\(slip.awardName) (\(slip.awardCode))")
            }
            if !slip.classification.isEmpty { LabeledContent("Classification", value: slip.classification) }
            LabeledContent("Pay period",
                           value: "\(RosterFormat.dateShort(slip.periodStart)) – \(RosterFormat.dateShort(slip.periodEnd))")
        }
    }

    private func hoursSection(editable: Bool) -> some View {
        Section {
            hoursRow("Ordinary hours", hours: binding(\.ordinaryHours), rate: binding(\.baseHourlyRate), editable: editable)
            hoursRow("Weekend hours", hours: binding(\.weekendHours), rate: binding(\.weekendRate), editable: editable)
            hoursRow("Public holiday", hours: binding(\.publicHolidayHours), rate: binding(\.publicHolidayRate), editable: editable)
            hoursRow("Overtime", hours: binding(\.overtimeHours), rate: binding(\.overtimeRate), editable: editable)
        } header: {
            Text("Hours")
        } footer: {
            Text("Hours come from approved timesheets (weekends split automatically). Penalty rates default from the base rate — adjust them to the award before approving.")
        }
    }

    private func hoursRow(_ label: String, hours: Binding<Double>, rate: Binding<Double>, editable: Bool) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            TextField("0", value: hours, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .disabled(!editable)
            Text("h ×").font(.caption).foregroundStyle(Theme.textTertiary)
            TextField("0.00", value: rate, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .disabled(!editable)
        }
        .onChange(of: hours.wrappedValue) { markDirty() }
        .onChange(of: rate.wrappedValue) { markDirty() }
    }

    @ViewBuilder
    private func earningsSection(_ slip: Payslip, editable: Bool) -> some View {
        Section {
            if slip.extraEarnings.isEmpty {
                Text("No allowances or additional earnings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(slip.extraEarnings.enumerated()), id: \.element.id) { index, earning in
                VStack(alignment: .leading, spacing: 6) {
                    Text(earning.name).font(.subheadline.weight(.medium))
                    HStack {
                        if earning.rate > 0 {
                            TextField("Qty", value: extraBinding(index, \.quantity), format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .frame(width: 60)
                                .disabled(!editable)
                            Text("× \(RosterFormat.money(earning.rate))")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(RosterFormat.money(earning.quantity * earning.rate))
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Text("Amount").font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("0.00", value: extraBinding(index, \.amount), format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .disabled(!editable)
                        }
                    }
                }
            }
            .onDelete(perform: editable ? { offsets in
                self.slip?.extraEarnings.remove(atOffsets: offsets)
                markDirty()
            } : nil)
            if editable {
                Button {
                    self.slip?.extraEarnings.append(PayslipEarning(name: "Allowance"))
                    markDirty()
                } label: {
                    Label("Add earnings row", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Allowances & other earnings")
        }
    }

    private func deductionsSection(editable: Bool) -> some View {
        Section {
            moneyRow("PAYG withholding", value: binding(\.payg), editable: editable)
            moneyRow("Other deductions", value: binding(\.otherDeductions), editable: editable)
            moneyRow("Salary sacrifice", value: binding(\.salarySacrifice), editable: editable)
            TextField("Deduction notes", text: binding(\.deductionNotes), axis: .vertical)
                .font(.subheadline)
                .disabled(!editable)
                .onChange(of: slip?.deductionNotes ?? "") { markDirty() }
            TextField("Payslip notes", text: binding(\.notes), axis: .vertical)
                .font(.subheadline)
                .disabled(!editable)
                .onChange(of: slip?.notes ?? "") { markDirty() }
        } header: {
            Text("Deductions & notes")
        } footer: {
            Text("PAYG is entered manually from the ATO tax tables for the employee's declaration.")
        }
    }

    private func moneyRow(_ label: String, value: Binding<Double>, editable: Bool) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text("$").foregroundStyle(Theme.textTertiary)
            TextField("0.00", value: value, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .disabled(!editable)
                .onChange(of: value.wrappedValue) { markDirty() }
        }
    }

    private func superSection(_ slip: Payslip, totals: PayrollCalculator.Totals) -> some View {
        Section {
            HStack {
                Text("Super guarantee").font(.subheadline)
                Spacer()
                TextField("12", value: binding(\.superRate), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .disabled(!slip.status.isEditable)
                    .onChange(of: slip.superRate) { markDirty() }
                Text("%").foregroundStyle(Theme.textTertiary)
            }
            LabeledContent("Employer contribution", value: RosterFormat.money(totals.superAmount))
        } header: {
            Text("Superannuation")
        } footer: {
            Text(slip.superRate > 0
                 ? "Calculated on ordinary time earnings — overtime and super-exempt rows are excluded."
                 : "Super is OFF for this payslip (rate 0%) — the PDF omits the superannuation block. Set a percentage to re-enable, or manage the default in Staff → Wage Assignment.")
        }
    }

    private func summarySection(_ totals: PayrollCalculator.Totals) -> some View {
        Section("Summary") {
            LabeledContent("Total hours", value: RosterFormat.decimalHours(totals.totalHours))
            LabeledContent("Gross pay", value: RosterFormat.money(totals.gross))
            LabeledContent("Tax (PAYG)", value: "− \(RosterFormat.money(totals.tax))")
            if totals.deductions > 0 {
                LabeledContent("Deductions", value: "− \(RosterFormat.money(totals.deductions))")
            }
            if totals.superAmount > 0 {
                LabeledContent("Super (employer)", value: RosterFormat.money(totals.superAmount))
            }
            HStack {
                Text("NET PAY").font(.subheadline.weight(.bold))
                Spacer()
                Text(RosterFormat.money(totals.net))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.brand)
                    .contentTransition(.numericText())
            }
        }
    }

    private func pdfSection(_ slip: Payslip) -> some View {
        Section {
            Button {
                showPDFPreview = true
            } label: {
                Label("Preview payslip PDF", systemImage: "doc.richtext")
            }
        } footer: {
            Text(isDirty ? "Preview includes your unsaved edits." : "The preview is rendered by the same engine as the exported PDF.")
        }
    }

    @ViewBuilder
    private func workflowSection(_ slip: Payslip) -> some View {
        Section("Workflow") {
            switch slip.status {
            case .draft:
                Button { transition(to: .underReview) } label: {
                    Label("Start review", systemImage: "eye")
                }
                Button { transition(to: .draft, regenerate: true) } label: {
                    Label("Regenerate from timesheets", systemImage: "arrow.clockwise")
                }
            case .underReview:
                Button { confirmAction = .approve } label: {
                    Label("Approve", systemImage: "checkmark.seal")
                }
                Button { transition(to: .draft) } label: {
                    Label("Back to draft", systemImage: "arrow.uturn.backward")
                }
            case .approved:
                Button { confirmAction = .submit } label: {
                    Label("Submit — publish to \(slip.staffName)", systemImage: "paperplane")
                }
                Button { transition(to: .underReview) } label: {
                    Label("Reopen review", systemImage: "arrow.uturn.backward")
                }
            case .submitted:
                Button { confirmAction = .correct } label: {
                    Label("Issue corrected copy", systemImage: "doc.on.doc")
                }
                Button { transition(to: .archived) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            case .archived:
                Text("Archived — kept for records.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func auditSection(_ slip: Payslip) -> some View {
        if !slip.audit.isEmpty {
            Section("Audit trail") {
                ForEach(slip.audit.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(RosterFormat.dateTime(entry.at))
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(entry.detail.isEmpty ? entry.userName : "\(entry.userName) — \(entry.detail)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Confirmation dialog

    private var confirmTitle: String {
        switch confirmAction {
        case .approve: return "Approve payslip?"
        case .submit: return "Submit payslip?"
        case .correct: return "Issue corrected copy?"
        case nil: return ""
        }
    }

    private var confirmMessage: String {
        switch confirmAction {
        case .approve: return "Approving locks the amounts. You can reopen the review before submitting."
        case .submit: return "Submitting publishes this payslip to \(slip?.staffName ?? "the staff member") and locks the pay period. This can't be undone — corrections require a new copy."
        case .correct: return "The submitted payslip is archived and an editable draft copy is created."
        case nil: return ""
        }
    }

    @ViewBuilder
    private var confirmButtons: some View {
        switch confirmAction {
        case .approve:
            Button("Approve") { transition(to: .approved) }
        case .submit:
            Button("Submit to staff") { transition(to: .submitted) }
        case .correct:
            Button("Create corrected copy") { correct() }
        case nil:
            EmptyView()
        }
        Button("Cancel", role: .cancel) { confirmAction = nil }
    }

    // MARK: State plumbing

    private func binding<T>(_ keyPath: WritableKeyPath<Payslip, T>) -> Binding<T> where T: Equatable {
        Binding(
            get: { slip?[keyPath: keyPath] ?? Payslip(id: "", staffId: "", staffName: "", periodStart: "", periodEnd: "")[keyPath: keyPath] },
            set: { newValue in
                guard slip?[keyPath: keyPath] != newValue else { return }
                slip?[keyPath: keyPath] = newValue
            }
        )
    }

    private func extraBinding(_ index: Int, _ keyPath: WritableKeyPath<PayslipEarning, Double>) -> Binding<Double> {
        Binding(
            get: { slip.flatMap { $0.extraEarnings.indices.contains(index) ? $0.extraEarnings[index][keyPath: keyPath] : nil } ?? 0 },
            set: { newValue in
                guard var current = slip, current.extraEarnings.indices.contains(index) else { return }
                current.extraEarnings[index][keyPath: keyPath] = newValue
                // Keep amount in sync for rate-based rows.
                if keyPath == \.quantity, current.extraEarnings[index].rate > 0 {
                    current.extraEarnings[index].amount = PayrollCalculator.round2(
                        newValue * current.extraEarnings[index].rate)
                }
                slip = current
                markDirty()
            }
        )
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        seedFromRepo(force: true)
    }

    private func seedFromRepo(force: Bool) {
        guard force else { return }
        if let fresh = repo.payslips.first(where: { $0.id == payslipId }) {
            slip = fresh
            isDirty = false
        }
    }

    private func markDirty() {
        guard seeded, slip?.status.isEditable == true else { return }
        isDirty = true
    }

    // MARK: Actions

    private func save() {
        guard let slip, let manager = repo.currentUser else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await repo.savePayslip(slip, editedBy: manager)
                isDirty = false
                toast = ToastMessage(kind: .success, text: "Payslip saved.")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func transition(to status: PayslipStatus, regenerate: Bool = false) {
        guard let slip, let manager = repo.currentUser else { return }
        confirmAction = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if regenerate {
                    try await repo.regenerateDraftPayslip(slip)
                    toast = ToastMessage(kind: .success, text: "Recalculated from current timesheets.")
                } else {
                    // Persist pending edits with the transition so nothing is lost.
                    if isDirty { try await repo.savePayslip(slip, editedBy: manager) }
                    let latest = repo.payslips.first(where: { $0.id == slip.id }) ?? slip
                    try await repo.setPayslipStatus(latest, to: status, by: manager)
                    toast = ToastMessage(kind: .success, text: status == .submitted
                        ? "Submitted — now visible to \(slip.staffName)."
                        : "Moved to \(status.label).")
                }
                isDirty = false
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't update. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func correct() {
        guard let slip else { return }
        confirmAction = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await repo.createCorrectedPayslip(from: slip)
                toast = ToastMessage(kind: .success, text: "Corrected draft created — the original is archived.")
                Haptics.success()
                dismiss()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't create copy. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}

// MARK: - Shared PDF sheet (manager + staff)

/// Renders the payslip PDF and offers view/share/print/save via ShareLink.
struct PayslipPDFSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    let slip: Payslip
    let isManager: Bool

    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    PDFKitView(url: pdfURL)
                } else {
                    ProgressView()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Payslip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share, save or print payslip")
                        .simultaneousGesture(TapGesture().onEnded {
                            if isManager { Task { await repo.recordPayslipDownload(slip) } }
                        })
                    }
                }
            }
            .task { renderPDF() }
        }
    }

    private func renderPDF() {
        // Older payslips have no employeeId snapshot — fill from the user doc
        // so a newly assigned ID still shows on them.
        var slipForRender = slip
        if slipForRender.employeeId.isEmpty {
            slipForRender.employeeId = repo.displayEmployeeId(for: slip)
        }
        let data = PayslipPDFService.render(slipForRender, settings: repo.appSettings)
        let name = "Payslip-\(slip.staffName.replacingOccurrences(of: " ", with: ""))-\(slip.periodStart).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            pdfURL = url
        } catch {
            // Extremely unlikely (temp dir); leave the spinner with no crash.
        }
    }
}

/// Minimal PDFKit wrapper for inline preview.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
