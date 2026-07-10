import SwiftUI

/// Manager → Wage: wage awards and earnings lines (pay items), structured
/// after Xero Payroll AU. Everything here is manager-only — the `wages`
/// collection is unreadable by staff under the deployed Firestore rules.
/// Nothing is seeded; managers create and maintain awards/lines manually.
/// Per-staff assignment happens in the Staff tab (ManagerStaffDetailSheet).
struct ManagerWageView: View {
    @Environment(RosterRepository.self) private var repo

    enum Segment: String, CaseIterable, Identifiable {
        case awards = "Wage Awards"
        case lines = "Earnings Lines"
        var id: String { rawValue }
    }

    enum ActiveSheet: Identifiable {
        case newAward
        case editAward(WageAward)
        case newLine
        case editLine(EarningsLine)

        var id: String {
            switch self {
            case .newAward: return "new-award"
            case .editAward(let award): return "award-\(award.id)"
            case .newLine: return "new-line"
            case .editLine(let line): return "line-\(line.id)"
            }
        }
    }

    @State private var segment: Segment = .awards
    @State private var activeSheet: ActiveSheet?
    @State private var toast: ToastMessage?

    var embedInNavigationStack = true

    var body: some View {
        if embedInNavigationStack {
            NavigationStack { rootContent }
        } else {
            rootContent
        }
    }

    private var rootContent: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            List {
                TitlePillCollapseReporter()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                switch segment {
                case .awards: awardsSection
                case .lines: linesSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Wage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Wage Setup", icon: "dollarsign.circle.fill")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = segment == .awards ? .newAward : .newLine
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(segment == .awards ? "Add wage award" : "Add earnings line")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newAward:
                WageAwardEditorSheet(award: nil) { save(award: $0) }
            case .editAward(let award):
                WageAwardEditorSheet(award: award) { save(award: $0) }
            case .newLine:
                EarningsLineEditorSheet(line: nil) { save(line: $0) }
            case .editLine(let line):
                EarningsLineEditorSheet(line: line) { save(line: $0) }
            }
        }
        .toast($toast)
    }

    // MARK: - Awards

    @ViewBuilder
    private var awardsSection: some View {
        if repo.wageAwards.isEmpty {
            Section {
                Text("No wage awards yet. Add the modern award(s) your staff are employed under (e.g. General Retail Industry Award MA000004) with their classification levels and base hourly rates.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Section {
                ForEach(repo.wageAwards) { award in
                    Button {
                        activeSheet = .editAward(award)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(award.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if !award.active {
                                    Text("Inactive")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            Text([award.code, award.industry].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(award.classifications.count) classification level\(award.classifications.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .onDelete { offsets in delete(ids: offsets.map { repo.wageAwards[$0].id }) }
            } footer: {
                Text("Tap to edit. Assign awards to staff in the Staff tab.")
            }
        }
    }

    // MARK: - Earnings lines

    @ViewBuilder
    private var linesSection: some View {
        if repo.earningsLines.isEmpty {
            Section {
                Text("No earnings lines yet. Add pay items such as Ordinary Hours, Overtime 1.5×, allowances or bonuses — with their rate type and super/tax treatment.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Section {
                ForEach(repo.earningsLines) { line in
                    Button {
                        activeSheet = .editLine(line)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(line.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(line.rateSummary)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.brand)
                            }
                            HStack(spacing: 6) {
                                Text(line.category.label)
                                if line.exemptFromSuper { Text("· no super") }
                                if line.exemptFromTax { Text("· no PAYG") }
                                if !line.active { Text("· inactive") }
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .onDelete { offsets in delete(ids: offsets.map { repo.earningsLines[$0].id }) }
            } footer: {
                Text("Tap to edit. Assign earnings lines to staff in the Staff tab — staff can never see them.")
            }
        }
    }

    // MARK: - Actions

    private func save(award: WageAward) {
        Task {
            do {
                try await repo.saveWageAward(award)
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func save(line: EarningsLine) {
        Task {
            do {
                try await repo.saveEarningsLine(line)
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func delete(ids: [String]) {
        Task {
            var failed = false
            for id in ids {
                do { try await repo.deleteWageDocument(id: id) } catch { failed = true }
            }
            if failed {
                toast = ToastMessage(kind: .error, text: "Couldn't delete some items.")
                Haptics.error()
            } else {
                Haptics.light()
            }
        }
    }
}

// MARK: - Award editor

private struct WageAwardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let award: WageAward?
    let onSave: (WageAward) -> Void

    @State private var name: String
    @State private var code: String
    @State private var industry: String
    @State private var active: Bool
    @State private var classifications: [EditableClassification]

    struct EditableClassification: Identifiable {
        let id = UUID()
        var level: String
        var title: String
        var rateText: String
    }

    init(award: WageAward?, onSave: @escaping (WageAward) -> Void) {
        self.award = award
        self.onSave = onSave
        _name = State(initialValue: award?.name ?? "")
        _code = State(initialValue: award?.code ?? "")
        _industry = State(initialValue: award?.industry ?? "")
        _active = State(initialValue: award?.active ?? true)
        _classifications = State(initialValue: (award?.classifications ?? []).map {
            EditableClassification(level: $0.level, title: $0.title,
                                   rateText: String(format: "%.2f", $0.baseHourlyRate))
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Award") {
                    LabeledContent("Name") {
                        TextField("e.g. General Retail Industry Award", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Code") {
                        TextField("e.g. MA000004", text: $code)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("Industry") {
                        TextField("Optional", text: $industry)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Active", isOn: $active)
                        .tint(Theme.brand)
                }

                Section {
                    ForEach($classifications) { $classification in
                        HStack(spacing: 8) {
                            TextField("Lvl", text: $classification.level)
                                .frame(width: 40)
                            TextField("Title", text: $classification.title)
                            HStack(spacing: 2) {
                                Text("$").foregroundStyle(Theme.textTertiary)
                                TextField("0.00", text: $classification.rateText)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 64)
                            }
                        }
                        .font(.subheadline)
                    }
                    .onDelete { classifications.remove(atOffsets: $0) }

                    Button {
                        classifications.append(EditableClassification(level: "\(classifications.count + 1)", title: "", rateText: ""))
                    } label: {
                        Label("Add classification level", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Classification levels")
                } footer: {
                    Text("Level, title and base hourly rate — e.g. 2 / Retail Employee Level 2 / $26.18. Swipe to remove.")
                }
            }
            .navigationTitle(award == nil ? "New Award" : "Edit Award")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(WageAward(
                            id: award?.id ?? "",
                            name: name.trimmingCharacters(in: .whitespaces),
                            code: code.trimmingCharacters(in: .whitespaces),
                            industry: industry.trimmingCharacters(in: .whitespaces),
                            classifications: classifications.compactMap {
                                let title = $0.title.trimmingCharacters(in: .whitespaces)
                                guard !title.isEmpty else { return nil }
                                return AwardClassification(level: $0.level.trimmingCharacters(in: .whitespaces),
                                                           title: title,
                                                           baseHourlyRate: Double($0.rateText) ?? 0)
                            },
                            active: active
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Earnings line editor

private struct EarningsLineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let line: EarningsLine?
    let onSave: (EarningsLine) -> Void

    @State private var name: String
    @State private var displayName: String
    @State private var category: EarningsCategory
    @State private var rateType: EarningsRateType
    @State private var multiplierText: String
    @State private var fixedRateText: String
    @State private var unitName: String
    @State private var exemptFromSuper: Bool
    @State private var exemptFromTax: Bool
    @State private var active: Bool

    init(line: EarningsLine?, onSave: @escaping (EarningsLine) -> Void) {
        self.line = line
        self.onSave = onSave
        _name = State(initialValue: line?.name ?? "")
        _displayName = State(initialValue: line?.displayName ?? "")
        _category = State(initialValue: line?.category ?? .ordinaryHours)
        _rateType = State(initialValue: line?.rateType ?? .multipleOfOrdinary)
        _multiplierText = State(initialValue: line.map { String(format: "%g", $0.multiplier) } ?? "1")
        _fixedRateText = State(initialValue: line.map { String(format: "%.2f", $0.fixedRate) } ?? "")
        _unitName = State(initialValue: line?.unitName ?? "")
        _exemptFromSuper = State(initialValue: line?.exemptFromSuper ?? false)
        _exemptFromTax = State(initialValue: line?.exemptFromTax ?? false)
        _active = State(initialValue: line?.active ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Earnings line") {
                    LabeledContent("Name") {
                        TextField("e.g. Overtime 1.5×", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Payslip name") {
                        TextField("Defaults to name", text: $displayName)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(EarningsCategory.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Rate") {
                    Picker("Rate type", selection: $rateType) {
                        ForEach(EarningsRateType.allCases) { Text($0.label).tag($0) }
                    }
                    switch rateType {
                    case .multipleOfOrdinary:
                        LabeledContent("Multiplier") {
                            TextField("1.5", text: $multiplierText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                    case .fixedAmount:
                        LabeledContent("Amount ($)") {
                            TextField("0.00", text: $fixedRateText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                    case .ratePerUnit:
                        LabeledContent("Rate ($)") {
                            TextField("0.00", text: $fixedRateText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                        LabeledContent("Unit") {
                            TextField("e.g. km", text: $unitName)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section {
                    Toggle("Exempt from superannuation", isOn: $exemptFromSuper)
                        .tint(Theme.brand)
                    Toggle("Exempt from PAYG withholding", isOn: $exemptFromTax)
                        .tint(Theme.brand)
                    Toggle("Active", isOn: $active)
                        .tint(Theme.brand)
                } footer: {
                    Text("Exemption flags follow ATO/STP treatment of the pay item (as in Xero's earnings rate settings).")
                }
            }
            .navigationTitle(line == nil ? "New Earnings Line" : "Edit Earnings Line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(EarningsLine(
                            id: line?.id ?? "",
                            name: name.trimmingCharacters(in: .whitespaces),
                            displayName: displayName.trimmingCharacters(in: .whitespaces),
                            category: category,
                            rateType: rateType,
                            multiplier: Double(multiplierText) ?? 1.0,
                            fixedRate: Double(fixedRateText) ?? 0,
                            unitName: unitName.trimmingCharacters(in: .whitespaces),
                            exemptFromSuper: exemptFromSuper,
                            exemptFromTax: exemptFromTax,
                            active: active
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
