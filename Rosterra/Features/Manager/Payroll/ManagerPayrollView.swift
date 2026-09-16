import SwiftUI

/// Manager → Payroll: weekly payroll overview + per-staff payslip workflow.
///
/// Draft payslips are generated automatically (idempotently) for the last
/// completed week; everything after that — review, edit, approve, submit —
/// is a manual manager action. Staff see a payslip only once it is SUBMITTED.
struct ManagerPayrollView: View {
    @Environment(RosterRepository.self) private var repo

    enum ActiveSheet: Identifiable {
        case payslip(Payslip)
        case gaps([PayrollGapItem])
        case bulkPublish([Payslip])
        var id: String {
            switch self {
            case .payslip(let slip): return "payslip-\(slip.id)"
            case .gaps: return "gaps"
            case .bulkPublish: return "bulkPublish"
            }
        }
    }

    /// Selected pay period (Monday key). Defaults to the last completed week —
    /// the one auto-generation targets.
    @State private var weekKey: String = RosterCalendar.dayFormatter.string(
        from: RosterCalendar.addWeeks(-1, to: RosterCalendar.weekStart()))
    @State private var activeSheet: ActiveSheet?
    @State private var toast: ToastMessage?
    @State private var isGenerating = false
    @State private var pendingDeleteSlip: Payslip?
    @State private var confirmDeleteAllDrafts = false
    @State private var pendingPublishSlip: Payslip?
    @State private var regenerationChanges: [PayslipRegenerationChange] = []
    @State private var showRegenerationPrompt = false

    var embedInNavigationStack = true

    var body: some View {
        if embedInNavigationStack {
            NavigationStack { rootContent }
        } else {
            rootContent
        }
    }

    private var weekMonday: Date {
        RosterCalendar.dateFromKey(weekKey) ?? RosterCalendar.weekStart()
    }

    /// Payslips of the selected period (corrections included via periodStart).
    private var periodSlips: [Payslip] {
        repo.payslips.filter { $0.periodStart == weekKey }
            .sorted { $0.staffName < $1.staffName }
    }

    /// Drafts/under-review payslips in the period — the ones "Delete all
    /// drafts" and swipe-to-delete can remove. Approved/submitted/archived
    /// payslips are official records and are never included here.
    private var deletableSlips: [Payslip] {
        periodSlips.filter { $0.status == .draft || $0.status == .underReview }
    }

    /// Draft/under-review/approved payslips — eligible for the "Publish"
    /// fast path (bulk or individual), which jumps straight to Submitted.
    /// Drives whether the bulk-publish entry point shows at all.
    private var publishableSlips: [Payslip] {
        periodSlips.filter { $0.status == .draft || $0.status == .underReview || $0.status == .approved }
    }

    /// Everything the bulk-publish sheet lists: publishable rows (toggleable)
    /// plus already-submitted ones (shown locked, for context). Archived is
    /// excluded — it's superseded by a correction and shouldn't clutter
    /// "this pay run".
    private var publishSheetSlips: [Payslip] {
        periodSlips.filter { $0.status != .archived }
    }

    private var rootContent: some View {
        List {
            // Zero-footprint scroll probe: own section with no spacing +
            // defaultMinListRowHeight below. A loose row would form an
            // implicit section (44pt min row height + section spacing)
            // and push the first card ~100pt down.
            Section {
                TitlePillCollapseReporter()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listSectionSpacing(0)

            // Grouped so the List's ViewBuilder has fewer top-level children
            // to type-check at once — 6 direct statements here (vs. this
            // group's 3) was enough to blow Swift's inference time budget.
            Group {
                weekSection
                summarySection
                publishBannerSection
            }
            staffSection
            recentPeriodsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .contentLane()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Payroll")
        .navigationBarTitleDisplayMode(.inline)
        .screenTitlePill("Payroll", icon: "banknote.fill", fraction: 0)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    generateDrafts()
                } label: {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: periodSlips.isEmpty ? "wand.and.sparkles" : "arrow.clockwise")
                    }
                }
                .disabled(isGenerating)
                .accessibilityLabel(periodSlips.isEmpty ? "Generate draft payslips for this period" : "Refresh pay run from approved timesheets")
                .help(periodSlips.isEmpty ? "Generate draft payslips for this period" : "Refresh pay run from approved timesheets")
            }
            if !deletableSlips.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        confirmDeleteAllDrafts = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundStyle(Theme.error)
                    .accessibilityLabel("Delete all draft payslips for this period")
                    .help("Delete all draft payslips for this period")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .payslip(let slip):
                ManagerPayslipDetailSheet(payslipId: slip.id)
            case .gaps(let gaps):
                PayrollGapsSheet(
                    gaps: gaps,
                    weekLabel: RosterFormat.weekRange(monday: weekMonday),
                    onGenerateAnyway: { checkForTimesheetChanges() }
                )
            case .bulkPublish(let slips):
                PayslipBulkPublishSheet(slips: slips, weekMonday: weekMonday) { count in
                    toast = ToastMessage(kind: .success, text: "Published \(count) payslip\(count == 1 ? "" : "s").")
                }
            }
        }
        .toast($toast)
        // Centered alert (not a bottom action sheet) — nothing is deleted
        // without explicit confirmation.
        .alert(
            "Delete draft payslip?",
            isPresented: Binding(
                get: { pendingDeleteSlip != nil },
                set: { if !$0 { pendingDeleteSlip = nil } }
            ),
            presenting: pendingDeleteSlip
        ) { slip in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteDraft(slip) }
        } message: { slip in
            Text("\(slip.staffName)'s draft payslip for this period will be permanently removed.")
        }
        .alert(
            "Delete all drafts?",
            isPresented: $confirmDeleteAllDrafts
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) { deleteAllDrafts() }
        } message: {
            Text("\(deletableSlips.count) draft payslip\(deletableSlips.count == 1 ? "" : "s") for \(RosterFormat.weekRange(monday: weekMonday)) will be permanently removed. Approved and submitted payslips are kept.")
        }
        .alert(
            "Publish payslip?",
            isPresented: Binding(
                get: { pendingPublishSlip != nil },
                set: { if !$0 { pendingPublishSlip = nil } }
            ),
            presenting: pendingPublishSlip
        ) { slip in
            Button("Cancel", role: .cancel) {}
            Button("Publish") { publishOne(slip) }
        } message: { slip in
            Text("\(slip.staffName) will be able to see this payslip immediately.")
        }
        .alert("Approved timesheet hours changed", isPresented: $showRegenerationPrompt) {
            Button("Cancel", role: .cancel) { regenerationChanges = [] }
            Button("Regenerate payslips") {
                runGeneration(regenerating: regenerationChanges.map(\.payslip))
            }
        } message: {
            Text(regenerationPromptMessage)
        }
    }

    // MARK: Sections

    private var weekSection: some View {
        Section {
            HStack {
                Button {
                    weekKey = RosterCalendar.dayFormatter.string(from: RosterCalendar.addWeeks(-1, to: weekMonday))
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous pay period")
                .help("Previous pay period")
                Spacer()
                VStack(spacing: 2) {
                    Text(RosterFormat.weekRange(monday: weekMonday))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        weekKey = RosterCalendar.dayFormatter.string(
                            from: RosterCalendar.addWeeks(-1, to: RosterCalendar.weekStart()))
                    } label: {
                        Text("Last completed week")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                    }
                }
                Spacer()
                Button {
                    weekKey = RosterCalendar.dayFormatter.string(from: RosterCalendar.addWeeks(1, to: weekMonday))
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next pay period")
                .help("Next pay period")
            }
            .buttonStyle(.plain)
            .pointerHover()
            .foregroundStyle(Theme.brand)
        } header: {
            Text("Pay period")
        }
    }

    private var summarySection: some View {
        let slips = periodSlips
        let totals = slips.map(\.totals)
        let counts = Dictionary(grouping: slips, by: \.status).mapValues(\.count)
        return Section {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatTile(value: "\(counts[.draft] ?? 0)", label: "Drafts", icon: "doc.badge.clock", tint: Theme.warning)
                    StatTile(value: "\((counts[.underReview] ?? 0) + (counts[.approved] ?? 0))", label: "Pending / Approved", icon: "checkmark.seal", tint: Theme.brand)
                    StatTile(value: "\(counts[.submitted] ?? 0)", label: "Submitted", icon: "paperplane", tint: Theme.accent)
                }
                HStack(spacing: 10) {
                    StatTile(value: RosterFormat.money(totals.reduce(0) { $0 + $1.gross }), label: "Gross wages", tint: Theme.brand)
                    StatTile(value: RosterFormat.money(totals.reduce(0) { $0 + $1.tax }), label: "PAYG", tint: Theme.warning)
                }
                HStack(spacing: 10) {
                    StatTile(value: RosterFormat.money(totals.reduce(0) { $0 + $1.superAmount }), label: "Super", tint: Theme.accent)
                    StatTile(value: RosterFormat.money(totals.reduce(0) { $0 + $1.net }), label: "Net pay", tint: Theme.accent)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Overview · \(RosterFormat.weekRange(monday: weekMonday))")
        }
    }

    /// Entry point for bulk publishing — a full-width row rather than a 3rd
    /// toolbar icon (already wand=generate + conditional trash=delete-drafts),
    /// shown only once there's something eligible to publish.
    @ViewBuilder
    private var publishBannerSection: some View {
        if !publishableSlips.isEmpty {
            Section {
                Button {
                    activeSheet = .bulkPublish(publishSheetSlips)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Publish Payslips")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(publishableSlips.count) ready to publish")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var staffSection: some View {
        Section {
            if repo.isLoading {
                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            } else if periodSlips.isEmpty {
                EmptyStateView(
                    icon: "banknote",
                    title: "No payslips for this period",
                    message: "Drafts generate automatically each Monday for the completed week, from approved timesheets and each staff member's wage assignment. You can also generate them now.",
                    actionTitle: "Generate drafts",
                    action: { generateDrafts() }
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(periodSlips) { slip in
                    Button {
                        activeSheet = .payslip(slip)
                    } label: {
                        PayslipRow(slip: slip)
                    }
                    .swipeActions(edge: .trailing) {
                        if slip.status == .draft || slip.status == .underReview {
                            Button(role: .destructive) {
                                pendingDeleteSlip = slip
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if slip.status == .draft || slip.status == .underReview || slip.status == .approved {
                            Button {
                                pendingPublishSlip = slip
                            } label: {
                                Label("Publish", systemImage: "paperplane")
                            }
                            .tint(Theme.accent)
                        }
                    }
                    // Right-click equivalent of the swipe actions above — on
                    // Mac Catalyst (scaled-iPad idiom) a swipe reveal needs a
                    // trackpad, so this is the only path for a mouse-only user.
                    .contextMenu {
                        if slip.status == .draft || slip.status == .underReview || slip.status == .approved {
                            Button {
                                pendingPublishSlip = slip
                            } label: {
                                Label("Publish", systemImage: "paperplane")
                            }
                        }
                        if slip.status == .draft || slip.status == .underReview {
                            Button(role: .destructive) {
                                pendingDeleteSlip = slip
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Staff payslips")
        } footer: {
            if !periodSlips.isEmpty {
                Text(publishableSlips.isEmpty
                     ? "Tap a payslip to review, edit and approve. Staff can only see a payslip after you press Submit."
                     : "Tap a payslip to review, edit and approve. Swipe left to publish or delete one, or use Publish Payslips above for several at once. Staff can only see a payslip after you press Submit.")
            }
        }
    }

    @ViewBuilder
    private var recentPeriodsSection: some View {
        let byPeriod = Dictionary(grouping: repo.payslips.filter { $0.periodStart != weekKey },
                                  by: \.periodStart)
        let periods = byPeriod.keys.sorted(by: >).prefix(6)
        if !periods.isEmpty {
            Section("Recent periods") {
                ForEach(Array(periods), id: \.self) { period in
                    Button {
                        weekKey = period
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RosterFormat.weekRange(monday: RosterCalendar.dateFromKey(period) ?? Date()))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(periodSummary(byPeriod[period] ?? []))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(RosterFormat.money((byPeriod[period] ?? []).reduce(0) { $0 + $1.totals.net }))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.brand)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func periodSummary(_ slips: [Payslip]) -> String {
        let submitted = slips.filter { $0.status == .submitted }.count
        return "\(slips.count) payslip\(slips.count == 1 ? "" : "s") · \(submitted) submitted"
    }

    // MARK: Actions

    private func generateDrafts() {
        guard !isGenerating else { return }
        let gaps = repo.payrollGaps(weekStart: weekMonday)
        if !gaps.isEmpty {
            activeSheet = .gaps(gaps)
            return
        }
        checkForTimesheetChanges()
    }

    private var regenerationPromptMessage: String {
        let rows = regenerationChanges.prefix(8).map {
            "\($0.payslip.staffName): \(String(format: "%.1f", $0.previousHours)) → \(String(format: "%.1f", $0.latestHours)) hours"
        }
        let remainder = regenerationChanges.count > 8
            ? "\n…and \(regenerationChanges.count - 8) more."
            : ""
        return "The latest approved timesheets differ from the current pay run:\n\n"
            + rows.joined(separator: "\n") + remainder
            + "\n\nRegenerating recalculates pay, PAYG and super and replaces manual edits. Approved payslips return to Draft for review. Published payslips are never changed."
    }

    private func checkForTimesheetChanges() {
        guard !isGenerating else { return }
        isGenerating = true
        Task {
            do {
                let changes = try await repo.payslipsNeedingRegeneration(weekStart: weekMonday)
                isGenerating = false
                if changes.isEmpty {
                    runGeneration()
                } else {
                    regenerationChanges = changes
                    showRegenerationPrompt = true
                }
            } catch {
                isGenerating = false
                toast = ToastMessage(kind: .error, text: "Couldn't check approved timesheets. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func runGeneration(regenerating slips: [Payslip] = []) {
        guard !isGenerating else { return }
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let created = try await repo.generateDraftPayslips(weekStart: weekMonday)
                for slip in slips { try await repo.regenerateDraftPayslip(slip) }
                regenerationChanges = []
                if created > 0 || !slips.isEmpty {
                    let createdText = created > 0 ? "Created \(created) new" : ""
                    let separator = created > 0 && !slips.isEmpty ? " and " : ""
                    let refreshedText = slips.isEmpty ? "" : "regenerated \(slips.count)"
                    toast = ToastMessage(kind: .success, text: "\(createdText)\(separator)\(refreshedText) payslip\((created + slips.count) == 1 ? "" : "s") from the latest approved timesheets.")
                    Haptics.success()
                } else {
                    toast = ToastMessage(kind: .info, text: "Pay run is up to date with approved timesheets.")
                }
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't generate drafts. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func deleteDraft(_ slip: Payslip) {
        Task {
            do {
                try await repo.deleteDraftPayslip(slip)
                Haptics.light()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't delete. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func deleteAllDrafts() {
        let slips = deletableSlips
        guard !slips.isEmpty else { return }
        Task {
            do {
                try await repo.deleteDraftPayslips(slips)
                toast = ToastMessage(kind: .success, text: "Deleted \(slips.count) draft payslip\(slips.count == 1 ? "" : "s").")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't delete drafts. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func publishOne(_ slip: Payslip) {
        guard let manager = repo.currentUser else { return }
        guard slip.baseHourlyRate > 0 else {
            toast = ToastMessage(kind: .error, text: "\(slip.staffName)'s payslip has no hourly rate set — fix it before publishing.")
            Haptics.error()
            return
        }
        Task {
            do {
                try await repo.publishPayslips([slip], by: manager)
                toast = ToastMessage(kind: .success, text: "Published — now visible to \(slip.staffName).")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't publish. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}

// MARK: - Row

private struct PayslipRow: View {
    @Environment(RosterRepository.self) private var repo
    let slip: Payslip

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(slip.staffName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text([slip.position, EmploymentType(rawValue: slip.employmentType)?.label]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    Text("Gross \(RosterFormat.money(slip.totals.gross))")
                    Text("Net \(RosterFormat.money(slip.totals.net))")
                    if slip.baseHourlyRate <= 0, slip.status.isEditable {
                        Label("No rate", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.warning)
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
                if let caption = statusCaption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 8)
            PayslipStatusPill(status: slip.status)
        }
        .padding(.vertical, 2)
    }

    /// "Published {date}" once submitted, else "Last edited {date}" once
    /// touched since generation (`updatedAt` stays nil until the first save/
    /// transition) — nil (no caption) for an untouched, freshly-generated draft.
    private var statusCaption: String? {
        if let submittedAt = slip.submittedAt {
            return "Published \(RosterFormat.dateShort(RosterCalendar.dayFormatter.string(from: submittedAt)))"
        }
        if let updatedAt = slip.updatedAt {
            return "Last edited \(RosterFormat.dateShort(RosterCalendar.dayFormatter.string(from: updatedAt)))"
        }
        return nil
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.brand.opacity(0.14))
            .frame(width: 40, height: 40)
            .overlay(
                Text(repo.user(id: slip.staffId)?.initials ?? String(slip.staffName.prefix(2)).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.brand)
            )
    }
}

// MARK: - Status pill (payroll-specific colours)

struct PayslipStatusPill: View {
    let status: PayslipStatus

    private var tint: Color {
        switch status {
        case .draft: return Theme.warning
        case .underReview: return Theme.brand
        case .approved: return Theme.accent
        case .submitted: return Theme.accent
        case .archived: return Theme.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityLabel("Status: \(status.label)")
    }
}

private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.textTertiary.opacity(0.18)).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(height: 12).frame(width: 140)
                SkeletonBlock(height: 10).frame(width: 90)
            }
            Spacer()
        }
    }
}
