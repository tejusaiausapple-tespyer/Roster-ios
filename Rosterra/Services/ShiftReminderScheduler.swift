import Foundation
import UserNotifications

/// Schedules local shift reminders from the staff roster. Fully device-local —
/// no push entitlement needed; alerts still fire after the app is closed.
///
/// Reminder set per shift (all relative to the *rostered* start/end):
///   • 24 h before  — "You have a shift tomorrow at 9:00 AM."
///   • 6 h  before  — "Your shift starts in 6 hours."
///   • 1 h  before  — "Your shift starts in 1 hour."
///   • 30 m before  — "Your shift starts in 30 minutes."
///   • 5 m  before  — "Start Shift is now available." (early check-in window)
///   • 10 m after start — "Don't forget to start your shift." (cancelled on clock-in)
///   • 10 m after end   — "Don't forget to end your shift."  (only while clocked in)
///   • 15 m after end   — "Submit your hours" (when timesheet not yet submitted)
///
/// `sync` is idempotent: it clears every previously scheduled shift reminder
/// and rebuilds from the current roster, so shift edits/cancellations are
/// reflected automatically whenever the Firestore listener fires.
enum ShiftReminderScheduler {
    static let idPrefix = "shift-reminder."
    /// iOS caps pending local notifications at 64; 8 shifts × ≤8 reminders
    /// stays safely under it.
    private static let maxShifts = 8
    /// How long after end we still arm a submit-hours reminder for past shifts.
    private static let submitLookback: TimeInterval = 48 * 60 * 60

    struct Slot {
        let tag: String
        let minutesBeforeStart: Int   // negative = after start
        let title: String
        let body: (Shift) -> String
    }

    private static let slots: [Slot] = [
        Slot(tag: "24h", minutesBeforeStart: 24 * 60, title: "Shift tomorrow") { shift in
            "You have a shift tomorrow at \(RosterFormat.time(shift.rosteredStart))."
        },
        Slot(tag: "6h", minutesBeforeStart: 6 * 60, title: "Shift today") { shift in
            "Your shift starts in 6 hours, at \(RosterFormat.time(shift.rosteredStart))."
        },
        Slot(tag: "1h", minutesBeforeStart: 60, title: "Shift soon") { shift in
            "Your shift starts in 1 hour, at \(RosterFormat.time(shift.rosteredStart))."
        },
        Slot(tag: "30m", minutesBeforeStart: 30, title: "Shift in 30 minutes") { shift in
            "Your shift starts in 30 minutes\(shift.location.map { " at \($0)" } ?? "")."
        },
        Slot(tag: "5m", minutesBeforeStart: 5, title: "Ready to start?") { _ in
            "Your shift starts in 5 minutes — Start Shift is now available."
        },
        Slot(tag: "forgot-start", minutesBeforeStart: -10, title: "Don't forget to start your shift") { shift in
            "Your \(RosterFormat.time(shift.rosteredStart)) shift has begun. Tap Start Shift if you're working."
        },
    ]

    /// Timesheet statuses that mean hours (or absence) are already filed.
    static func isHoursFiled(_ status: TimesheetStatus?) -> Bool {
        switch status {
        case .pending, .approved, .absentReported, .absent: return true
        case .draft, .rejected, .none: return false
        }
    }

    /// Rebuild all reminders from the current roster. Call whenever staff
    /// shifts or timesheets change. `clockedInShiftId` suppresses the
    /// "forgot to start" nag for the shift already in progress and arms the
    /// end-of-shift one. `filedShiftIds` are shifts whose timesheet is already
    /// submitted/approved/absent — those skip submit-hours nags and, once
    /// ended, skip start reminders.
    static func sync(
        shifts: [Shift],
        clockedInShiftId: String?,
        filedShiftIds: Set<String> = [],
        now: Date = Date()
    ) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            let published = shifts.filter { $0.status == .published }

            // Upcoming / in-progress: start reminders (max 8).
            let upcoming = published
                .sorted { ($0.date, $0.rosteredStart) < ($1.date, $1.rosteredStart) }
                .filter { $0.endDateTime > now }
                .prefix(maxShifts)

            for shift in upcoming {
                // Already filed hours for an in-progress/ended window — no start nags.
                if filedShiftIds.contains(shift.id), shift.startDateTime <= now { continue }

                for slot in slots {
                    if slot.tag == "forgot-start" && shift.id == clockedInShiftId { continue }
                    let fireDate = shift.startDateTime.addingTimeInterval(TimeInterval(-slot.minutesBeforeStart * 60))
                    schedule(
                        id: idPrefix + shift.id + "." + slot.tag,
                        title: slot.title,
                        body: slot.body(shift),
                        fireDate: fireDate,
                        shiftId: shift.id,
                        slot: slot.tag,
                        now: now
                    )
                }
                // End-of-shift reminder: only while clocked in.
                if shift.id == clockedInShiftId {
                    schedule(
                        id: idPrefix + shift.id + ".forgot-end",
                        title: "Your shift has ended",
                        body: "Don't forget to end your shift and submit your hours.",
                        fireDate: shift.endDateTime.addingTimeInterval(10 * 60),
                        shiftId: shift.id,
                        slot: "forgot-end",
                        now: now
                    )
                }
            }

            // Submit-hours: any published shift that ended (or ends soon) without a filed timesheet.
            let submitCandidates = published
                .filter { !filedShiftIds.contains($0.id) }
                .filter { $0.endDateTime > now.addingTimeInterval(-submitLookback) }
                .sorted { $0.endDateTime < $1.endDateTime }
                .prefix(maxShifts)

            for shift in submitCandidates {
                let fireDate = shift.endDateTime.addingTimeInterval(15 * 60)
                schedule(
                    id: idPrefix + shift.id + ".submit-hours",
                    title: "Submit your hours",
                    body: "Please submit hours for your \(RosterFormat.time(shift.rosteredStart))–\(RosterFormat.time(shift.rosteredEnd)) shift.",
                    fireDate: fireDate,
                    shiftId: shift.id,
                    slot: "submit-hours",
                    now: now
                )
            }
        }
    }

    /// Cancel the not-started/not-ended nags the moment the state changes.
    static func cancelForgotStart(shiftId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [idPrefix + shiftId + ".forgot-start"])
    }

    static func cancelForgotEnd(shiftId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [idPrefix + shiftId + ".forgot-end"])
    }

    static func cancelSubmitHours(shiftId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [idPrefix + shiftId + ".submit-hours"])
    }

    /// Remove everything (sign-out on a shared device).
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    /// Snapshot for Account UI: pending local shift reminders.
    struct PendingStatus: Equatable {
        var count: Int
        var nextFireDate: Date?
        var nextTitle: String?
    }

    static func pendingStatus() async -> PendingStatus {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .filter { $0.identifier.hasPrefix(idPrefix) }
            .compactMap { req -> (Date, String)? in
                guard let trigger = req.trigger as? UNTimeIntervalNotificationTrigger else { return nil }
                let fire = trigger.nextTriggerDate() ?? Date().addingTimeInterval(trigger.timeInterval)
                return (fire, req.content.title)
            }
            .sorted { $0.0 < $1.0 }
        return PendingStatus(
            count: ours.count,
            nextFireDate: ours.first?.0,
            nextTitle: ours.first?.1
        )
    }

    // MARK: - Internals

    private static func schedule(
        id: String,
        title: String,
        body: String,
        fireDate: Date,
        shiftId: String,
        slot: String,
        now: Date
    ) {
        guard fireDate > now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "shiftId": shiftId,
            "kind": "shift-reminder",
            "slot": slot,
        ]

        // Time-interval trigger keys off the absolute instant, so device
        // timezone can't shift the fire time away from the roster's.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
