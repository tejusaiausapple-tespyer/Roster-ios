import Foundation

/// Display formatting helpers matching the web app's date/time/hours presentation.
enum RosterFormat {

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = RosterCalendar.timeZone
        f.dateFormat = pattern
        return f
    }

    /// Parse a `yyyy-MM-dd` key into a Date (noon in business TZ to avoid DST edges).
    static func parseISODate(_ key: String) -> Date? {
        RosterCalendar.dateFromKey(key)
    }

    // MARK: - Times & dates

    /// "HH:mm" -> "h:mm a" (mirrors formatTime).
    static func time(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return hhmm }
        let h = parts[0]
        let m = parts[1]
        let ampm = h >= 12 ? "PM" : "AM"
        let hour = h % 12 == 0 ? 12 : h % 12
        return "\(hour):\(String(format: "%02d", m)) \(ampm)"
    }

    /// "yyyy-MM-dd" -> "EEE, d MMM yyyy" (mirrors formatDate).
    static func date(_ key: String) -> String {
        guard let d = parseISODate(key) else { return key }
        return formatter("EEE, d MMM yyyy").string(from: d)
    }

    /// "yyyy-MM-dd" -> "d MMM" (mirrors formatDateShort).
    static func dateShort(_ key: String) -> String {
        guard let d = parseISODate(key) else { return key }
        return formatter("d MMM").string(from: d)
    }

    static func weekdayLong(_ key: String) -> String {
        guard let d = parseISODate(key) else { return key }
        return formatter("EEEE").string(from: d)
    }

    static func monthYear(_ date: Date) -> String {
        formatter("MMM yyyy").string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        formatter("d MMM yyyy, h:mm a").string(from: date)
    }

    /// Range label like "5 – 11 May" for a week (Mon...Sun).
    static func weekRange(monday: Date) -> String {
        let sunday = RosterCalendar.addDays(6, to: monday)
        let sameMonth = formatter("MMM").string(from: monday) == formatter("MMM").string(from: sunday)
        if sameMonth {
            return "\(formatter("d").string(from: monday)) – \(formatter("d MMM").string(from: sunday))"
        }
        return "\(formatter("d MMM").string(from: monday)) – \(formatter("d MMM").string(from: sunday))"
    }

    // MARK: - Hours (mirrors formatHours)

    static func hours(_ value: Double) -> String {
        let h = Int(value)
        let m = Int((value - Double(h)) * 60 + 0.5)
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Compact decimal hours, e.g. "7.5" for stat tiles.
    static func decimalHours(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
