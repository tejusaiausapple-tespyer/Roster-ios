import Foundation
@preconcurrency import UserNotifications

/// Schedules local "please check your daily jobs" reminders, purely device-local
/// — no push, no server, no extra Firebase usage. Mirrors `ShiftReminderScheduler`'s
/// shape and lifecycle exactly (see that file's doc comment for the general pattern).
///
/// One reminder per hour of *today's* shift, starting an hour after it begins
/// and stopping `quietPeriodBeforeEnd` before it ends (no point nagging with
/// too little time left to act). Deliberately generic — "Please check your
/// daily jobs.", never naming a specific job.
///
/// `sync` is idempotent and staff-local: it only ever looks at *today's*
/// shifts, and only schedules for a shift that still has an incomplete job.
/// That means completing the last job — or the manager auto-populating a
/// repeat-daily job onto a new shift — naturally reschedules or clears
/// reminders the next time the staff device's `daily_job_assignments`
/// listener fires; no separate "all done" cancellation path is needed.
@MainActor
enum DailyJobReminderScheduler {
    nonisolated static let idPrefix = "daily-job-reminder."
    /// Only today's shifts are relevant (daily jobs aren't visible to staff
    /// past their shift date anyway), so this stays small — plenty of room
    /// alongside ShiftReminderScheduler's own budget under iOS's 64-pending cap.
    private static let maxShifts = 4
    private static let checkInInterval: TimeInterval = 60 * 60
    private static let quietPeriodBeforeEnd: TimeInterval = 15 * 60

    private static var generation = 0

    /// Rebuild every pending daily-jobs reminder from the current shift +
    /// assignment data. Call whenever staff shifts or daily job assignments
    /// change. Reentrant-safe via the same generation-counter guard as
    /// `ShiftReminderScheduler.sync`.
    static func sync(shifts: [Shift], assignments: [DailyJobAssignment], now: Date = Date()) {
        generation += 1
        let myGeneration = generation
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard myGeneration == generation else { return }
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            let todayKey = RosterCalendar.todayKey(now)
            let byShift = Dictionary(grouping: assignments.filter { $0.date == todayKey }, by: \.shiftId)

            let relevantShifts = shifts
                .filter { $0.status == .published && $0.date == todayKey }
                .filter { (byShift[$0.id] ?? []).contains { !$0.completed } }
                .filter { $0.endDateTime > now }
                .sorted { $0.startDateTime < $1.startDateTime }
                .prefix(maxShifts)

            for shift in relevantShifts {
                let latest = shift.endDateTime.addingTimeInterval(-quietPeriodBeforeEnd)
                var offset = checkInInterval
                var index = 0
                while true {
                    let fireDate = shift.startDateTime.addingTimeInterval(offset)
                    guard fireDate <= latest else { break }
                    schedule(
                        id: idPrefix + shift.id + ".\(index)",
                        fireDate: fireDate,
                        shiftId: shift.id,
                        now: now
                    )
                    offset += checkInInterval
                    index += 1
                }
            }
        }
    }

    /// Remove everything (sign-out on a shared device).
    static func cancelAll() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    private static func schedule(id: String, fireDate: Date, shiftId: String, now: Date) {
        guard fireDate > now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Daily Jobs"
        content.body = "Please check your daily jobs."
        content.sound = .default
        content.userInfo = [
            "shiftId": shiftId,
            "kind": "daily-job-reminder",
        ]

        // Time-interval trigger keys off the absolute instant, so device
        // timezone can't shift the fire time away from the shift's.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
