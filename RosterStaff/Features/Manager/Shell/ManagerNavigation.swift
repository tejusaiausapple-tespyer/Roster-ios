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