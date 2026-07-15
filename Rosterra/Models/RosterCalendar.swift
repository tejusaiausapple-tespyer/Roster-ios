import Foundation

/// Centralised calendar/formatter configuration for all roster date math.
///
/// The web app interprets shift wall-clock times in `Australia/Adelaide`
/// (see `ROSTER_TIME_ZONE`) and starts weeks on Monday. We do the same here so
/// "today", week boundaries, and submit gates behave identically on any device.
enum RosterCalendar {
    static let timeZone = TimeZone(identifier: "Australia/Adelaide") ?? .current

    /// Gregorian calendar, Monday-first, pinned to the business timezone.
    /// Cached: `Calendar` is a value type with no mutable shared state, and it
    /// is read on virtually every date operation, so rebuilding it per access
    /// was pure waste.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Start of the day (in business TZ) for a given instant.
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(_ date: Date = Date()) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? startOfDay(date)
    }

    /// The `yyyy-MM-dd` key of the Monday of the week containing `date`.
    static func weekStartKey(_ date: Date = Date()) -> String {
        dayFormatter.string(from: weekStart(date))
    }

    /// The seven days (Mon...Sun) of the week containing `date`.
    static func weekDays(for date: Date) -> [Date] {
        let start = weekStart(date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func addWeeks(_ weeks: Int, to date: Date) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: date) ?? date
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func todayKey(_ now: Date = Date()) -> String {
        dayFormatter.string(from: now)
    }

    static func dateFromKey(_ key: String) -> Date? {
        dayFormatter.date(from: key)
    }

    // MARK: - Months (payslip month filter)

    /// "yyyy-MM" key of the month containing `date` (business timezone).
    static func monthKey(_ date: Date = Date()) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return monthKey(year: comps.year ?? 1970, month: comps.month ?? 1)
    }

    static func monthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    /// (year, month) of a "yyyy-MM" key; nil when malformed.
    static func monthKeyComponents(_ key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        return (year, month)
    }

    /// First instant of the month for a "yyyy-MM" key (business timezone).
    static func monthStartDate(_ key: String) -> Date? {
        guard let comps = monthKeyComponents(key) else { return nil }
        return calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1))
    }

    /// Half-open day-key bounds of a month: ("yyyy-MM-01", first day of the
    /// next month). Because `yyyy-MM-dd` sorts lexicographically — and so do
    /// document ids prefixed with it — these bounds drive string range queries.
    static func monthDayKeyBounds(_ key: String) -> (start: String, end: String)? {
        guard let comps = monthKeyComponents(key) else { return nil }
        let next = comps.month == 12 ? (comps.year + 1, 1) : (comps.year, comps.month + 1)
        return ("\(monthKey(year: comps.year, month: comps.month))-01",
                "\(monthKey(year: next.0, month: next.1))-01")
    }

    /// The "yyyy-MM" key `offset` months from `key` (e.g. -1 = previous month).
    static func monthKey(byAdding offset: Int, to key: String) -> String? {
        guard let start = monthStartDate(key),
              let shifted = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
        return monthKey(shifted)
    }
}
