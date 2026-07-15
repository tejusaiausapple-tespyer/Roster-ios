import Foundation

/// Approved-hours rollups by period, plus pending/rejected counts.
/// Mirrors the hours summary logic on Home and History (bucketed by *shift date*).
struct HoursMetrics {
    var week: Double = 0
    var month: Double = 0
    var year: Double = 0
    var all: Double = 0
    var pendingHours: Double = 0
    var pendingCount: Int = 0
    var rejectedCount: Int = 0

    static func compute(timesheets: [Timesheet], shifts: [Shift], now: Date = Date()) -> HoursMetrics {
        var metrics = HoursMetrics()
        let cal = RosterCalendar.calendar
        let nowComps = cal.dateComponents([.year, .month], from: now)
        let nowWeekKey = RosterCalendar.weekStartKey(now)

        let shiftDateByShiftId: [String: String] = Dictionary(
            shifts.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first }
        )

        for ts in timesheets {
            switch ts.status {
            case .approved:
                metrics.all += ts.workedHours
                // Bucket by shift date when the shift is loaded; otherwise fall
                // back to the submission time. Staff shifts are only kept for a
                // −28…+56-day window, so older approved timesheets have no
                // matching shift — without the fallback they'd silently drop
                // out of the week/month/year buckets ("this year" undercount).
                // submittedAt is minutes-to-days after the shift, so the
                // approximation is exact for year, near-exact for month/week.
                let date: Date? = shiftDateByShiftId[ts.shiftId]
                    .flatMap { RosterFormat.parseISODate($0) }
                    ?? ts.submittedAt
                guard let date else { continue }
                let comps = cal.dateComponents([.year, .month], from: date)
                if comps.year == nowComps.year {
                    metrics.year += ts.workedHours
                    if comps.month == nowComps.month { metrics.month += ts.workedHours }
                }
                if RosterCalendar.weekStartKey(date) == nowWeekKey {
                    metrics.week += ts.workedHours
                }
            case .pending:
                metrics.pendingHours += ts.workedHours
                metrics.pendingCount += 1
            case .rejected:
                metrics.rejectedCount += 1
            default:
                break
            }
        }
        return metrics
    }
}
