import Foundation
import Observation

/// Cross-screen navigation state: the selected tab and any pending roster action
/// requested via a deep link / push tap (`?submit=` / `?absent=`).
@MainActor
@Observable
final class AppRouter {
    /// Weak shared handle so `NotificationService` / AppDelegate can route taps
    /// without holding the SwiftUI `@State` instance strongly.
    static weak var shared: AppRouter?

    enum Tab: Int, CaseIterable {
        case home, roster, tasks, availability, account
    }

    var selectedTab: Int = Tab.home.rawValue

    /// Mirrors `selectedTab` for the manager shell, which has its own tab set
    /// (`ManagerMainView`/`ManagerTab`) rather than the staff `Tab` enum.
    /// Only one of the two shells is ever on screen at a time (`RootView`
    /// picks by role), so both can be updated unconditionally on every tap.
    var selectedManagerTab: ManagerTab = .dashboard

    /// A shift the user should be taken to in order to submit hours.
    var pendingSubmitShiftId: String?
    /// A shift the user should be taken to in order to report an absence.
    var pendingAbsentShiftId: String?

    func select(_ tab: Tab) {
        selectedTab = tab.rawValue
    }

    func selectManager(_ tab: ManagerTab) {
        selectedManagerTab = tab
    }

    /// Parse deep links like `surafoster://staff/roster?submit=<id>` or `?absent=<id>`.
    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        if let submit = items.first(where: { $0.name == "submit" })?.value {
            openSubmit(shiftId: submit)
        } else if let absent = items.first(where: { $0.name == "absent" })?.value {
            pendingAbsentShiftId = absent
            selectedTab = Tab.roster.rawValue
        } else {
            routeStaffPath(components.path)
        }
    }

    /// Route a local or remote notification tap using `userInfo` keys
    /// (`shiftId`, `timesheetId`, `slot`, `kind`/`event`, `url`).
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        let shiftId = ((userInfo["shiftId"] as? String) ?? (userInfo["timesheetId"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let slot = (userInfo["slot"] as? String)
            ?? Self.slotFromNotificationId(userInfo["identifier"] as? String)
        let event = (userInfo["event"] as? String) ?? (userInfo["kind"] as? String)
        let urlPath = userInfo["url"] as? String

        // Manager-facing events (all resolved server-side via listActiveManagerIds,
        // plus the two synthetic late/overtime sweep events). ManagerMainView is
        // the only shell listening to selectedManagerTab, so this is a no-op
        // when a staff member's device somehow receives one.
        if let managerTab = Self.managerTab(forEvent: event) {
            selectManager(managerTab)
            return
        }

        // Manager decision / roster pushes (and local backups) — work when app was closed.
        if event == "timesheet-rejected" {
            if let shiftId, !shiftId.isEmpty {
                openSubmit(shiftId: shiftId)
            } else {
                select(.roster)
            }
            return
        }
        if event == "timesheet-approved" || event == "roster-published" || event == "shift-changed" {
            select(.roster)
            return
        }
        if event == "shift-cancelled" {
            select(.roster)
            return
        }
        // The registry's url ('/staff/history') would otherwise fall through
        // to routeStaffPath's "history" -> Roster mapping, but PayslipsView
        // lives under Account on iOS, not Roster/History.
        if event == "payslip-generated" {
            select(.account)
            return
        }

        if let shiftId, !shiftId.isEmpty {
            let submitSlots: Set<String> = ["submit-hours", "forgot-end"]
            if let slot, submitSlots.contains(slot) {
                openSubmit(shiftId: shiftId)
                return
            }
            // Start / soon local reminders → Home (Start Shift).
            if event == "shift-reminder" {
                select(.home)
                return
            }
        }

        if let urlPath, !urlPath.isEmpty {
            routeStaffPath(urlPath)
            return
        }

        // Remote hours reminder without a shift id → roster tab.
        if event == "timesheet-reminder" {
            select(.roster)
        }
    }

    func openSubmit(shiftId: String) {
        pendingSubmitShiftId = shiftId
        selectedTab = Tab.roster.rawValue
    }

    private func routeStaffPath(_ path: String) {
        let p = path.lowercased()
        if p.contains("roster") || p.contains("history") {
            selectedTab = Tab.roster.rawValue
        } else if p.contains("tasks") || p.contains("job") {
            selectedTab = Tab.tasks.rawValue
        } else if p.contains("availability") {
            selectedTab = Tab.availability.rawValue
        } else if p.contains("account") {
            selectedTab = Tab.account.rawValue
        } else if p.contains("home") {
            selectedTab = Tab.home.rawValue
        }
    }

    /// Maps a manager-facing notification event to the manager tab it should
    /// open. Mirrors the Worker's `NOTIFICATION_EVENTS` registry urls
    /// (`worker/handlers/notifications.ts`) and `lateOrOvertimeSweep.ts`'s
    /// two synthetic events.
    private static func managerTab(forEvent event: String?) -> ManagerTab? {
        guard let event else { return nil }
        switch event {
        case "timesheet-submitted", "timesheet-absent":
            return .timesheets
        case "shift-started", "shift-ended", "shift-running-late", "shift-overtime-started":
            return .dashboard
        case "task-completed", "jobs-all-completed":
            return .tasks
        case "availability-updated":
            return .availability
        default:
            return nil
        }
    }

    /// Local reminder ids look like `shift-reminder.{shiftId}.{slot}`.
    private static func slotFromNotificationId(_ id: String?) -> String? {
        guard let id, id.hasPrefix(ShiftReminderScheduler.idPrefix) else { return nil }
        return id.split(separator: ".").last.map(String.init)
    }
}
