import SwiftUI

struct HistoryView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AppRouter.self) private var router

    enum Period: String, CaseIterable, Identifiable {
        case week = "This week", month = "This month", year = "This year", all = "All time"
        var id: String { rawValue }
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All statuses"
        case approved = "Approved"
        case pending = "Pending"
        case rejected = "Rejected"
        case absentReported = "Absence reported"
        case absent = "Absent"
        var id: String { rawValue }

        var status: TimesheetStatus? {
            switch self {
            case .all: return nil
            case .approved: return .approved
            case .pending: return .pending
            case .rejected: return .rejected
            case .absentReported: return .absentReported
            case .absent: return .absent
            }
        }
    }

    struct Entry: Identifiable {
        let timesheet: Timesheet
        let shift: Shift?
        var id: String { timesheet.id }
        var dateKey: String {
            if let shift { return shift.date }
            if let submitted = timesheet.submittedAt {
                return RosterCalendar.dayFormatter.string(from: submitted)
            }
            return ""
        }
    }

    @State private var period: Period = .month
    @State private var statusFilter: StatusFilter = .all
    @State private var search = ""

    private var now: Date { Date() }
    private var metrics: HoursMetrics {
        HoursMetrics.compute(timesheets: repo.timesheets, shifts: repo.shifts, now: now)
    }

    private var entries: [Entry] {
        let joined = repo.timesheets.map { ts in
            Entry(timesheet: ts, shift: repo.shifts.first { $0.id == ts.shiftId })
        }
        return joined
            .filter { inPeriod($0.dateKey) }
            .filter { statusFilter.status == nil || $0.timesheet.status == statusFilter.status }
            .filter { matchesSearch($0) }
            .sorted { $0.dateKey > $1.dateKey }
    }

    private var grouped: [(month: String, entries: [Entry])] {
        let groups = Dictionary(grouping: entries) { entry -> String in
            String(entry.dateKey.prefix(7)) // yyyy-MM
        }
        return groups.keys.sorted(by: >).map { key in
            (month: monthLabel(key), entries: groups[key] ?? [])
        }
    }

    var body: some View {
        Group {
            if repo.isLoading {
                TabScroll { ForEach(0..<4, id: \.self) { _ in SkeletonCard() } }
            } else {
                List {
                    summarySection
                    if metrics.pendingHours > 0 {
                        Section {
                            Banner(kind: .warning,
                                   title: "\(RosterFormat.hours(metrics.pendingHours)) awaiting approval",
                                   message: "\(metrics.pendingCount) submission\(metrics.pendingCount == 1 ? "" : "s") pending review.")
                            .plainRow()
                        }
                    }
                    if entries.isEmpty {
                        Section {
                            EmptyStateView(icon: "clock.badge.questionmark",
                                           title: "Nothing here yet",
                                           message: "Timesheets you submit will appear here.")
                            .plainRow()
                        }
                    } else {
                        ForEach(grouped, id: \.month) { group in
                            Section(header: monthHeader(group.month)) {
                                ForEach(group.entries) { entry in
                                    entryRow(entry)
                                }
                            }
                        }
                    }
                    Rectangle().fill(Color.clear).frame(height: 24).plainRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search by location or date")
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "History", icon: "clock.arrow.circlepath")
            }
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        .refreshable { await repo.refreshFromServer() }
    }

    // MARK: Filter menu

    private var filterMenu: some View {
        Menu {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle\(isFiltering ? ".fill" : "")")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel("Filter")
    }

    private var isFiltering: Bool { period != .month || statusFilter != .all }

    // MARK: Summary

    private var summarySection: some View {
        Section {
            let m = metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(value: RosterFormat.decimalHours(m.week), label: "This week", unit: "h", icon: "calendar")
                StatTile(value: RosterFormat.decimalHours(m.month), label: "This month", unit: "h", icon: "calendar.badge.clock")
                StatTile(value: RosterFormat.decimalHours(m.year), label: "This year", unit: "h", icon: "chart.bar")
                StatTile(value: RosterFormat.decimalHours(m.all), label: "All time", unit: "h", icon: "infinity")
            }
            .plainRow()
        }
    }

    private func monthHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(nil)
            Spacer()
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    // MARK: Entry row

    private func entryRow(_ entry: Entry) -> some View {
        let ts = entry.timesheet
        return TimesheetRow(entry: entry, approverName: approverName(ts))
            .plainRow(insets: EdgeInsets(top: 6, leading: Theme.screenPadding, bottom: 6, trailing: Theme.screenPadding))
            .swipeActions(edge: .trailing) {
                if ts.status == .rejected, let shift = entry.shift {
                    Button {
                        router.pendingSubmitShiftId = shift.id
                        router.select(.roster)
                    } label: {
                        Label("Resubmit", systemImage: "arrow.uturn.up")
                    }.tint(Theme.brand)
                }
            }
    }

    // MARK: Helpers

    private func approverName(_ ts: Timesheet) -> String? {
        guard let approvedBy = ts.approvedBy else { return nil }
        return repo.currentUser?.id == approvedBy ? nil : nil // approver profiles aren't loaded for staff
    }

    private func inPeriod(_ dateKey: String) -> Bool {
        guard !dateKey.isEmpty, let date = RosterFormat.parseISODate(dateKey) else { return period == .all }
        let cal = RosterCalendar.calendar
        switch period {
        case .all: return true
        case .week: return RosterCalendar.weekStartKey(date) == RosterCalendar.weekStartKey(now)
        case .month:
            return cal.dateComponents([.year, .month], from: date) == cal.dateComponents([.year, .month], from: now)
        case .year:
            return cal.component(.year, from: date) == cal.component(.year, from: now)
        }
    }

    private func matchesSearch(_ entry: Entry) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let location = entry.shift?.location?.lowercased() ?? ""
        let dateText = RosterFormat.date(entry.dateKey).lowercased()
        return location.contains(q) || dateText.contains(q)
    }

    private func monthLabel(_ yyyymm: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        guard let date = f.date(from: yyyymm) else { return yyyymm }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "MMMM yyyy"
        return out.string(from: date)
    }
}

/// Detailed timesheet row for the history list.
struct TimesheetRow: View {
    let entry: HistoryView.Entry
    var approverName: String?

    private var ts: Timesheet { entry.timesheet }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.dateKey.isEmpty ? "Unknown date" : RosterFormat.date(entry.dateKey))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let location = entry.shift?.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                    StatusPill(ts.status, compact: true)
                }

                if ts.status != .absent && ts.status != .absentReported {
                    HStack(spacing: 16) {
                        if let shift = entry.shift {
                            metric("Rostered", "\(RosterFormat.time(shift.rosteredStart))–\(RosterFormat.time(shift.rosteredEnd))")
                        }
                        if !ts.actualStart.isEmpty {
                            metric("Actual", "\(RosterFormat.time(ts.actualStart))–\(RosterFormat.time(ts.actualEnd))")
                        }
                        metric("Worked", RosterFormat.hours(ts.workedHours))
                    }
                }

                if let notes = ts.staffNotes, !notes.isEmpty {
                    detail(icon: "text.bubble", text: notes, color: Theme.textSecondary)
                }
                if ts.status == .rejected, let reason = ts.rejectedReason, !reason.isEmpty {
                    detail(icon: "xmark.circle", text: "Rejected: \(reason)", color: Theme.error)
                }
                if let managerNotes = ts.managerNotes, !managerNotes.isEmpty {
                    detail(icon: "checkmark.seal", text: managerNotes, color: Theme.accent)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func detail(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(color)
        }
    }
}

/// Convenience for plain, transparent list rows.
extension View {
    func plainRow(insets: EdgeInsets = EdgeInsets(top: 4, leading: Theme.screenPadding, bottom: 4, trailing: Theme.screenPadding)) -> some View {
        self
            .listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
