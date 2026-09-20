import Foundation

/// Mirrors `DayAvailability` in src/types/index.ts
struct DayAvailability: Codable, Equatable, Hashable {
    var available: Bool
    var allDay: Bool
    var start: String?   // HH:mm
    var end: String?     // HH:mm

    /// Mirrors DEFAULT_DAY_AVAIL: available all day 09:00–17:00.
    static let defaultDay = DayAvailability(available: true, allDay: true, start: "09:00", end: "17:00")

    init(available: Bool, allDay: Bool, start: String? = nil, end: String? = nil) {
        self.available = available
        self.allDay = allDay
        self.start = start
        self.end = end
    }

    init(dict: [String: Any]) {
        self.available = FS.bool(dict, "available", default: true)
        self.allDay = FS.bool(dict, "allDay", default: true)
        self.start = FS.string(dict, "start")
        self.end = FS.string(dict, "end")
    }

    var asDictionary: [String: Any] {
        var d: [String: Any] = ["available": available, "allDay": allDay]
        if let start { d["start"] = start }
        if let end { d["end"] = end }
        return d
    }

    /// Human summary of the stated hours: "All day", "9:00 AM – 5:00 PM",
    /// or "Unavailable".
    var summary: String {
        guard available else { return "Unavailable" }
        if allDay { return "All day" }
        let from = start.map(RosterFormat.time) ?? "—"
        let to = end.map(RosterFormat.time) ?? "—"
        return "\(from) – \(to)"
    }
}

/// The seven weekday keys used across the app, Monday-first.
enum Weekday: String, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: String { rawValue }

    var fullLabel: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var shortLabel: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}

/// Mirrors `UserAvailability` (a fixed 7-day map).
struct UserAvailability: Codable, Equatable {
    var days: [Weekday: DayAvailability]

    init(days: [Weekday: DayAvailability]) {
        self.days = days
    }

    static var defaultAvailability: UserAvailability {
        var map: [Weekday: DayAvailability] = [:]
        for day in Weekday.allCases { map[day] = .defaultDay }
        return UserAvailability(days: map)
    }

    subscript(_ day: Weekday) -> DayAvailability {
        get { days[day] ?? .defaultDay }
        set { days[day] = newValue }
    }

    init(dict: [String: Any]) {
        var map: [Weekday: DayAvailability] = [:]
        for day in Weekday.allCases {
            if let dayDict = dict[day.rawValue] as? [String: Any] {
                map[day] = DayAvailability(dict: dayDict)
            } else {
                map[day] = .defaultDay
            }
        }
        self.days = map
    }

    var asDictionary: [String: Any] {
        var out: [String: Any] = [:]
        for day in Weekday.allCases {
            out[day.rawValue] = self[day].asDictionary
        }
        return out
    }

    // Codable conformance keyed by weekday rawValue.
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var map: [Weekday: DayAvailability] = [:]
        for day in Weekday.allCases {
            if let key = DynamicKey(stringValue: day.rawValue),
               let value = try? container.decode(DayAvailability.self, forKey: key) {
                map[day] = value
            } else {
                map[day] = .defaultDay
            }
        }
        self.days = map
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for day in Weekday.allCases {
            if let key = DynamicKey(stringValue: day.rawValue) {
                try container.encode(self[day], forKey: key)
            }
        }
    }
}

extension AppUser {
    /// The availability that applies to one roster week. A submitted override
    /// wins over the recurring template; accounts without either retain the
    /// product default. Shared by the full manager matrix and compact roster
    /// preview so the two views cannot disagree.
    func resolvedAvailability(forWeekKey weekKey: String) -> UserAvailability {
        weeklyAvailability[weekKey] ?? availability ?? .defaultAvailability
    }

    /// Resolves this staff member's stated availability for a single date,
    /// honouring a per-week override (`weeklyAvailability[weekKey]`) before
    /// falling back to the recurring weekly template. Mirrors the lookup in
    /// `ManagerAvailabilityView.availability(for:)`, generalised to any date
    /// (not just the currently displayed week) so it can be used from the
    /// shift editor's date picker.
    func dayAvailability(on date: Date) -> DayAvailability {
        let weekKey = RosterCalendar.weekStartKey(date)
        let weekday = RosterCalendar.weekday(for: date)
        let template = resolvedAvailability(forWeekKey: weekKey)
        return template[weekday]
    }

    func dayAvailability(onKey dateKey: String) -> DayAvailability {
        guard let date = RosterCalendar.dateFromKey(dateKey) else { return .defaultDay }
        return dayAvailability(on: date)
    }
}

// MARK: - Shift fit

/// How well one staff member fits a *specific proposed shift*.
///
/// "Available" is not a property of a day. Whether someone can work a slot is
/// the combination of three things: what they said they could work, the hours
/// the shift actually runs, and what they are already rostered onto. A day-level
/// yes/no silently green-lights a 6pm shift for someone who only offered 9–5,
/// and hides double-bookings entirely — so this grades the fit instead.
struct StaffShiftFit: Identifiable {

    /// Ordered best-first: `<` means "the better candidate for this shift".
    enum Verdict: Int, Comparable {
        /// Available, stated hours cover the shift, nothing else booked.
        case free
        /// Fits their hours, but they are already rostered elsewhere that day.
        case secondShift
        /// Available that weekday, but the shift runs outside their stated hours.
        case outsideHours
        /// Already rostered on a shift that overlaps this one.
        case doubleBooked
        /// Marked unavailable for that weekday.
        case unavailable

        static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let user: AppUser
    let verdict: Verdict
    let window: DayAvailability
    /// The already-rostered shift this one collides with (`doubleBooked` only).
    let clashingShift: Shift?
    /// Other shifts they already hold that day, overlapping or not.
    let otherShiftsToday: [Shift]

    var id: String { user.id }

    /// True when assigning this shift raises no objection at all.
    var isClean: Bool { verdict <= .secondShift }

    /// Their stated hours, e.g. "All day" or "9:00 AM – 5:00 PM".
    var windowLabel: String { window.summary }

    /// Compact chip label; `detail` carries the full explanation.
    var shortLabel: String {
        switch verdict {
        case .free:         return windowLabel
        case .secondShift:  return "2nd shift"
        case .outsideHours: return "Outside hours"
        case .doubleBooked: return "Clash"
        case .unavailable:  return "Unavailable"
        }
    }

    /// One-line reason — chip tooltip, conflict banner, and save warning.
    var detail: String {
        switch verdict {
        case .free:
            return windowLabel
        case .secondShift:
            let n = otherShiftsToday.count
            return "Already on \(n) shift\(n == 1 ? "" : "s") today · free \(windowLabel)"
        case .outsideHours:
            return "Only free \(windowLabel)"
        case .doubleBooked:
            guard let clash = clashingShift else { return "Already rostered at this time" }
            return "Clashes with \(RosterFormat.time(clash.rosteredStart)) – \(RosterFormat.time(clash.rosteredEnd)) shift"
        case .unavailable:
            return "Marked unavailable this day"
        }
    }
}

/// Who is free on a given day, for the roster grid's coverage pill.
struct DayCoverage {
    /// Available that weekday and not yet rostered — the people you can still use.
    let free: [AppUser]
    /// Available, but already holding at least one shift that day.
    let rostered: [AppUser]
    /// Marked unavailable that weekday.
    let unavailable: [AppUser]
}

/// Resolves staff availability against real shift times and existing bookings.
enum ShiftFit {

    /// Minutes since midnight for an "HH:mm" string.
    private static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// Whether `shift` overlaps the window [start, end) as absolute instants.
    /// Compared on instants rather than clock strings so overnight shifts
    /// (22:00 → 06:00) are handled by the same rule as daytime ones.
    private static func overlaps(_ shift: Shift, start: Date, end: Date) -> Bool {
        shift.startDateTime < end && start < shift.endDateTime
    }

    /// A staff member's existing shifts that could touch `dateKey` — that day's
    /// own shifts plus the previous day's, because an overnight shift started
    /// yesterday still occupies this morning.
    private static func candidateShifts(
        staffId: String,
        dateKey: String,
        in shifts: [Shift],
        excluding excludedId: String?
    ) -> [Shift] {
        let previousKey = RosterCalendar.dateFromKey(dateKey)
            .map { RosterCalendar.dayFormatter.string(from: RosterCalendar.addDays(-1, to: $0)) }
        return shifts.filter { shift in
            shift.staffId == staffId
                && shift.status != .cancelled
                && shift.id != excludedId
                && (shift.date == dateKey || shift.date == previousKey)
        }
    }

    /// Grades one staff member against a proposed shift.
    ///
    /// - Parameter excluding: the shift being edited, so it never clashes with itself.
    static func fit(
        user: AppUser,
        dateKey: String,
        start: String,
        end: String,
        shifts: [Shift],
        excluding excludedId: String? = nil
    ) -> StaffShiftFit {
        let window = user.dayAvailability(onKey: dateKey)

        let booked = candidateShifts(staffId: user.id, dateKey: dateKey, in: shifts, excluding: excludedId)
        let sameDay = booked.filter { $0.date == dateKey }

        let startAt = BusinessRules.shiftStartDateTime(date: dateKey, time: start)
        let endAt = BusinessRules.shiftEndDateTime(date: dateKey, start: start, end: end)
        let clash = booked.first { overlaps($0, start: startAt, end: endAt) }

        // A hard clash outranks everything: even a willing staff member cannot
        // be in two places at once.
        if let clash {
            return StaffShiftFit(user: user, verdict: .doubleBooked, window: window,
                                 clashingShift: clash, otherShiftsToday: sameDay)
        }

        guard window.available else {
            return StaffShiftFit(user: user, verdict: .unavailable, window: window,
                                 clashingShift: nil, otherShiftsToday: sameDay)
        }

        if !window.allDay,
           let windowStart = window.start.flatMap(minutes),
           let windowEnd = window.end.flatMap(minutes),
           let shiftStart = minutes(start),
           var shiftEnd = minutes(end) {
            // An overnight shift runs past the end of the day, so it necessarily
            // runs past any same-day window — which is the correct verdict:
            // "free 9:00 AM – 5:00 PM" does not cover 22:00 → 06:00.
            if shiftEnd <= shiftStart { shiftEnd += 24 * 60 }
            if shiftStart < windowStart || shiftEnd > windowEnd {
                return StaffShiftFit(user: user, verdict: .outsideHours, window: window,
                                     clashingShift: nil, otherShiftsToday: sameDay)
            }
        }

        return StaffShiftFit(user: user,
                             verdict: sameDay.isEmpty ? .free : .secondShift,
                             window: window, clashingShift: nil, otherShiftsToday: sameDay)
    }

    /// Grades every staff member, best candidates first (ties broken by name).
    static func fits(
        staff: [AppUser],
        dateKey: String,
        start: String,
        end: String,
        shifts: [Shift],
        excluding excludedId: String? = nil
    ) -> [StaffShiftFit] {
        staff
            .map { fit(user: $0, dateKey: dateKey, start: start, end: end,
                       shifts: shifts, excluding: excludedId) }
            .sorted {
                $0.verdict == $1.verdict
                    ? $0.user.fullName < $1.user.fullName
                    : $0.verdict < $1.verdict
            }
    }

    /// Day-level split for the roster grid, where no shift times exist yet.
    static func coverage(staff: [AppUser], dateKey: String, shifts: [Shift]) -> DayCoverage {
        let workingIds = Set(
            shifts.filter { $0.date == dateKey && $0.status != .cancelled }.map(\.staffId)
        )
        var free: [AppUser] = [], rostered: [AppUser] = [], unavailable: [AppUser] = []
        for user in staff.sorted(by: { $0.fullName < $1.fullName }) {
            if !user.dayAvailability(onKey: dateKey).available {
                unavailable.append(user)
            } else if workingIds.contains(user.id) {
                rostered.append(user)
            } else {
                free.append(user)
            }
        }
        return DayCoverage(free: free, rostered: rostered, unavailable: unavailable)
    }
}
