import SwiftUI

enum ManagerTab: String, CaseIterable, Identifiable {
    case dashboard
    case roster
    case timesheets
    case staff
    case tasks
    case availability
    case reports
    case tenure
    case wage
    case payroll
    case account

    var id: String { rawValue }

    /// `true` for the 5 tabs `ManagerMainView` actually tags on the iPhone
    /// `TabView`. The other 6 are only reachable there via Account →
    /// Management overflow. Notification-driven routing consults this so a
    /// push that targets one of the 6 doesn't silently select a tag the
    /// TabView doesn't recognize (see `AppRouter.selectManager`).
    var isPhoneTab: Bool {
        switch self {
        case .dashboard, .roster, .tasks, .timesheets, .account: return true
        case .staff, .availability, .reports, .tenure, .wage, .payroll: return false
        }
    }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .roster: return "Roster"
        case .timesheets: return "Timesheets"
        case .staff: return "Staff"
        case .tasks: return "Tasks"
        case .availability: return "Availability"
        case .reports: return "Reports"
        case .tenure: return "Tenure & Hours"
        case .wage: return "Wage"
        case .payroll: return "Payroll"
        case .account: return "Account"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .roster: return "calendar"
        case .timesheets: return "clipboard"
        case .staff: return "person.2"
        case .tasks: return "list.bullet.clipboard"
        case .availability: return "calendar.badge.clock"
        case .reports: return "chart.bar"
        case .tenure: return "rosette"
        case .wage: return "dollarsign.circle"
        case .payroll: return "banknote"
        case .account: return "gearshape"
        }
    }

    var sidebarSection: ManagerSidebarSection? {
        switch self {
        case .dashboard: return .overview
        case .roster, .tasks, .timesheets, .availability: return .operations
        case .staff, .tenure: return .people
        case .reports, .wage, .payroll: return .finance
        case .account: return nil
        }
    }

    /// ⌘1…⌘0 for destination tabs, numbered in sidebar order; Account uses ⌘,
    /// (Mac Settings convention). The `Go` menu is the only thing that binds
    /// these — see `RosterraApp`.
    var commandShortcut: KeyEquivalent {
        switch self {
        case .dashboard: return "1"
        case .roster: return "2"
        case .tasks: return "3"
        case .timesheets: return "4"
        case .availability: return "5"
        case .staff: return "6"
        case .tenure: return "7"
        case .reports: return "8"
        case .wage: return "9"
        case .payroll: return "0"
        case .account: return ","
        }
    }
}

enum ManagerSidebarSection: Int, CaseIterable, Identifiable {
    case overview
    case operations
    case people
    case finance

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .operations: return "Operations"
        case .people: return "People"
        case .finance: return "Finance"
        }
    }

    var tabs: [ManagerTab] {
        switch self {
        case .overview: return [.dashboard]
        case .operations: return [.roster, .tasks, .timesheets, .availability]
        case .people: return [.staff, .tenure]
        case .finance: return [.reports, .wage, .payroll]
        }
    }
}
