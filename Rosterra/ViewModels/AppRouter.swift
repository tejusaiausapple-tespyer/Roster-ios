import Foundation
import Observation
import SwiftUI

/// Cross-screen navigation state: the selected tab and any pending roster action
/// requested via a deep link / push tap (`?submit=` / `?absent=`).
@MainActor
@Observable
final class AppRouter {
    /// Weak shared handle so `NotificationService` / AppDelegate can route taps
    /// without holding the SwiftUI `@State` instance strongly.
    static weak var shared: AppRouter?

    enum Tab: Int, CaseIterable, Identifiable {
        case home, roster, payslips, availability, account

        var id: Self { self }

        var title: String {
            switch self {
            case .home: return "Home"
            case .roster: return "Roster"
            case .payslips: return "Payslips"
            case .availability: return "Availability"
            case .account: return "Account"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house"
            case .roster: return "calendar"
            case .payslips: return "banknote"
            case .availability: return "calendar.badge.clock"
            case .account: return "person.crop.circle"
            }
        }

        /// ⌘1…⌘4 in sidebar order; Account uses ⌘, (Mac Settings convention).
        /// Bound only by the `Go` menu — see `RosterraApp`.
        var commandShortcut: KeyEquivalent {
            switch self {
            case .home: return "1"
            case .roster: return "2"
            case .payslips: return "3"
            case .availability: return "4"
            case .account: return ","
            }
        }
    }

    var selectedTab: Int = Tab.home.rawValue

    struct PendingClockAction: Equatable {
        enum Kind: String {
            case start
            case end
        }

        let shiftId: String
        let kind: Kind
    }

    /// A Start/End control tapped from the shift Live Activity. Home consumes
    /// it through ClockInCard so location checks and confirmations stay intact.
    var pendingClockAction: PendingClockAction?

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
        // The iPhone TabView only tags 5 of the 11 ManagerTab cases (the
        // rest live behind Account -> Management). Selecting an untagged
        // case there is a silent no-op — the tab bar just keeps whatever
        // was already selected — so fail closed to Account, where the
        // manager can find the real destination themselves.
        if PlatformUI.isPhone && !tab.isPhoneTab {
            selectedManagerTab = .account
            return
        }
        selectedManagerTab = tab
    }

    /// Parse deep links like `surafoster://staff/roster?submit=<id>` or `?absent=<id>`.
    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        if let rawAction = items.first(where: { $0.name == "shiftAction" })?.value,
           let kind = PendingClockAction.Kind(rawValue: rawAction),
           let shiftId = items.first(where: { $0.name == "shiftId" })?.value,
           !shiftId.isEmpty {
            pendingClockAction = PendingClockAction(shiftId: shiftId, kind: kind)
            selectedTab = Tab.home.rawValue
        } else if let submit = items.first(where: { $0.name == "submit" })?.value {
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
        // Payslips has its own staff tab, so this takes precedence over the
        // registry's legacy `/staff/history` URL.
        if event == "payslip-generated" {
            select(.payslips)
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
        if p.contains("payslip") {
            selectedTab = Tab.payslips.rawValue
        } else if p.contains("roster") || p.contains("history") {
            selectedTab = Tab.roster.rawValue
        } else if p.contains("job") {
            // Daily Jobs lives as a card on Home (right under the Start Shift
            // card), not its own tab — route there.
            selectedTab = Tab.home.rawValue
        } else if p.contains("tasks") {
            // Tasks now lives as a card on the Home dashboard.
            selectedTab = Tab.home.rawValue
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
        case "task-completed":
            return .tasks
        case "jobs-all-completed":
            // Daily Jobs overview lives on the Dashboard, not the Tasks tab.
            return .dashboard
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
