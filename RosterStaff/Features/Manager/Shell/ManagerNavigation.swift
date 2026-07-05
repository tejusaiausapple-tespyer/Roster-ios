import Foundation

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
    case account

    var id: String { rawValue }

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
        case .account: return "gear"
        }
    }
}

/// Sidebar grouping for the iPad/macOS split view — mirrors the PWA
/// sidebar's order while giving the ten tabs scannable sections.
enum ManagerSidebarSection: CaseIterable {
    case overview, scheduling, people, operations, settings

    var title: String? {
        switch self {
        case .overview: return nil
        case .scheduling: return "Scheduling"
        case .people: return "People"
        case .operations: return "Operations"
        case .settings: return "Settings"
        }
    }

    var tabs: [ManagerTab] {
        switch self {
        case .overview: return [.dashboard]
        case .scheduling: return [.roster, .timesheets, .availability]
        case .people: return [.staff, .tenure]
        case .operations: return [.tasks, .reports, .wage]
        case .settings: return [.account]
        }
    }
}