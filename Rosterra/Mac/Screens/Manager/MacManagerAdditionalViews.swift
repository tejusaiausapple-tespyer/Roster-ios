#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Mac Manager Wage View

struct MacManagerWageView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    private enum Section: String, CaseIterable, Identifiable {
        case awards = "Awards"
        case classifications = "Classifications"
        case payItems = "Pay items"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .awards: return "doc.text.fill"
            case .classifications: return "person.text.rectangle"
            case .payItems: return "plus.forwardslash.minus"
            }
        }
    }

    private struct ClassificationRow: Identifiable {
        enum Source {
            case line(EarningsLine)
            case legacy(awardId: String, classification: AwardClassification)
        }

        let id: String
        let source: Source
        let awardName: String
        let awardCode: String

        var title: String {
            switch source {
            case .line(let line): return line.classificationTitle
            case .legacy(_, let classification): return classification.title
            }
        }

        var level: String {
            switch source {
            case .line(let line): return line.level
            case .legacy(_, let classification): return classification.level
            }
        }

        var baseRate: Double {
            switch source {
            case .line(let line): return line.baseHourlyRate > 0 ? line.baseHourlyRate : line.fixedRate
            case .legacy(_, let classification): return classification.baseHourlyRate
            }
        }

        var weekendRate: Double {
            switch source {
            case .line(let line): return line.weekendHourlyRate
            case .legacy(_, let classification): return classification.weekendHourlyRate
            }
        }

        var active: Bool {
            if case .line(let line) = source { return line.active }
            return true
        }

        var isLegacy: Bool {
            if case .legacy = source { return true }
            return false
        }
    }

    private enum ActiveSheet: Identifiable {
        case award(WageAward?)
        case line(EarningsLine?)
        case legacy(awardId: String, classification: AwardClassification)

        var id: String {
            switch self {
            case .award(let award): return "award-\(award?.id ?? "new")"
            case .line(let line): return "line-\(line?.id ?? "new")"
            case .legacy(let awardId, let classification): return "legacy-\(awardId)-\(classification.level)"
            }
        }
    }

    private enum PendingDelete: Identifiable {
        case award(WageAward)
        case classification(ClassificationRow)
        case payItem(EarningsLine)

        var id: String {
            switch self {
            case .award(let award): return "award-\(award.id)"
            case .classification(let row): return "classification-\(row.id)"
            case .payItem(let line): return "pay-item-\(line.id)"
            }
        }

        var title: String {
            switch self {
            case .award: return "Delete wage award?"
            case .classification: return "Delete classification?"
            case .payItem: return "Delete pay item?"
            }
        }

        var message: String {
            switch self {
            case .award(let award):
                return "\u{201c}\(award.name)\u{201d} will be removed. Linked classifications keep their rates but lose the award reference."
            case .classification(let row):
                return "\u{201c}\(row.title)\u{201d} will be removed. Existing staff assignments remain until they are changed."
            case .payItem(let line):
                return "\u{201c}\(line.name)\u{201d} will be removed from every staff wage assignment."
            }
        }
    }

    @State private var section: Section = .awards
    @State private var searchText = ""
    @State private var selectedID: String?
    @State private var activeSheet: ActiveSheet?
    @State private var pendingDelete: PendingDelete?

    init() {}

    var body: some View {
        MacScreen(
            title: "Wage Awards & Rates",
            subtitle: "Awards, classifications and payroll rates",
            actions: { toolbarActions }
        ) {
            screenContent
        }
        .onAppear { maintainSelection() }
        .onChange(of: section) { _, _ in
            searchText = ""
            selectedID = nil
            maintainSelection()
        }
        .onChange(of: visibleIDs) { _, _ in maintainSelection() }
        .sheet(item: $activeSheet) { sheet in
            editor(for: sheet)
                .frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 680)
                .macObserved(repo: repo, toasts: toasts)
        }
        .alert(
            pendingDelete?.title ?? "Delete item?",
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

    @ViewBuilder
    private var toolbarActions: some View {
        MacRefreshButton("Refresh wage data") {
            await repo.refreshFromServer()
        }

        Button {
            createNewItem()
        } label: {
            Image(systemName: "plus")
        }
        .keyboardShortcut("n", modifiers: [.command])
        .help(addButtonTitle)
        .accessibilityLabel(addButtonTitle)
    }

    private var screenContent: some View {
        VStack(spacing: 0) {
            controls

            summaryStrip
                .padding(.horizontal, MacSpace.xl)
                .padding(.bottom, MacSpace.lg)

            workspacePanels
                .padding(.horizontal, MacSpace.xl)
                .padding(.bottom, MacSpace.xl)
        }
    }

    private var workspacePanels: some View {
        HStack(spacing: MacSpace.lg) {
            AnyView(recordsPanel)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

            AnyView(inspectorPanel)
                .frame(width: 350)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Data

    private var classificationRows: [ClassificationRow] {
        var rows: [ClassificationRow] = []
        var coveredLevels: Set<String> = []

        for line in repo.earningsLines where line.isClassificationLevel {
            let key = levelKey(awardId: line.awardId, level: line.level)
            coveredLevels.insert(key)
            let award = line.awardId.flatMap { id in repo.wageAwards.first { $0.id == id } }
            rows.append(ClassificationRow(
                id: "line-\(line.id)",
                source: .line(line),
                awardName: award?.name ?? "No award",
                awardCode: award?.code ?? ""
            ))
        }

        for award in repo.wageAwards {
            for classification in award.classifications {
                let key = levelKey(awardId: award.id, level: classification.level)
                guard !coveredLevels.contains(key) else { continue }
                rows.append(ClassificationRow(
                    id: "legacy-\(award.id)-\(classification.level)",
                    source: .legacy(awardId: award.id, classification: classification),
                    awardName: award.name,
                    awardCode: award.code
                ))
            }
        }

        return rows.sorted {
            if $0.awardName != $1.awardName {
                return $0.awardName.localizedCaseInsensitiveCompare($1.awardName) == .orderedAscending
            }
            return ClassificationDisplayOrder.areInOrder(
                levelA: $0.level, titleA: $0.title,
                levelB: $1.level, titleB: $1.title
            )
        }
    }

    private var payItems: [EarningsLine] {
        repo.earningsLines
            .filter { !$0.isClassificationLevel }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredAwards: [WageAward] {
        repo.wageAwards
            .filter { matchesSearch([$0.name, $0.code, $0.industry]) }
            .sorted { lhs, rhs in
                if lhs.active != rhs.active { return lhs.active }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var filteredClassifications: [ClassificationRow] {
        classificationRows.filter { matchesSearch([$0.title, $0.level, $0.awardName, $0.awardCode]) }
    }

    private var filteredPayItems: [EarningsLine] {
        payItems.filter { matchesSearch([$0.name, $0.displayName, $0.category.label, $0.rateSummary]) }
    }

    private var visibleIDs: [String] {
        switch section {
        case .awards: return filteredAwards.map(\.id)
        case .classifications: return filteredClassifications.map(\.id)
        case .payItems: return filteredPayItems.map(\.id)
        }
    }

    private func matchesSearch(_ values: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return values.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func levelKey(awardId: String?, level: String) -> String {
        "\(awardId ?? "")|\(level)"
    }

    private func classificationCount(for award: WageAward) -> Int {
        let lineCount = repo.earningsLines.filter {
            $0.isClassificationLevel && $0.awardId == award.id
        }.count
        return lineCount > 0 ? lineCount : award.classifications.count
    }

    // MARK: - Controls and summary

    private var controls: some View {
        HStack(spacing: MacSpace.lg) {
            HStack(spacing: MacSpace.xs) {
                ForEach(Section.allCases) { item in
                    sectionButton(item)
                }
            }
            .padding(4)
            .background(MacColor.cardBackgroundSecondary, in: Capsule())
            .overlay { Capsule().strokeBorder(MacColor.cardBorder, lineWidth: 1) }

            Spacer()

            HStack(spacing: MacSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MacColor.textTertiary)
                TextField("Search \(section.rawValue.lowercased())", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MacType.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MacColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MacSpace.md)
            .frame(width: 250, height: 34)
            .background(MacColor.cardBackground, in: RoundedRectangle(cornerRadius: MacRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
    }

    private func sectionButton(_ item: Section) -> some View {
        let selected = section == item
        return Button {
            withAnimation(MacMotion.fast) { section = item }
        } label: {
            Label(item.rawValue, systemImage: item.icon)
                .font(MacType.captionStrong)
                .foregroundStyle(selected ? MacColor.textPrimary : MacColor.textSecondary)
                .padding(.horizontal, MacSpace.md)
                .padding(.vertical, 7)
                .background(selected ? MacColor.cardBackground : Color.clear, in: Capsule())
                .shadow(color: selected ? Color.black.opacity(0.06) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryMetric(
                title: "Active awards",
                value: "\(repo.wageAwards.filter(\.active).count)",
                detail: "\(repo.wageAwards.count) total",
                icon: "doc.text.fill",
                tint: MacColor.accent
            )
            summaryDivider
            summaryMetric(
                title: "Classifications",
                value: "\(classificationRows.count)",
                detail: "Ordinary-hour rates",
                icon: "person.text.rectangle",
                tint: MacColor.info
            )
            summaryDivider
            summaryMetric(
                title: "Pay items",
                value: "\(payItems.count)",
                detail: "Allowances & overtime",
                icon: "plus.forwardslash.minus",
                tint: MacColor.warning
            )
            summaryDivider
            summaryMetric(
                title: "Assigned staff",
                value: "\(assignedStaffCount)",
                detail: "\(repo.staffMembers.count) staff total",
                icon: "person.2.fill",
                tint: MacColor.success
            )
        }
        .padding(.vertical, MacSpace.md)
        .background(MacColor.cardBackground, in: RoundedRectangle(cornerRadius: MacRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var assignedStaffCount: Int {
        repo.staffWageProfiles.filter {
            $0.active && ($0.awardId != nil || $0.hourlyRateOverride != nil)
        }.count
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

    // MARK: - Records

    private var recordsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.rawValue)
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Text(recordsSubtitle)
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }
                Spacer()
                Text("\(visibleIDs.count)")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(MacColor.accent.opacity(0.12), in: Capsule())
            }
            .padding(MacSpace.lg)

            Divider().overlay(MacColor.separator)

            if visibleIDs.isEmpty {
                MacEmptyState(
                    title: searchText.isEmpty ? emptyTitle : "No matches",
                    subtitle: searchText.isEmpty ? emptySubtitle : "Try a different name, code or category.",
                    icon: searchText.isEmpty ? section.icon : "magnifyingglass",
                    actionTitle: searchText.isEmpty ? addButtonTitle : nil,
                    action: searchText.isEmpty ? createNewItem : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        switch section {
                        case .awards:
                            ForEach(filteredAwards) { awardRow($0) }
                        case .classifications:
                            ForEach(filteredClassifications) { classificationRow($0) }
                        case .payItems:
                            ForEach(filteredPayItems) { payItemRow($0) }
                        }
                    }
                }
            }
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private var recordsSubtitle: String {
        switch section {
        case .awards: return "Modern awards used by your team"
        case .classifications: return "Weekday and weekend hourly rates"
        case .payItems: return "Allowances, loadings, overtime and bonuses"
        }
    }

    private var emptyTitle: String {
        switch section {
        case .awards: return "No wage awards"
        case .classifications: return "No classifications"
        case .payItems: return "No pay items"
        }
    }

    private var emptySubtitle: String {
        switch section {
        case .awards: return "Add the modern award your staff are employed under."
        case .classifications: return "Add each award level and its current hourly rates."
        case .payItems: return "Add optional allowances, overtime rates or bonuses."
        }
    }

    private func awardRow(_ award: WageAward) -> some View {
        recordButton(id: award.id) {
            HStack(spacing: MacSpace.md) {
                iconWell("doc.text.fill", tint: award.active ? MacColor.accent : MacColor.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(award.name)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(1)
                    Text([award.code, award.industry].filter { !$0.isEmpty }.joined(separator: "  ·  ").nilIfEmpty ?? "No award code or industry")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(classificationCount(for: award)) levels")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textSecondary)
                statusPill(active: award.active)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacColor.textTertiary)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { activeSheet = .award(award) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = .award(award) }
        }
    }

    private func classificationRow(_ row: ClassificationRow) -> some View {
        recordButton(id: row.id) {
            HStack(spacing: MacSpace.md) {
                levelWell(row.level)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(1)
                    Text([row.awardCode, row.awardName].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(currencyRate(row.baseRate))
                        .font(MacType.monoStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    Text(row.weekendRate > 0 ? "\(currencyRate(row.weekendRate)) weekend" : "Default penalties")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }
                if row.isLegacy {
                    Text("LEGACY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MacColor.warning)
                } else {
                    statusPill(active: row.active)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacColor.textTertiary)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { open(row) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = .classification(row) }
        }
    }

    private func payItemRow(_ line: EarningsLine) -> some View {
        recordButton(id: line.id) {
            HStack(spacing: MacSpace.md) {
                iconWell("plus.forwardslash.minus", tint: MacColor.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(1)
                    Text(line.category.label)
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }
                Spacer()
                Text(line.rateSummary)
                    .font(MacType.monoStrong)
                    .foregroundStyle(MacColor.textPrimary)
                statusPill(active: line.active)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacColor.textTertiary)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { activeSheet = .line(line) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = .payItem(line) }
        }
    }

    private func recordButton<Content: View>(id: String, @ViewBuilder content: () -> Content) -> some View {
        let selected = selectedID == id
        return Button {
            selectedID = id
        } label: {
            content()
                .padding(.horizontal, MacSpace.lg)
                .frame(minHeight: 68)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? MacColor.tableRowSelected : Color.clear)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    Rectangle().fill(MacColor.separator.opacity(0.7)).frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func iconWell(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: MacRadius.medium))
    }

    private func levelWell(_ level: String) -> some View {
        Text(level.isEmpty ? "—" : level)
            .font(MacType.badge)
            .foregroundStyle(MacColor.info)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 42, height: 36)
            .background(MacColor.info.opacity(0.11), in: RoundedRectangle(cornerRadius: MacRadius.medium))
    }

    private func statusPill(active: Bool) -> some View {
        Text(active ? "Active" : "Inactive")
            .font(MacType.badge)
            .foregroundStyle(active ? MacColor.success : MacColor.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((active ? MacColor.success : MacColor.textTertiary).opacity(0.1), in: Capsule())
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorPanel: some View {
        switch section {
        case .awards:
            if let award = filteredAwards.first(where: { $0.id == selectedID }) {
                awardInspector(award)
            } else {
                inspectorPlaceholder
            }
        case .classifications:
            if let row = filteredClassifications.first(where: { $0.id == selectedID }) {
                classificationInspector(row)
            } else {
                inspectorPlaceholder
            }
        case .payItems:
            if let line = filteredPayItems.first(where: { $0.id == selectedID }) {
                payItemInspector(line)
            } else {
                inspectorPlaceholder
            }
        }
    }

    private func awardInspector(_ award: WageAward) -> some View {
        inspectorCard {
            inspectorHeader(icon: "doc.text.fill", tint: MacColor.accent, title: award.name, subtitle: award.code.nilIfEmpty ?? "No award code")
            inspectorDivider
            detailRow("Status", value: award.active ? "Active" : "Inactive")
            detailRow("Industry", value: award.industry.nilIfEmpty ?? "Not specified")
            detailRow("Classifications", value: "\(classificationCount(for: award))")
            detailRow("Assigned staff", value: "\(repo.staffWageProfiles.filter { $0.awardId == award.id }.count)")
            inspectorDivider
            VStack(alignment: .leading, spacing: MacSpace.sm) {
                Text("LINKED LEVELS")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.textTertiary)
                    .tracking(0.5)
                let rows = classificationRows.filter {
                    switch $0.source {
                    case .line(let line): return line.awardId == award.id
                    case .legacy(let awardId, _): return awardId == award.id
                    }
                }
                if rows.isEmpty {
                    Text("No classifications linked yet.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                } else {
                    ForEach(rows.prefix(5)) { row in
                        HStack {
                            Text(row.level.isEmpty ? "—" : row.level)
                                .font(MacType.badge)
                                .foregroundStyle(MacColor.info)
                                .frame(width: 38, alignment: .leading)
                            Text(row.title)
                                .font(MacType.caption)
                                .foregroundStyle(MacColor.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(currencyRate(row.baseRate))
                                .font(MacType.mono)
                        }
                    }
                    if rows.count > 5 {
                        Text("+ \(rows.count - 5) more")
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.accent)
                    }
                }
            }
            Spacer(minLength: MacSpace.lg)
            inspectorActions(
                edit: { activeSheet = .award(award) },
                delete: { pendingDelete = .award(award) }
            )
        }
    }

    private func classificationInspector(_ row: ClassificationRow) -> some View {
        inspectorCard {
            inspectorHeader(icon: "person.text.rectangle", tint: MacColor.info, title: row.title, subtitle: "Level \(row.level.isEmpty ? "—" : row.level)")
            inspectorDivider
            detailRow("Award", value: row.awardCode.nilIfEmpty ?? row.awardName)
            detailRow("Mon–Fri", value: currencyRate(row.baseRate))
            detailRow("Weekend & PH", value: row.weekendRate > 0 ? currencyRate(row.weekendRate) : "Payroll default")
            detailRow("Status", value: row.active ? "Active" : "Inactive")
            if row.isLegacy {
                HStack(alignment: .top, spacing: MacSpace.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(MacColor.warning)
                    Text("This is a legacy embedded rate. Saving it migrates the level to the current payroll format.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                }
                .padding(MacSpace.md)
                .background(MacColor.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: MacRadius.medium))
            }
            Spacer(minLength: MacSpace.lg)
            inspectorActions(edit: { open(row) }, delete: { pendingDelete = .classification(row) })
        }
    }

    private func payItemInspector(_ line: EarningsLine) -> some View {
        inspectorCard {
            inspectorHeader(icon: "plus.forwardslash.minus", tint: MacColor.warning, title: line.name, subtitle: line.category.label)
            inspectorDivider
            detailRow("Payslip name", value: line.displayName)
            detailRow("Rate", value: line.rateSummary)
            detailRow("Status", value: line.active ? "Active" : "Inactive")
            detailRow("Super", value: line.exemptFromSuper ? "Exempt" : "Included")
            detailRow("PAYG", value: line.exemptFromTax ? "Exempt" : "Included")
            Spacer(minLength: MacSpace.lg)
            inspectorActions(edit: { activeSheet = .line(line) }, delete: { pendingDelete = .payItem(line) })
        }
    }

    private var inspectorPlaceholder: some View {
        inspectorCard {
            MacEmptyState(
                title: "Select an item",
                subtitle: "Choose a record to view its setup and actions.",
                icon: "sidebar.right"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func inspectorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            content()
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func inspectorHeader(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: MacSpace.md) {
            iconWell(icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }
        }
    }

    private var inspectorDivider: some View {
        Rectangle().fill(MacColor.separator).frame(height: 1)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
            Spacer()
            Text(value)
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func inspectorActions(edit: @escaping () -> Void, delete: @escaping () -> Void) -> some View {
        HStack(spacing: MacSpace.sm) {
            Button(action: edit) { Label("Edit", systemImage: "pencil") }
                .macButton(.prominent, size: .medium, fullWidth: true)
            Button(action: delete) { Image(systemName: "trash") }
                .macButton(.destructive, size: .medium)
                .help("Delete")
        }
    }

    // MARK: - Actions

    private var addButtonTitle: String {
        switch section {
        case .awards: return "Add award"
        case .classifications: return "Add classification"
        case .payItems: return "Add pay item"
        }
    }

    private func createNewItem() {
        switch section {
        case .awards: activeSheet = .award(nil)
        case .classifications, .payItems: activeSheet = .line(nil)
        }
    }

    private func maintainSelection() {
        guard !visibleIDs.isEmpty else {
            selectedID = nil
            return
        }
        if selectedID == nil || !visibleIDs.contains(selectedID!) {
            selectedID = visibleIDs.first
        }
    }

    private func open(_ row: ClassificationRow) {
        switch row.source {
        case .line(let line): activeSheet = .line(line)
        case .legacy(let awardId, let classification):
            activeSheet = .legacy(awardId: awardId, classification: classification)
        }
    }

    @ViewBuilder
    private func editor(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .award(let award):
            WageAwardEditorSheet(award: award) { save(award: $0) }
        case .line(let line):
            EarningsLineEditorSheet(
                line: line,
                onSave: { save(line: $0) },
                onDelete: line.map { existing in { deleteDocument(id: existing.id, message: "Pay item deleted.") } }
            )
        case .legacy(let awardId, let classification):
            EarningsLineEditorSheet(
                line: EarningsLine.from(classification: classification, awardId: awardId),
                migrateFromAwardId: awardId,
                removeLegacyLevel: classification.level,
                onSave: { save(line: $0, migrateFromAwardId: awardId, removeLegacyLevel: classification.level) },
                onDelete: { deleteLegacy(awardId: awardId, level: classification.level) }
            )
        }
    }

    private func save(award: WageAward) {
        Task {
            do {
                try await repo.saveWageAward(award)
                toasts.show(award.id.isEmpty ? "Wage award added." : "Wage award updated.", style: .success)
            } catch {
                toasts.show("Couldn\u{2019}t save the wage award. \(error.localizedDescription)", style: .error)
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
                toasts.show(line.id.isEmpty ? "Rate added." : "Rate updated.", style: .success)
            } catch {
                toasts.show("Couldn\u{2019}t save the rate. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func performDelete(_ pending: PendingDelete) {
        pendingDelete = nil
        switch pending {
        case .award(let award):
            deleteDocument(id: award.id, message: "Wage award deleted.")
        case .classification(let row):
            switch row.source {
            case .line(let line): deleteDocument(id: line.id, message: "Classification deleted.")
            case .legacy(let awardId, let classification): deleteLegacy(awardId: awardId, level: classification.level)
            }
        case .payItem(let line):
            deleteDocument(id: line.id, message: "Pay item deleted.")
        }
    }

    private func deleteDocument(id: String, message: String) {
        Task {
            do {
                try await repo.deleteWageDocument(id: id)
                toasts.show(message, style: .success)
            } catch {
                toasts.show("Couldn\u{2019}t delete this item. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func deleteLegacy(awardId: String, level: String) {
        Task {
            do {
                try await repo.deleteLegacyClassification(awardId: awardId, level: level)
                toasts.show("Classification deleted.", style: .success)
            } catch {
                toasts.show("Couldn\u{2019}t delete this classification. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func currencyRate(_ value: Double) -> String {
        String(format: "$%.2f/h", value)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
    @Environment(MacToastCenter.self) private var toasts

    @State private var selectedLocationID: String?
    @State private var editor: ManagerLocationsView.EditorMode?
    @State private var locationToDelete: RosterLocation?
    @State private var isWorking = false

    init() {}

    private var selectedLocation: RosterLocation? {
        repo.locations.first { $0.id == selectedLocationID } ?? repo.locations.first
    }

    private var geofencedCount: Int {
        repo.locations.filter(\.hasGeofence).count
    }

    private var enforcedCount: Int {
        repo.locations.filter { $0.hasGeofence && $0.geofenceEnforced }.count
    }

    var body: some View {
        MacScreen(
            title: "Work Locations",
            subtitle: "Manage workplaces and attendance boundaries",
            actions: {
            Button {
                editor = .add
            } label: {
                Label("Add work location", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
        }) {
            if repo.locations.isEmpty {
                MacEmptyState(
                    title: "No Work Locations",
                    subtitle: "Add the suburbs your staff work in. Locations appear when creating shifts and can verify attendance with a geofence.",
                    icon: "mappin.and.ellipse",
                    actionTitle: "Add Location",
                    action: { editor = .add }
                )
            } else {
                VStack(spacing: 0) {
                    summaryBar
                    Divider()
                        .overlay(MacColor.separator)

                    HStack(spacing: 0) {
                        locationsList
                            .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)

                        Divider()
                            .overlay(MacColor.separator)

                        if let selectedLocation {
                            locationDetail(selectedLocation)
                        }
                    }
                }
            }
        }
        .sheet(item: $editor) { mode in
            LocationEditorSheet(mode: mode) { location in
                Task { await save(mode: mode, location: location) }
            }
        }
        .confirmationDialog(
            "Delete Work Location?",
            isPresented: Binding(
                get: { locationToDelete != nil },
                set: { if !$0 { locationToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Location", role: .destructive) {
                if let locationToDelete {
                    Task { await delete(locationToDelete) }
                }
            }
            Button("Cancel", role: .cancel) {
                locationToDelete = nil
            }
        } message: {
            Text("Existing shifts keep their saved location. This action cannot be undone.")
        }
        .disabled(isWorking)
        .onAppear {
            if selectedLocationID == nil {
                selectedLocationID = repo.locations.first?.id
            }
        }
        .onChange(of: repo.locations) { _, locations in
            if !locations.contains(where: { $0.id == selectedLocationID }) {
                selectedLocationID = locations.first?.id
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryMetric(
                value: "\(repo.locations.count)",
                label: "Locations",
                icon: "mappin.and.ellipse",
                tint: MacColor.accent
            )
            summaryMetric(
                value: "\(geofencedCount)",
                label: "Geofenced",
                icon: "location.circle.fill",
                tint: .green
            )
            summaryMetric(
                value: "\(enforcedCount)",
                label: "Strict enforcement",
                icon: "lock.shield.fill",
                tint: .orange
            )
            Spacer(minLength: MacSpace.lg)
            Text("Editing or deleting a location does not change existing shifts.")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
        .background(MacColor.cardBackground)
    }

    private func summaryMetric(value: String, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: MacSpace.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: MacRadius.small))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
                Text(label)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private var locationsList: some View {
        ScrollView {
            LazyVStack(spacing: MacSpace.xs) {
                ForEach(repo.locations) { location in
                    let iconTint = location.hasGeofence ? MacColor.accent : MacColor.textTertiary
                    let selectionBackground = selectedLocation?.id == location.id
                        ? MacColor.accent.opacity(0.10)
                        : Color.clear

                    Button {
                        selectedLocationID = location.id
                    } label: {
                        HStack(spacing: MacSpace.md) {
                            Image(systemName: location.hasGeofence ? "mappin.circle.fill" : "mappin.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(iconTint)
                                .frame(width: 34, height: 34)
                                .background(
                                    iconTint.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: MacRadius.small)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(location.displayName)
                                    .font(MacType.bodyStrong)
                                    .foregroundStyle(MacColor.textPrimary)
                                Text(location.city)
                                    .font(MacType.caption)
                                    .foregroundStyle(MacColor.textSecondary)
                            }

                            Spacer()

                            if location.geofenceEnforced {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(MacColor.textTertiary)
                        }
                        .padding(.horizontal, MacSpace.md)
                        .padding(.vertical, MacSpace.sm)
                        .background(
                            selectionBackground,
                            in: RoundedRectangle(cornerRadius: MacRadius.medium)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(location.displayName), \(location.city)")
                }
            }
            .padding(MacSpace.md)
        }
        .background(MacColor.cardBackground.opacity(0.45))
    }

    private func locationDetail(_ location: RosterLocation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacSpace.xl) {
                HStack(alignment: .top, spacing: MacSpace.lg) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(MacColor.accent)
                        .frame(width: 54, height: 54)
                        .background(MacColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: MacRadius.large))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.displayName)
                            .font(MacType.sectionHeader)
                            .foregroundStyle(MacColor.textPrimary)
                        Text(location.city)
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    Spacer()

                    Button("Edit") {
                        editor = .edit(location)
                    }
                    .macButton(.bordered, size: .small)

                    Button {
                        locationToDelete = location
                    } label: {
                        Image(systemName: "trash")
                    }
                    .macButton(.bordered, size: .small)
                    .tint(.red)
                    .help("Delete location")
                    .accessibilityLabel("Delete \(location.displayName)")
                }

                MacCard(title: "Attendance Geofence", icon: "location.circle.fill") {
                    VStack(alignment: .leading, spacing: MacSpace.lg) {
                        HStack(spacing: MacSpace.md) {
                            statusBadge(
                                location.hasGeofence ? "Configured" : "Not configured",
                                icon: location.hasGeofence ? "checkmark.circle.fill" : "minus.circle",
                                tint: location.hasGeofence ? .green : MacColor.textTertiary
                            )
                            if location.hasGeofence {
                                statusBadge(
                                    location.geofenceEnforced ? "Strict enforcement" : "Warning only",
                                    icon: location.geofenceEnforced ? "lock.fill" : "exclamationmark.triangle.fill",
                                    tint: location.geofenceEnforced ? .orange : .yellow
                                )
                            }
                        }

                        if let latitude = location.latitude, let longitude = location.longitude {
                            detailRow("Allowed radius", value: "\(Int(location.effectiveGeofenceRadius)) metres")
                            detailRow(
                                "Coordinates",
                                value: String(format: "%.5f, %.5f", latitude, longitude),
                                monospaced: true
                            )

                            Divider()
                                .overlay(MacColor.separator)

                            Label(
                                location.geofenceEnforced
                                    ? "Staff outside this boundary are blocked from starting a shift."
                                    : "Staff outside 250 metres receive a warning and the attempt is recorded.",
                                systemImage: "info.circle"
                            )
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                        } else {
                            Text("No attendance boundary is attached to this location. Shifts can still use it, but staff position is not verified.")
                                .font(MacType.body)
                                .foregroundStyle(MacColor.textSecondary)

                            Button("Configure Geofence") {
                                editor = .edit(location)
                            }
                            .macButton(.bordered, size: .small)
                        }
                    }
                }

                MacCard(title: "Location Details", icon: "building.2") {
                    VStack(spacing: MacSpace.md) {
                        detailRow("Suburb", value: location.suburb)
                        detailRow("State", value: location.state)
                        detailRow("City", value: location.city)
                    }
                }

                Spacer(minLength: MacSpace.xl)
            }
            .padding(MacSpace.xl)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusBadge(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(MacType.captionStrong)
            .foregroundStyle(tint)
            .padding(.horizontal, MacSpace.sm)
            .padding(.vertical, MacSpace.xs)
            .background(tint.opacity(0.11), in: Capsule())
    }

    private func detailRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(MacType.body)
                .foregroundStyle(MacColor.textSecondary)
            Spacer()
            Text(value)
                .font(monospaced ? MacType.mono : MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func save(mode: ManagerLocationsView.EditorMode, location: RosterLocation) async {
        let collides: Bool
        switch mode {
        case .add:
            collides = repo.locations.contains { $0.id == location.id }
        case .edit(let previous):
            collides = repo.locations.contains { $0.id == location.id && $0.id != previous.id }
        }

        guard !collides else {
            toasts.show("\(location.displayName) already exists.", style: .error)
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            switch mode {
            case .add:
                try await repo.addLocation(location)
            case .edit(let previous):
                var updated = repo.locations.filter { $0.id != previous.id }
                updated.append(location)
                try await repo.setLocations(updated)
            }
            selectedLocationID = location.id
            toasts.show(mode.isAdding ? "Location added." : "Location updated.", style: .success)
        } catch {
            toasts.show("Couldn’t save the location. \(error.localizedDescription)", style: .error)
        }
    }

    private func delete(_ location: RosterLocation) async {
        isWorking = true
        defer {
            isWorking = false
            locationToDelete = nil
        }

        do {
            try await repo.setLocations(repo.locations.filter { $0.id != location.id })
            toasts.show("Location deleted.", style: .success)
        } catch {
            toasts.show("Couldn’t delete the location. \(error.localizedDescription)", style: .error)
        }
    }
}

private extension ManagerLocationsView.EditorMode {
    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }
}

// MARK: - Mac Manager Company View

struct MacManagerCompanyView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var companyName = ""
    @State private var abn = ""
    @State private var acn = ""
    @State private var street = ""
    @State private var suburb = ""
    @State private var state = "SA"
    @State private var city = RosterLocation.capital(for: "SA")
    @State private var phoneLocal = ""
    @State private var contactEmail = ""
    @State private var businessNotes = ""
    @State private var loadedFrom: AppSettings?
    @State private var isSaving = false

    init() {}

    private var current: AppSettings {
        let trimmedStreet = street.trimmingCharacters(in: .whitespaces)
        let trimmedSuburb = suburb.trimmingCharacters(in: .whitespaces)
        let localDigits = phoneLocal.filter(\.isNumber)

        return AppSettings(
            companyName: companyName.trimmingCharacters(in: .whitespaces),
            businessAddress: AppSettings.composedAddress(
                street: trimmedStreet,
                suburb: trimmedSuburb,
                state: state
            ),
            businessStreet: trimmedStreet,
            businessSuburb: trimmedSuburb,
            businessState: state,
            businessCity: city.trimmingCharacters(in: .whitespaces),
            contactPhone: localDigits.isEmpty ? "" : "+61 \(RosterFormat.auPhoneLocal(localDigits))",
            contactEmail: contactEmail.trimmingCharacters(in: .whitespaces),
            abn: abn,
            acn: acn,
            businessNotes: businessNotes.trimmingCharacters(in: .whitespaces)
        )
    }

    private var isDirty: Bool {
        current != (loadedFrom ?? repo.appSettings)
    }

    private var canSave: Bool {
        isDirty && !companyName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    private var profileCompletion: Int {
        let values = [
            companyName, abn, street, suburb, city, phoneLocal, contactEmail,
        ]
        let completed = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return Int((Double(completed) / Double(values.count)) * 100)
    }

    var body: some View {
        MacScreen(
            title: "Company Details",
            subtitle: "Business identity, contact details, and payslip information",
            actions: {
                if isDirty && !isSaving {
                    Button("Revert") {
                        restoreLoadedValues()
                    }
                    .help("Discard unsaved changes")
                }

                Button {
                    save()
                } label: {
                    if isSaving {
                        HStack(spacing: MacSpace.sm) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving…")
                        }
                    } else {
                        Label("Save Changes", systemImage: "checkmark")
                    }
                }
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: .command)
                .macButton(.success, size: .small)
            }
        ) {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: MacSpace.xxl) {
                        companySummary
                            .frame(width: 300)

                        editor
                            .frame(minWidth: 600, maxWidth: 760)
                    }

                    VStack(spacing: MacSpace.xl) {
                        companySummary
                        editor
                    }
                }
                .padding(MacSpace.xxl)
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(isSaving)
        .onAppear { loadIfNeeded() }
        .onChange(of: repo.appSettings) { _, _ in loadIfNeeded() }
    }

    private var companySummary: some View {
        VStack(spacing: MacSpace.lg) {
            VStack(alignment: .leading, spacing: MacSpace.xl) {
                HStack(alignment: .top) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: MacRadius.large))

                    Spacer()

                    Label(isDirty ? "Editing" : "Saved", systemImage: isDirty ? "pencil" : "checkmark")
                        .font(MacType.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.15), in: Capsule())
                }

                VStack(alignment: .leading, spacing: MacSpace.sm) {
                    Text(companyName.trimmingCharacters(in: .whitespaces).isEmpty ? "Your Company" : companyName)
                        .font(MacType.pageTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Label(
                        current.businessAddress.isEmpty ? "Add a business address" : current.businessAddress,
                        systemImage: "mappin"
                    )
                    .font(MacType.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: MacSpace.sm) {
                    HStack {
                        Text("Profile completeness")
                        Spacer()
                        Text("\(profileCompletion)%")
                            .fontWeight(.semibold)
                    }
                    .font(MacType.caption)
                    .foregroundStyle(.white.opacity(0.9))

                    ProgressView(value: Double(profileCompletion), total: 100)
                        .tint(.white)
                }
            }
            .padding(MacSpace.xl)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x4F46E5), Color(hex: 0x312E81)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: MacRadius.extraLarge, style: .continuous)
            )
            .shadow(color: MacColor.accent.opacity(0.2), radius: 18, x: 0, y: 8)

            MacCard(title: "Business snapshot", icon: "doc.text.magnifyingglass") {
                VStack(spacing: 0) {
                    summaryRow(icon: "number", title: "ABN", value: abn.isEmpty ? "Not provided" : abn)
                    Divider().padding(.vertical, MacSpace.md)
                    summaryRow(icon: "phone", title: "Phone", value: phoneLocal.isEmpty ? "Not provided" : "+61 \(phoneLocal)")
                    Divider().padding(.vertical, MacSpace.md)
                    summaryRow(icon: "envelope", title: "Email", value: contactEmail.isEmpty ? "Not provided" : contactEmail)
                }
            }

            HStack(alignment: .top, spacing: MacSpace.md) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(MacColor.accent)
                Text("This business profile is used across dashboards and generated payslips.")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
            }
            .padding(MacSpace.lg)
            .background(MacColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: MacRadius.large))
        }
    }

    private var editor: some View {
        VStack(spacing: MacSpace.xl) {
            editorSection(
                number: "01",
                title: "Business identity",
                subtitle: "The legal details shown on company documents.",
                icon: "building.columns.fill"
            ) {
                VStack(spacing: MacSpace.lg) {
                    formField("Company name", prompt: "Company name", text: $companyName)

                    HStack(spacing: MacSpace.md) {
                        formField("ABN", prompt: "XX XXX XXX XXX", text: $abn)
                            .onChange(of: abn) { _, value in
                                let formatted = RosterFormat.abn(value)
                                if formatted != value { abn = formatted }
                            }

                        formField("ACN (optional)", prompt: "XXX XXX XXX", text: $acn)
                            .onChange(of: acn) { _, value in
                                let formatted = RosterFormat.acn(value)
                                if formatted != value { acn = formatted }
                            }
                    }
                }
            }

            editorSection(
                number: "02",
                title: "Business address",
                subtitle: "Your primary registered or trading location.",
                icon: "mappin.and.ellipse"
            ) {
                VStack(spacing: MacSpace.lg) {
                    formField("Street address", prompt: "Street address", text: $street)

                    HStack(spacing: MacSpace.md) {
                        formField("Suburb", prompt: "Suburb", text: $suburb)
                        formField("City", prompt: "City", text: $city)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("State or territory")
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.textSecondary)
                        Picker("State or territory", selection: $state) {
                            ForEach(RosterLocation.states, id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7)
                        .frame(height: 38)
                        .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).stroke(MacColor.cardBorder))
                        .onChange(of: state) { _, newValue in
                            city = RosterLocation.capital(for: newValue)
                        }
                    }
                }
            }

            editorSection(
                number: "03",
                title: "Contact & payroll",
                subtitle: "How staff and payroll documents identify the business.",
                icon: "person.crop.circle.fill"
            ) {
                VStack(spacing: MacSpace.lg) {
                    HStack(spacing: MacSpace.md) {
                        phoneField
                        formField("Email address", prompt: "accounts@example.com", text: $contactEmail)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Additional business information")
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.textSecondary)
                        TextField(
                            "Bank details, payroll notes, or other information",
                            text: $businessNotes,
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .lineLimit(4...8)
                        .padding(11)
                        .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).stroke(MacColor.cardBorder))

                        Text("Optional. Keep sensitive credentials out of this field.")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textTertiary)
                    }
                }
            }
        }
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phone number")
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textSecondary)
            HStack(spacing: MacSpace.sm) {
                Text("+61")
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textSecondary)
                Rectangle()
                    .fill(MacColor.separator)
                    .frame(width: 1, height: 18)
                TextField("412 345 678", text: $phoneLocal)
                    .textFieldStyle(.plain)
                    .textContentType(.telephoneNumber)
                    .onChange(of: phoneLocal) { _, value in
                        let formatted = RosterFormat.auPhoneLocal(value)
                        if formatted != value { phoneLocal = formatted }
                    }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
            .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).stroke(MacColor.cardBorder))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorSection<Content: View>(
        number: String,
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        MacCard {
            VStack(alignment: .leading, spacing: MacSpace.xl) {
                HStack(spacing: MacSpace.md) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MacColor.accent)
                        .frame(width: 34, height: 34)
                        .background(MacColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: MacRadius.medium))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(MacType.sectionHeader)
                            .foregroundStyle(MacColor.textPrimary)
                        Text(subtitle)
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textTertiary)
                    }

                    Spacer()

                    Text(number)
                        .font(MacType.monoStrong)
                        .foregroundStyle(MacColor.textTertiary.opacity(0.65))
                }

                Divider()
                content()
            }
        }
    }

    private func summaryRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                Text(value)
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func formField(
        _ label: String,
        prompt: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textSecondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).stroke(MacColor.cardBorder))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func restoreLoadedValues() {
        guard let loadedFrom else { return }
        companyName = loadedFrom.companyName
        abn = RosterFormat.abn(loadedFrom.abn)
        acn = RosterFormat.acn(loadedFrom.acn)
        street = loadedFrom.businessStreet.isEmpty && loadedFrom.businessSuburb.isEmpty
            ? loadedFrom.businessAddress
            : loadedFrom.businessStreet
        suburb = loadedFrom.businessSuburb
        state = loadedFrom.businessState.isEmpty ? "SA" : loadedFrom.businessState
        city = loadedFrom.businessCity.isEmpty
            ? RosterLocation.capital(for: state)
            : loadedFrom.businessCity
        phoneLocal = RosterFormat.auPhoneLocal(
            loadedFrom.contactPhone.replacingOccurrences(of: "+61", with: "")
        )
        contactEmail = loadedFrom.contactEmail
        businessNotes = loadedFrom.businessNotes
    }

    private func loadIfNeeded() {
        guard loadedFrom == nil || !isDirty else { return }

        let settings = repo.appSettings
        companyName = settings.companyName
        abn = RosterFormat.abn(settings.abn)
        acn = RosterFormat.acn(settings.acn)
        street = settings.businessStreet.isEmpty && settings.businessSuburb.isEmpty
            ? settings.businessAddress
            : settings.businessStreet
        suburb = settings.businessSuburb
        if !settings.businessState.isEmpty {
            state = settings.businessState
        }
        city = settings.businessCity.isEmpty
            ? RosterLocation.capital(for: state)
            : settings.businessCity
        phoneLocal = RosterFormat.auPhoneLocal(
            settings.contactPhone.replacingOccurrences(of: "+61", with: "")
        )
        contactEmail = settings.contactEmail
        businessNotes = settings.businessNotes
        loadedFrom = settings
    }

    private func save() {
        guard canSave else { return }

        isSaving = true
        let settings = current

        Task {
            defer { isSaving = false }
            do {
                try await repo.saveCompanyDetails(settings)
                loadedFrom = settings
                toasts.show("Company details saved.", style: .success)
            } catch {
                toasts.show("Couldn’t save company details. \(error.localizedDescription)", style: .error)
            }
        }
    }
}
#endif
