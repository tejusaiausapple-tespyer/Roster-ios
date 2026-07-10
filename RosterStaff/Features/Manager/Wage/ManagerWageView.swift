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
        case lines = "Classification Levels"
        var id: String { rawValue }
    }

    enum ActiveSheet: Identifiable {
        case newAward
        case editAward(WageAward)
        case newLine
        case editLine(EarningsLine)
        case editLegacy(awardId: String, classification: AwardClassification)

        var id: String {
            switch self {
            case .newAward: return "new-award"
            case .editAward(let award): return "award-\(award.id)"
            case .newLine: return "new-line"
            case .editLine(let line): return "line-\(line.id)"
            case .editLegacy(let awardId, let c): return "legacy-\(awardId)-\(c.level)"
            }
        }
    }

    /// Saved classification level — earnings line or legacy row on an award doc.
    private struct ClassificationEntry: Identifiable {
        enum Source {
            case line(EarningsLine)
            case legacy(awardId: String, classification: AwardClassification)
        }

        let id: String
        let source: Source
        let awardName: String?

        var title: String {
            switch source {
            case .line(let line): return line.classificationTitle
            case .legacy(_, let c): return c.title
            }
        }

        var level: String {
            switch source {
            case .line(let line): return line.level
            case .legacy(_, let c): return c.level
            }
        }

        var rateSummary: String {
            switch source {
            case .line(let line): return line.rateSummary
            case .legacy(_, let c):
                if c.weekendHourlyRate > 0 {
                    return String(format: "$%.2f M–F · $%.2f Wknd/PH", c.baseHourlyRate, c.weekendHourlyRate)
                }
                return String(format: "$%.2f/h", c.baseHourlyRate)
            }
        }

        var isLegacy: Bool {
            if case .legacy = source { return true }
            return false
        }
    }

    /// Anything the manager asked to delete via swipe — held here until the
    /// centered alert confirms it. Nothing is deleted without confirmation.
    private enum PendingDelete: Identifiable {
        case award(WageAward)
        case classification(ClassificationEntry)
        case payItem(EarningsLine)

        var id: String {
            switch self {
            case .award(let award): return "award-\(award.id)"
            case .classification(let entry): return "classification-\(entry.id)"
            case .payItem(let line): return "payitem-\(line.id)"
            }
        }

        var title: String {
            switch self {
            case .award: return "Delete wage award?"
            case .classification: return "Delete classification level?"
            case .payItem: return "Delete pay item?"
            }
        }

        var message: String {
            switch self {
            case .award(let award):
                return "“\(award.name)” will be permanently removed. Classification levels linked to this award keep their rates but lose the award reference."
            case .classification(let entry):
                return "“\(entry.title)” will be removed. Staff already assigned to this level keep their assignment until you change it."
            case .payItem(let line):
                return "“\(line.name)” will be permanently removed. Staff assignments that include it stop paying this item."
            }
        }
    }

    @State private var segment: Segment = .awards
    @State private var activeSheet: ActiveSheet?
    @State private var toast: ToastMessage?
    @State private var isAddingConsole = false
    @State private var pendingDelete: PendingDelete?

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
                case .lines: linesSections
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
                .accessibilityLabel(segment == .awards ? "Add wage award" : "Add classification level")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newAward:
                WageAwardEditorSheet(award: nil) { save(award: $0) }
            case .editAward(let award):
                WageAwardEditorSheet(award: award) { save(award: $0) }
            case .newLine:
                EarningsLineEditorSheet(line: nil, onSave: { save(line: $0) }, onSaveMany: { save(lines: $0) })
            case .editLine(let line):
                EarningsLineEditorSheet(line: line, onSave: { save(line: $0) }) {
                    delete(ids: [line.id])
                }
            case .editLegacy(let awardId, let classification):
                EarningsLineEditorSheet(
                    line: EarningsLine.from(classification: classification, awardId: awardId),
                    migrateFromAwardId: awardId,
                    removeLegacyLevel: classification.level,
                    onSave: { save(line: $0, migrateFromAwardId: awardId, removeLegacyLevel: classification.level) },
                    onDelete: { deleteLegacy(awardId: awardId, level: classification.level) }
                )
            }
        }
        .toast($toast)
        // Centered alert (not a bottom action sheet) shared by all three lists.
        .alert(
            pendingDelete?.title ?? "Delete?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { pending in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { performDelete(pending) }
        } message: { pending in
            Text(pending.message)
        }
    }

    // MARK: - Awards

    @ViewBuilder
    private var awardsSection: some View {
        if repo.wageAwards.isEmpty {
            Section {
                Text("No wage awards yet. Add the modern award(s) your staff are employed under (e.g. General Retail Industry Award MA000004).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } footer: {
                Text("Tap + to add a wage award. Classification levels are set up under Classification Levels.")
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
                            Text("\(classificationCount(for: award)) classification level\(classificationCount(for: award) == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = .award(award)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("Tap to edit, swipe left to delete. Assign awards to staff in the Staff tab.")
            }
        }
    }

    // MARK: - Classification levels

    @ViewBuilder
    private var linesSections: some View {
        Section {
            Button {
                Task { await addConsoleAgeRateTable() }
            } label: {
                HStack {
                    if isAddingConsole {
                        ProgressView()
                    } else {
                        Label("Add Console age-rate table", systemImage: "tablecells")
                            .foregroundStyle(Theme.brand)
                    }
                    Spacer()
                }
            }
            .disabled(isAddingConsole)
        } footer: {
            Text("Adds Under 17 through Adult 20+ with Mon–Fri and Weekend & PH rates. Skips levels that already exist. Creates a Console award if needed.")
        }

        if classificationEntries.isEmpty {
            Section {
                Text("No classification levels yet. Use the button above to add the Console age-rate table, or tap + to add levels manually.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Section {
                ForEach(classificationEntries) { entry in
                    Button {
                        openEditor(for: entry)
                    } label: {
                        classificationRow(entry)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = .classification(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Classification levels")
            } footer: {
                Text("Tap to edit, swipe left to delete.")
            }
        }

        if !supplementalPayItems.isEmpty {
            Section("Other pay items") {
                ForEach(supplementalPayItems) { line in
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
                            Text(line.category.label)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = .payItem(line)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func classificationRow(_ entry: ClassificationEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(entry.rateSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.brand)
            }
            HStack(spacing: 6) {
                if let awardName = entry.awardName {
                    Text(awardName)
                }
                if !entry.level.isEmpty {
                    Text("Lvl \(entry.level)")
                }
                if entry.isLegacy {
                    Text("· migrate on save")
                        .foregroundStyle(Theme.warning)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Helpers

    private var classificationEntries: [ClassificationEntry] {
        var entries: [ClassificationEntry] = []
        var coveredLevels: Set<String> = []

        for line in repo.earningsLines where line.isClassificationLevel {
            let key = levelKey(awardId: line.awardId, level: line.level)
            coveredLevels.insert(key)
            entries.append(ClassificationEntry(
                id: "line-\(line.id)",
                source: .line(line),
                awardName: line.awardId.flatMap { awardName(for: $0) }
            ))
        }

        for award in repo.wageAwards {
            let name = award.code.isEmpty ? award.name : award.code
            for classification in award.classifications {
                let key = levelKey(awardId: award.id, level: classification.level)
                guard !coveredLevels.contains(key) else { continue }
                coveredLevels.insert(key)
                entries.append(ClassificationEntry(
                    id: "legacy-\(award.id)-\(classification.level)",
                    source: .legacy(awardId: award.id, classification: classification),
                    awardName: name
                ))
            }
        }

        return entries.sorted {
            ($0.awardName ?? "") < ($1.awardName ?? "")
                || ($0.level.isEmpty ? $0.title : $0.level) < ($1.level.isEmpty ? $1.title : $1.level)
        }
    }

    private var supplementalPayItems: [EarningsLine] {
        repo.earningsLines.filter { !$0.isClassificationLevel }
    }

    private func levelKey(awardId: String?, level: String) -> String {
        "\(awardId ?? "")|\(level)"
    }

    private func openEditor(for entry: ClassificationEntry) {
        switch entry.source {
        case .line(let line):
            activeSheet = .editLine(line)
        case .legacy(let awardId, let classification):
            activeSheet = .editLegacy(awardId: awardId, classification: classification)
        }
    }

    private func addConsoleAgeRateTable() async {
        isAddingConsole = true
        defer { isAddingConsole = false }
        do {
            let awardId = try await repo.ensureConsoleAward()
            let added = try await repo.addConsoleClassificationLevels(for: awardId)
            Haptics.success()
            if added == 0 {
                toast = ToastMessage(kind: .success, text: "Console age-rate levels are already saved.")
            } else {
                toast = ToastMessage(kind: .success, text: "Added \(added) Console classification level\(added == 1 ? "" : "s").")
            }
        } catch {
            toast = ToastMessage(kind: .error, text: "Couldn't add levels. \(error.localizedDescription)")
            Haptics.error()
        }
    }

    private func classificationCount(for award: WageAward) -> Int {
        let fromLines = repo.earningsLines.filter {
            $0.isClassificationLevel && $0.awardId == award.id
        }.count
        if fromLines > 0 { return fromLines }
        return award.classifications.count
    }

    private func awardName(for awardId: String) -> String? {
        guard let award = repo.wageAwards.first(where: { $0.id == awardId }) else { return nil }
        return award.code.isEmpty ? award.name : award.code
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

    private func save(line: EarningsLine, migrateFromAwardId: String? = nil, removeLegacyLevel: String? = nil) {
        Task {
            do {
                if migrateFromAwardId != nil || removeLegacyLevel != nil {
                    try await repo.saveClassificationLine(line, migrateFromAwardId: migrateFromAwardId, removeLegacyLevel: removeLegacyLevel)
                } else {
                    try await repo.saveEarningsLine(line)
                }
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func save(lines: [EarningsLine]) {
        Task {
            var failed = false
            for line in lines {
                do { try await repo.saveEarningsLine(line) } catch { failed = true }
            }
            if failed {
                toast = ToastMessage(kind: .error, text: "Couldn't save some levels.")
                Haptics.error()
            } else {
                Haptics.success()
            }
        }
    }

    private func performDelete(_ pending: PendingDelete) {
        switch pending {
        case .award(let award):
            delete(ids: [award.id], successMessage: "Wage award deleted.")
        case .classification(let entry):
            switch entry.source {
            case .line(let line):
                delete(ids: [line.id], successMessage: "Classification level deleted.")
            case .legacy(let awardId, let classification):
                deleteLegacy(awardId: awardId, level: classification.level)
            }
        case .payItem(let line):
            delete(ids: [line.id], successMessage: "Pay item deleted.")
        }
    }

    private func deleteLegacy(awardId: String, level: String) {
        Task {
            do {
                try await repo.deleteLegacyClassification(awardId: awardId, level: level)
                Haptics.light()
                toast = ToastMessage(kind: .success, text: "Classification level deleted.")
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't delete. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func delete(ids: [String], successMessage: String = "Classification level deleted.") {
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
                toast = ToastMessage(kind: .success, text: successMessage)
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

    init(award: WageAward?, onSave: @escaping (WageAward) -> Void) {
        self.award = award
        self.onSave = onSave
        _name = State(initialValue: award?.name ?? "")
        _code = State(initialValue: award?.code ?? "")
        _industry = State(initialValue: award?.industry ?? "")
        _active = State(initialValue: award?.active ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } header: {
                    Text("Award")
                } footer: {
                    Text("Classification levels and hourly rates are managed under Classification Levels — link each level to this award.")
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
                            classifications: award?.classifications ?? [],
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

// MARK: - Classification level / earnings line editor

private struct EarningsLineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RosterRepository.self) private var repo

    let line: EarningsLine?
    let onSave: (EarningsLine) -> Void
    var onDelete: (() -> Void)?
    var migrateFromAwardId: String?
    var removeLegacyLevel: String?
    /// When set, batch-create Console template levels for this award.
    var onSaveMany: (([EarningsLine]) -> Void)?

    @State private var name: String
    @State private var displayName: String
    @State private var awardId: String
    @State private var level: String
    @State private var baseRateText: String
    @State private var weekendRateText: String
    @State private var category: EarningsCategory
    @State private var rateType: EarningsRateType
    @State private var multiplierText: String
    @State private var fixedRateText: String
    @State private var unitName: String
    @State private var exemptFromSuper: Bool
    @State private var exemptFromTax: Bool
    @State private var active: Bool
    @State private var showDeleteConfirm = false

    private var canDelete: Bool {
        onDelete != nil && (line?.id.isEmpty == false || migrateFromAwardId != nil)
    }

    init(line: EarningsLine?, migrateFromAwardId: String? = nil, removeLegacyLevel: String? = nil,
         onSave: @escaping (EarningsLine) -> Void, onDelete: (() -> Void)? = nil,
         onSaveMany: (([EarningsLine]) -> Void)? = nil) {
        self.line = line
        self.migrateFromAwardId = migrateFromAwardId
        self.removeLegacyLevel = removeLegacyLevel
        self.onSave = onSave
        self.onDelete = onDelete
        self.onSaveMany = onSaveMany
        _name = State(initialValue: line?.name ?? "")
        _displayName = State(initialValue: line?.displayName ?? "")
        _awardId = State(initialValue: line?.awardId ?? "")
        _level = State(initialValue: line?.level ?? "")
        _baseRateText = State(initialValue: line.map {
            $0.baseHourlyRate > 0 ? String(format: "%.2f", $0.baseHourlyRate)
                : ($0.fixedRate > 0 ? String(format: "%.2f", $0.fixedRate) : "")
        } ?? "")
        _weekendRateText = State(initialValue: line.map {
            $0.weekendHourlyRate > 0 ? String(format: "%.2f", $0.weekendHourlyRate) : ""
        } ?? "")
        _category = State(initialValue: line?.category ?? .ordinaryHours)
        _rateType = State(initialValue: line?.rateType ?? .fixedAmount)
        _multiplierText = State(initialValue: line.map { String(format: "%g", $0.multiplier) } ?? "1")
        _fixedRateText = State(initialValue: line.map { String(format: "%.2f", $0.fixedRate) } ?? "")
        _unitName = State(initialValue: line?.unitName ?? "")
        _exemptFromSuper = State(initialValue: line?.exemptFromSuper ?? false)
        _exemptFromTax = State(initialValue: line?.exemptFromTax ?? false)
        _active = State(initialValue: line?.active ?? true)
    }

    private var isClassificationMode: Bool {
        category == .ordinaryHours
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Wage award", selection: $awardId) {
                        Text("None").tag("")
                        ForEach(repo.wageAwards.filter { $0.active || $0.id == awardId }) { award in
                            Text(award.code.isEmpty ? award.name : "\(award.name) (\(award.code))").tag(award.id)
                        }
                    }
                    LabeledContent("Level code") {
                        TextField("e.g. U17, 20+", text: $level)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("Title") {
                        TextField("e.g. Under 17, Adult 20+", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Payslip name") {
                        TextField("Defaults to title", text: $displayName)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        LabeledContent("Mon–Fri ($/h)") {
                            TextField("0.00", text: $baseRateText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                    }
                    LabeledContent("Weekend & PH ($/h)") {
                        TextField("Optional", text: $weekendRateText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    Toggle("Active", isOn: $active)
                        .tint(Theme.brand)
                } header: {
                    Text("Classification level")
                } footer: {
                    Text("Each classification level is an earnings line with ordinary-hours rates. Weekend & PH rate is used by payroll when set — otherwise payroll defaults to base × 1.5 weekend / × 2.25 public holiday.")
                }

                if line == nil, !awardId.isEmpty {
                    Section {
                        Button {
                            let lines = EarningsLine.consoleTemplateLines(awardId: awardId.isEmpty ? nil : awardId)
                            onSaveMany?(lines)
                            dismiss()
                        } label: {
                            Label("Add Console age-rate levels for this award", systemImage: "tablecells")
                        }
                    }
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(EarningsCategory.allCases) { Text($0.label).tag($0) }
                    }
                    if !isClassificationMode {
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
                        Toggle("Exempt from superannuation", isOn: $exemptFromSuper)
                            .tint(Theme.brand)
                        Toggle("Exempt from PAYG withholding", isOn: $exemptFromTax)
                            .tint(Theme.brand)
                    }
                } header: {
                    Text("Other pay items")
                } footer: {
                    if isClassificationMode {
                        Text("Ordinary-hours lines are classification levels. Use another category below only if you also need overtime multipliers, allowances, or bonuses on staff assignments.")
                    } else {
                        Text("Non-ordinary items (overtime, allowances, etc.) can be assigned alongside a staff member's classification level.")
                    }
                }

                if canDelete {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete classification level", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(line == nil ? "New Level" : "Edit Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(buildLine())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: category) { _, newValue in
                if newValue == .ordinaryHours {
                    rateType = .fixedAmount
                }
            }
            .confirmationDialog(
                "Delete this classification level?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var canSave: Bool {
        let title = name.trimmingCharacters(in: .whitespaces)
        if isClassificationMode {
            let base = Double(baseRateText) ?? 0
            return !title.isEmpty && base > 0
        }
        return !title.isEmpty
    }

    private func buildLine() -> EarningsLine {
        let title = name.trimmingCharacters(in: .whitespaces)
        var trimmedLevel = level.trimmingCharacters(in: .whitespaces)
        if trimmedLevel.isEmpty, isClassificationMode {
            trimmedLevel = title.uppercased()
                .replacingOccurrences(of: " ", with: "")
                .prefix(8)
                .description
        }
        let baseRate = Double(baseRateText) ?? 0
        let weekendRate = Double(weekendRateText) ?? 0
        let effectiveCategory = isClassificationMode ? .ordinaryHours : category
        let effectiveRateType = isClassificationMode ? .fixedAmount : rateType
        let effectiveFixed = isClassificationMode ? baseRate : (Double(fixedRateText) ?? 0)

        return EarningsLine(
            id: line?.id ?? "",
            name: title,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            category: effectiveCategory,
            rateType: effectiveRateType,
            multiplier: Double(multiplierText) ?? 1.0,
            fixedRate: effectiveFixed,
            unitName: unitName.trimmingCharacters(in: .whitespaces),
            exemptFromSuper: exemptFromSuper,
            exemptFromTax: exemptFromTax,
            active: active,
            awardId: awardId.isEmpty ? nil : awardId,
            level: trimmedLevel,
            baseHourlyRate: baseRate,
            weekendHourlyRate: weekendRate
        )
    }
}
