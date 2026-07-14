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
        var id: String {
            switch self {
            case .payslip(let slip): return "payslip-\(slip.id)"
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

            weekSection
            summarySection
            staffSection
            recentPeriodsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Payroll")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Payroll", icon: "banknote.fill")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    generateDrafts()
                } label: {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "wand.and.sparkles")
                    }
                }
                .disabled(isGenerating)
                .accessibilityLabel("Generate draft payslips for this period")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .payslip(let slip):
                ManagerPayslipDetailSheet(payslipId: slip.id)
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
            }
            .buttonStyle(.plain)
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
                    }
                }
            }
        } header: {
            Text("Staff payslips")
        } footer: {
            if !periodSlips.isEmpty {
                Text("Tap a payslip to review, edit and approve. Swipe left on a draft or under-review payslip to delete. Staff can only see a payslip after you press Submit.")
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
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let created = try await repo.generateDraftPayslips(weekStart: weekMonday)
                toast = created > 0
                    ? ToastMessage(kind: .success, text: "Created \(created) draft payslip\(created == 1 ? "" : "s").")
                    : ToastMessage(kind: .info, text: "Nothing new to generate — existing payslips are never overwritten, and drafts need approved timesheets in the period.")
                if created > 0 { Haptics.success() }
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
            }
            Spacer(minLength: 8)
            PayslipStatusPill(status: slip.status)
        }
        .padding(.vertical, 2)
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
