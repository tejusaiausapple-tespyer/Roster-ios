import Foundation
import Observation

/// Cross-screen navigation state: the selected tab and any pending roster action
/// requested via a deep link / push tap (`?submit=` / `?absent=`).
@MainActor
@Observable
final class AppRouter {
    enum Tab: Int, CaseIterable {
        case home, roster, tasks, availability, account
    }

    var selectedTab: Int = Tab.home.rawValue

    /// A shift the user should be taken to in order to submit hours.
    var pendingSubmitShiftId: String?
    /// A shift the user should be taken to in order to report an absence.
    var pendingAbsentShiftId: String?

    func select(_ tab: Tab) {
        selectedTab = tab.rawValue
    }

    /// Parse deep links like `surafoster://staff/roster?submit=<id>` or `?absent=<id>`.
    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        if let submit = items.first(where: { $0.name == "submit" })?.value {
            pendingSubmitShiftId = submit
            selectedTab = Tab.roster.rawValue
        } else if let absent = items.first(where: { $0.name == "absent" })?.value {
            pendingAbsentShiftId = absent
            selectedTab = Tab.roster.rawValue
        } else if components.path.contains("roster") {
            selectedTab = Tab.roster.rawValue
        } else if components.path.contains("tasks") {
            selectedTab = Tab.tasks.rawValue
        } else if components.path.contains("history") {
            selectedTab = Tab.roster.rawValue
        }
    }
}
