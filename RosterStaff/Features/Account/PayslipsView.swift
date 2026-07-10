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

        var id: String {
            switch self {
            case .pdf(let slip): return "pdf-\(slip.id)"
            }
        }
    }

    @State private var monthKey = RosterCalendar.monthKey()
    @State private var slips: [Payslip] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var activeSheet: ActiveSheet?
    @State private var isExpanded = false

    private var monthLabel: String {
        RosterCalendar.monthStartDate(monthKey).map { RosterFormat.monthYear($0) } ?? monthKey
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                monthBar
                    .zIndex(1)

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
                .zIndex(0)
            }

            if isExpanded {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }
                    .zIndex(0.5)
            }
        }
        .navigationTitle("Payslips")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: monthKey) { await load() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .pdf(let slip):
                PayslipPDFSheet(slip: slip, isManager: false)
            }
        }
    }

    // MARK: - Month bar

    private var monthBar: some View {
        HStack {
            monthPill
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .topLeading) {
            if isExpanded {
                FloatingMonthYearPicker(selectedMonthKey: $monthKey, isExpanded: $isExpanded)
                    .offset(x: 16, y: 48)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(2)
            }
        }
    }

    private var monthPill: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            Haptics.selection()
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
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .glassCapsule(interactive: true)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change month, currently \(monthLabel)")
        .accessibilityHint(isExpanded ? "Collapses the month picker" : "Expands the month picker")
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

// MARK: - Floating Month/Year picker

private struct FloatingMonthYearPicker: View {
    @Binding var selectedMonthKey: String
    @Binding var isExpanded: Bool

    @State private var tempYear: Int
    @State private var tempMonth: Int
    private let years: [Int]

    private let monthSymbols: [String] = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.monthSymbols
    }()

    init(selectedMonthKey: Binding<String>, isExpanded: Binding<Bool>) {
        self._selectedMonthKey = selectedMonthKey
        self._isExpanded = isExpanded

        let now = RosterCalendar.monthKeyComponents(RosterCalendar.monthKey()) ?? (2026, 1)
        let selected = RosterCalendar.monthKeyComponents(selectedMonthKey.wrappedValue) ?? now
        _tempYear = State(initialValue: selected.year)
        _tempMonth = State(initialValue: selected.month)

        let earliest = min(selected.year, now.year - 5)
        self.years = Array(earliest...now.year).reversed()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Select Period")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(monthSymbols[tempMonth - 1] + " \(tempYear)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.brand)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 0) {
                // Left side: Month vertical wheel selector
                Picker("Month", selection: $tempMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthSymbols[m - 1])
                            .font(.subheadline)
                            .tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                // Right side: Year vertical wheel selector
                Picker("Year", selection: $tempYear) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y))
                            .font(.subheadline)
                            .tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 90)
            }
            .frame(height: 140)

            // Select button
            Button {
                selectedMonthKey = RosterCalendar.monthKey(year: tempYear, month: tempMonth)
                Haptics.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded = false
                }
            } label: {
                Text("Select")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.brand))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("Select \(monthSymbols[tempMonth - 1]) \(tempYear)")
            .accessibilityHint("Selects this month and year and closes the picker")
        }
        .padding(12)
        .frame(width: 280)
        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
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
