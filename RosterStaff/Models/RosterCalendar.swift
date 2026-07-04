import Foundation

/// Centralised calendar/formatter configuration for all roster date math.
///
/// The web app interprets shift wall-clock times in `Australia/Adelaide`
/// (see `ROSTER_TIME_ZONE`) and starts weeks on Monday. We do the same here so
/// "today", week boundaries, and submit gates behave identically on any device.
enum RosterCalendar {
    static let timeZone = TimeZone(identifier: "Australia/Adelaide") ?? .current

    /// Gregorian calendar, Monday-first, pinned to the business timezone.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday
        return cal
    }

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
}
