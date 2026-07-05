import Foundation

/// A staff member's live clock-in session for one shift, tracked ON DEVICE.
///
/// WHY LOCAL: the deployed Firestore rules only allow staff to create/update
/// `timesheets/{shiftId}` once `request.time >= shift.submittableAfter`
/// (i.e. after the shift ends), so a real-time clock-in cannot be written to
/// the backend. Instead the session is persisted to UserDefaults (survives
/// relaunch mid-shift) and its recorded times/breaks seed the timesheet in
/// SubmitHoursSheet, which is where the data enters the system of record.
struct ClockSession: Codable, Equatable {
    /// One recorded break. `end == nil` while the break is in progress.
    struct BreakInterval: Codable, Equatable {
        var start: Date
        var end: Date?

        func duration(at now: Date = Date()) -> TimeInterval {
            max(0, (end ?? now).timeIntervalSince(start))
        }
    }

    let shiftId: String
    let staffId: String
    var clockInAt: Date
    var clockOutAt: Date?
    var breaks: [BreakInterval] = []

    var isOnBreak: Bool { breaks.last?.end == nil && !breaks.isEmpty }
    var isActive: Bool { clockOutAt == nil }

    /// Total recorded break time. An in-progress break counts up to `now`.
    func totalBreakSeconds(at now: Date = Date()) -> TimeInterval {
        breaks.reduce(0) { $0 + $1.duration(at: now) }
    }

    /// Break minutes for the timesheet: rounded to the nearest stepper
    /// increment and clamped to the business range, so the value slots
    /// straight into the existing break stepper (0–90, step 5).
    func timesheetBreakMinutes(at now: Date = Date()) -> Int {
        let minutes = totalBreakSeconds(at: now) / 60
        let step = Double(BusinessRules.breakMinutesStep)
        let rounded = Int((minutes / step).rounded() * step)
        return BusinessRules.clampBreakMinutes(rounded)
    }

    /// Elapsed on-the-clock time (excludes breaks).
    func workedSeconds(at now: Date = Date()) -> TimeInterval {
        let end = clockOutAt ?? now
        return max(0, end.timeIntervalSince(clockInAt) - totalBreakSeconds(at: now))
    }

    // MARK: Mutations

    mutating func startBreak(at now: Date = Date()) {
        guard isActive, !isOnBreak else { return }
        breaks.append(BreakInterval(start: now, end: nil))
    }

    mutating func endBreak(at now: Date = Date()) {
        guard isOnBreak, let last = breaks.indices.last else { return }
        breaks[last].end = now
    }

    mutating func clockOut(at now: Date = Date()) {
        endBreak(at: now)
        clockOutAt = now
    }
}
