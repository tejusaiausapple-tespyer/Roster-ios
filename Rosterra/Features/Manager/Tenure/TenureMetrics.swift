import Foundation

/// Pure, testable tenure + hours calculations for the manager Tenure & Hours
/// screen. Mirrors the web app's Tenure Summary logic (src/pages/manager/
/// TenureSummary.tsx): "service tenure" is measured from a staff member's first
/// approved shift, and hours are the sum of approved timesheet hours.
enum TenureMetrics {

    struct StaffTenure: Identifiable, Equatable {
        let id: String
        let name: String
        let initials: String
        let status: UserStatus
        let employmentType: EmploymentType?
        /// Employment start (startDate, else createdAt) — "member since".
        let startDate: Date?
        /// Date of the earliest approved shift/timesheet — service tenure anchor.
        let firstApprovedDate: Date?
        let totalApprovedHours: Double
        /// Whole days from `firstApprovedDate` to `now` (0 when none).
        let tenureDays: Int
        /// Approved hours averaged over the weeks worked since the first shift.
        let avgWeeklyHours: Double
    }

    /// Compute per-staff tenure rows for all `staff`-role users.
    static func compute(users: [AppUser], timesheets: [Timesheet], shifts: [Shift],
                        now: Date = Date()) -> [StaffTenure] {
        let shiftDateByShiftId: [String: String] = Dictionary(
            shifts.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first }
        )
        let approvedByStaff = Dictionary(grouping: timesheets.filter { $0.status == .approved },
                                         by: { $0.staffId })

        return users.filter { $0.role == .staff }.map { user in
            let approved = approvedByStaff[user.id] ?? []
            let totalHours = approved.reduce(0) { $0 + $1.workedHours }

            let approvedDates: [Date] = approved.compactMap { ts in
                shiftDateByShiftId[ts.shiftId].flatMap { RosterFormat.parseISODate($0) } ?? ts.submittedAt
            }
            let firstApproved = approvedDates.min()

            let startDate = user.startDate.flatMap { RosterFormat.parseISODate($0) }
                ?? user.createdAt.flatMap { FS.isoDate(from: $0) }

            let tenureDays = firstApproved.map { max(0, dayCount(from: $0, to: now)) } ?? 0
            let weeks = max(1.0, Double(tenureDays) / 7.0)
            let avgWeekly = totalHours > 0 ? totalHours / weeks : 0

            return StaffTenure(
                id: user.id,
                name: user.fullName,
                initials: user.initials,
                status: user.status,
                employmentType: user.employmentType,
                startDate: startDate,
                firstApprovedDate: firstApproved,
                totalApprovedHours: totalHours,
                tenureDays: tenureDays,
                avgWeeklyHours: avgWeekly
            )
        }
    }

    /// Whole days between two instants in the business timezone.
    static func dayCount(from start: Date, to end: Date) -> Int {
        let cal = RosterCalendar.calendar
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: end)
        return cal.dateComponents([.day], from: s, to: e).day ?? 0
    }

    /// Human tenure label (years/months/weeks/days), mirroring the web app.
    static func tenureString(days: Int) -> String {
        guard days > 0 else { return "—" }
        if days < 7 { return "\(days) day\(days == 1 ? "" : "s")" }
        if days < 30 {
            let w = Int((Double(days) / 7).rounded())
            return "\(w) wk\(w == 1 ? "" : "s")"
        }
        let months = Double(days) / 30.4375
        if months < 12 {
            let m = Int(months)
            let w = Int(((Double(days).truncatingRemainder(dividingBy: 30.4375)) / 7).rounded())
            return w > 0 ? "\(m) mo\(m == 1 ? "" : "s"), \(w) wk\(w == 1 ? "" : "s")"
                         : "\(m) mo\(m == 1 ? "" : "s")"
        }
        let y = Int(months / 12)
        let m = Int((months.truncatingRemainder(dividingBy: 12)).rounded())
        return m > 0 ? "\(y) yr\(y == 1 ? "" : "s"), \(m) mo\(m == 1 ? "" : "s")"
                     : "\(y) yr\(y == 1 ? "" : "s")"
    }

    /// Compact average tenure label for the KPI strip.
    static func friendlyDays(_ days: Double) -> String {
        guard days > 0 else { return "0 days" }
        if days < 30 {
            let d = Int(days.rounded())
            return "\(d) day\(d == 1 ? "" : "s")"
        }
        let months = days / 30.4375
        if months < 12 { return String(format: "%.1f mos", months) }
        return String(format: "%.1f yrs", months / 12)
    }
}
