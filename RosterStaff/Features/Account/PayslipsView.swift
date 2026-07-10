import SwiftUI

/// Staff → Account → Payslips, one month at a time. A pill at the top shows
/// the selected month; tapping it opens a month/year picker and the chevrons
/// step a month either way. Data loads via the repository's cache-first
/// month fetch — previously viewed months cost zero Firestore reads and are
/// available offline; pull-to-refresh forces a server round-trip.
/// Visibility is enforced by the payslips Firestore rules (staff can only
/// ever read their own submitted/archived documents).
struct PayslipsView: View {
    @Environment(RosterRepository.self) private var repo

    private enum ActiveSheet: Identifiable {
        case pdf(Payslip)
        case monthPicker

        var id: String {
            switch self {
            case .pdf(let slip): return "pdf-\(slip.id)"
            case .monthPicker: return "month-picker"
            }
        }
    }

    @State private var monthKey = RosterCalendar.monthKey()
    @State private var slips: [Payslip] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var activeSheet: ActiveSheet?

    private var monthLabel: String {
        RosterCalendar.monthStartDate(monthKey).map { RosterFormat.monthYear($0) } ?? monthKey
    }

    var body: some View {
        VStack(spacing: 0) {
            monthBar
            List {
                if loadFailed {
                    Banner(kind: .error,
                           title: "Couldn't load payslips",
                           message: "Check your connection and try again.",
                           actionTitle: "Retry",
                           action: { Task { await load() } })
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } else if isLoading {
                    Section {
                        ForEach(0..<2, id: \.self) { _ in SkeletonRow() }
                    }
                } else if slips.isEmpty {
                    EmptyStateView(
                        icon: "banknote",
                        title: "No payslips for \(monthLabel)",
                        message: "Payslips appear here once your manager finalises and submits them. Pick another month above."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(slips) { slip in
                            Button {
                                activeSheet = .pdf(slip)
                            } label: {
                                row(slip)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable { await load(forceRefresh: true) }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Payslips")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: monthKey) { await load() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .pdf(let slip):
                PayslipPDFSheet(slip: slip, isManager: false)
            case .monthPicker:
                MonthYearPickerSheet(monthKey: monthKey) { picked in
                    monthKey = picked
                }
            }
        }
    }

    // MARK: - Month bar

    private var monthBar: some View {
        HStack(spacing: 12) {
            stepButton(icon: "chevron.left", label: "Previous month", offset: -1)
            Button {
                activeSheet = .monthPicker
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                    Text(monthLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule(style: .continuous).fill(Theme.card))
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change month, currently \(monthLabel)")
            stepButton(icon: "chevron.right", label: "Next month", offset: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stepButton(icon: String, label: String, offset: Int) -> some View {
        Button {
            if let shifted = RosterCalendar.monthKey(byAdding: offset, to: monthKey) {
                monthKey = shifted
                Haptics.selection()
            }
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Data

    private func load(forceRefresh: Bool = false) async {
        // Month switches clear the list (stale rows under a new month label
        // mislead); pull-to-refresh keeps rows visible under its spinner.
        if !forceRefresh {
            slips = []
            isLoading = true
        }
        loadFailed = false
        do {
            slips = try await repo.staffPayslips(monthKey: monthKey, forceRefresh: forceRefresh)
        } catch {
            slips = []
            loadFailed = true
        }
        isLoading = false
    }

    // MARK: - Row

    private func row(_ slip: Payslip) -> some View {
        let totals = slip.totals
        return HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.brand.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(RosterFormat.weekRange(monday: RosterCalendar.dateFromKey(slip.periodStart) ?? Date()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Paid \(RosterFormat.date(slip.payDate))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    Text("Gross \(RosterFormat.money(totals.gross))")
                    Text("Net \(RosterFormat.money(totals.net))")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(RosterFormat.money(totals.net))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
                PayslipStatusPill(status: slip.status)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Month/year picker

/// Lightweight two-wheel month & year picker presented from the month pill.
private struct MonthYearPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (String) -> Void

    @State private var month: Int
    @State private var year: Int
    private let years: [Int]

    init(monthKey: String, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        let now = RosterCalendar.monthKeyComponents(RosterCalendar.monthKey())
            ?? (2026, 1)
        let selected = RosterCalendar.monthKeyComponents(monthKey) ?? now
        _month = State(initialValue: selected.month)
        _year = State(initialValue: selected.year)
        // Recent years only — payslips can't exist before the business did.
        let earliest = min(selected.year, now.year - 5)
        self.years = Array(earliest...now.year).reversed()
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { m in
                        Text(RosterCalendar.calendar.monthSymbols[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
            }
            .padding(.horizontal, 16)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Choose month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        onSelect(RosterCalendar.monthKey(year: year, month: month))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
}

private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.textTertiary.opacity(0.18)).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(height: 12).frame(width: 150)
                SkeletonBlock(height: 10).frame(width: 100)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
