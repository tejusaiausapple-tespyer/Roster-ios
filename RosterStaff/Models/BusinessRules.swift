import Foundation

/// Direct 1:1 port of the staff-facing business logic in src/lib/utils.ts.
/// Keeping these pure and centralised means the native app enforces exactly the
/// same rules (time gates, week locks, visibility windows) as the web app.
enum BusinessRules {

    // MARK: - Constants

    static let breakMinutesMin = 0
    static let breakMinutesMax = 90
    static let breakMinutesStep = 5

    /// Staff shift listener window: 28 days back, 56 days forward.
    static let shiftWindowDaysBack = 28
    static let shiftWindowDaysForward = 56

    /// Manager timesheet listener window (days back). The manager sees every
    /// staff member's timesheets, so this is scoped to a recent operational
    /// window to keep the live listener fast as the collection grows. Staff
    /// keep their own full 5-year history (a single person's data is small).
    static let managerTimesheetWindowDaysBack = 90

    /// Availability may be set up to 12 weeks ahead.
    static let availabilityMaxWeekOffset = 12
    /// Availability navigation lower bound (2 weeks back, though locked).
    static let availabilityMinWeekOffset = -2

    // MARK: - Shift instants (timezone-aware, mirrors getShiftStartDateTime)

    static func shiftStartDateTime(date: String, time: String) -> Date {
        let dateParts = date.split(separator: "-").compactMap { Int($0) }
        let timeParts = time.split(separator: ":").compactMap { Int($0) }
        guard dateParts.count == 3, timeParts.count >= 2 else { return Date() }
        var comps = DateComponents()
        comps.year = dateParts[0]
        comps.month = dateParts[1]
        comps.day = dateParts[2]
        comps.hour = timeParts[0]
        comps.minute = timeParts[1]
        return RosterCalendar.calendar.date(from: comps) ?? Date()
    }

    /// Mirrors getShiftEndDateTime (adds a day when the shift crosses midnight).
    static func shiftEndDateTime(date: String, start: String, end: String) -> Date {
        var endDate = shiftStartDateTime(date: date, time: end)
        if end <= start {
            endDate = RosterCalendar.addDays(1, to: endDate)
        }
        return endDate
    }

    // MARK: - Worked hours (mirrors calcScheduledHours)

    static func calcWorkedHours(start: String, end: String, breakMinutes: Int) -> Double {
        let s = start.split(separator: ":").compactMap { Int($0) }
        let e = end.split(separator: ":").compactMap { Int($0) }
        guard s.count >= 2, e.count >= 2 else { return 0 }
        let startMins = s[0] * 60 + s[1]
        var endMins = e[0] * 60 + e[1]
        if endMins < startMins { endMins += 24 * 60 } // crosses midnight
        let total = endMins - startMins - breakMinutes
        let hours = Double(max(0, total)) / 60.0
        return (hours * 100).rounded() / 100
    }

    static func clampBreakMinutes(_ value: Int) -> Int {
        min(breakMinutesMax, max(breakMinutesMin, value))
    }

    // MARK: - Visibility windows

    /// Staff shift date range as inclusive `yyyy-MM-dd` keys.
    static func staffShiftDateRange(at now: Date = Date()) -> (start: String, end: String) {
        let start = RosterCalendar.addDays(-shiftWindowDaysBack, to: now)
        let end = RosterCalendar.addDays(shiftWindowDaysForward, to: now)
        return (RosterCalendar.dayFormatter.string(from: start),
                RosterCalendar.dayFormatter.string(from: end))
    }

    /// Oldest timesheet included in the staff history (5 years back).
    static func staffTimesheetCutoff(at now: Date = Date()) -> Date {
        RosterCalendar.addDays(-365 * 5, to: now)
    }

    /// Oldest timesheet the manager listener loads live (recent operational
    /// window). Older records aren't streamed to keep the all-staff listener
    /// fast; widen `managerTimesheetWindowDaysBack` if more history is needed.
    static func managerTimesheetCutoff(at now: Date = Date()) -> Date {
        RosterCalendar.addDays(-managerTimesheetWindowDaysBack, to: now)
    }

    /// Week-offset bounds for the roster picker, aligned with the shift window.
    static func shiftWeekOffsetBounds(at now: Date = Date()) -> (min: Int, max: Int) {
        let range = staffShiftDateRange(at: now)
        let todayMonday = RosterCalendar.weekStart(now)
        guard let startDate = RosterCalendar.dateFromKey(range.start),
              let endDate = RosterCalendar.dateFromKey(range.end) else {
            return (min: -4, max: 8)
        }
        let startMonday = RosterCalendar.weekStart(startDate)
        let endMonday = RosterCalendar.weekStart(endDate)
        let cal = RosterCalendar.calendar
        let minWeeks = cal.dateComponents([.weekOfYear], from: todayMonday, to: startMonday).weekOfYear ?? -4
        let maxWeeks = cal.dateComponents([.weekOfYear], from: todayMonday, to: endMonday).weekOfYear ?? 8
        return (min: minWeeks, max: maxWeeks)
    }

    // MARK: - Week lock (mirrors isRosterWeekLockedForStaff)

    /// The current week and all past weeks are locked for staff availability edits.
    static func isWeekLockedForStaff(weekStartKey: String, at now: Date = Date()) -> Bool {
        weekStartKey <= RosterCalendar.weekStartKey(now)
    }

    /// Mirrors buildRecurringWeekKeys — every unlocked Monday key from `fromMonday`
    /// through the availability horizon.
    static func recurringWeekKeys(fromMonday: Date, at now: Date = Date()) -> [String] {
        var keys: [String] = []
        let horizon = RosterCalendar.addWeeks(availabilityMaxWeekOffset, to: RosterCalendar.weekStart(now))
        var monday = RosterCalendar.weekStart(fromMonday)
        while monday <= horizon {
            keys.append(RosterCalendar.dayFormatter.string(from: monday))
            monday = RosterCalendar.addWeeks(1, to: monday)
        }
        return keys
    }

    // MARK: - Staff shift display status (mirrors getStaffShiftDisplayStatus)

    static func displayStatus(for shift: Shift, timesheet: Timesheet?, at now: Date = Date()) -> StaffShiftDisplayStatus {
        if let ts = timesheet {
            return StaffShiftDisplayStatus(rawValue: ts.status.rawValue) ?? .pending
        }
        if shift.isSubmittable(at: now) { return .awaitingSubmission }
        return .scheduled
    }

    /// Whether a shift currently needs staff action (submit / resubmit / undo).
    /// Mirrors `shiftNeedsStaffAction`.
    static func needsStaffAction(shift: Shift, timesheet: Timesheet?, at now: Date = Date()) -> Bool {
        if timesheet == nil && shift.isSubmittable(at: now) { return true }
        if timesheet?.status == .rejected { return true }
        if let ts = timesheet, ts.isStaffReportedAbsence { return true }
        return false
    }

    /// Whether staff may report an absence for this shift (no ts, or a rejected one).
    /// Mirrors `canStaffReportAbsenceForShift` combined with the time gate.
    static func canReportAbsence(shift: Shift, timesheet: Timesheet?, at now: Date = Date()) -> Bool {
        guard shift.isSubmittable(at: now) else { return false }
        guard let ts = timesheet else { return true }
        return ts.status == .rejected
    }

    /// Whether staff may submit / resubmit hours for this shift.
    static func canSubmitHours(shift: Shift, timesheet: Timesheet?, at now: Date = Date()) -> Bool {
        guard shift.status == .published, shift.isSubmittable(at: now) else { return false }
        guard let ts = timesheet else { return true }
        return ts.status == .rejected
    }

    // MARK: - Manager dashboard shift lifecycle

    /// Real-time lifecycle status of a shift from the manager's perspective.
    /// A timesheet decides the state once one exists; otherwise the schedule
    /// does (scheduled → in progress → pending submission).
    static func managerShiftStatus(shift: Shift, timesheet: Timesheet?, at now: Date = Date()) -> ManagerShiftStatus {
        if let ts = timesheet {
            switch ts.status {
            case .approved: return .approved
            case .pending: return .awaitingApproval
            case .rejected: return .rejected
            case .absentReported, .absent: return .absence
            case .draft: break // not submitted yet — fall through to schedule
            }
        }
        if now < shift.startDateTime { return .scheduled }
        if now < shift.endDateTime { return .inProgress }
        return .pendingSubmission
    }

    // MARK: - Password validation (mirrors validatePassword, required rules only)

    /// Returns an array of unmet *required* password rules (empty == valid).
    static func passwordErrors(_ password: String) -> [String] {
        var errors: [String] = []
        if password.count < 8 { errors.append("At least 8 characters") }
        if password.range(of: "[A-Z]", options: .regularExpression) == nil {
            errors.append("One uppercase letter")
        }
        if password.range(of: "[0-9]", options: .regularExpression) == nil {
            errors.append("One number")
        }
        return errors
    }

    /// Rules shown as a checklist (symbol is recommended, not required).
    struct PasswordRule: Identifiable {
        let id = UUID()
        let label: String
        let isMet: Bool
        let required: Bool
    }

    static func passwordRules(_ password: String) -> [PasswordRule] {
        [
            PasswordRule(label: "At least 8 characters", isMet: password.count >= 8, required: true),
            PasswordRule(label: "One uppercase letter",
                         isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil, required: true),
            PasswordRule(label: "One number",
                         isMet: password.range(of: "[0-9]", options: .regularExpression) != nil, required: true),
            PasswordRule(label: "One symbol (recommended)",
                         isMet: password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil, required: false),
        ]
    }
}
