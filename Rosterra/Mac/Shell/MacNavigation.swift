#if targetEnvironment(macCatalyst)
import SwiftUI
import Observation

enum MacDestination: String, Hashable, CaseIterable, Identifiable {
    // Staff Destinations
    case staffHome = "staff_home"
    case staffRoster = "staff_roster"
    case staffTasks = "staff_tasks"
    case staffAvailability = "staff_availability"
    case staffHistory = "staff_history"
    case staffPayslips = "staff_payslips"

    // Manager Destinations
    case managerDashboard = "manager_dashboard"
    case managerRoster = "manager_roster"
    case managerTimesheets = "manager_timesheets"
    case managerStaff = "manager_staff"
    case managerTasks = "manager_tasks"
    case managerAvailability = "manager_availability"
    case managerReports = "manager_reports"
    case managerTenure = "manager_tenure"
    case managerWage = "manager_wage"
    case managerPayroll = "manager_payroll"
    case managerLocations = "manager_locations"
    case managerCompany = "manager_company"

    // Shared
    case account = "account"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .staffHome: return "Overview"
        case .staffRoster: return "My Roster"
        case .staffTasks: return "My Tasks"
        case .staffAvailability: return "My Availability"
        case .staffHistory: return "Timesheet History"
        case .staffPayslips: return "My Payslips"

        case .managerDashboard: return "Dashboard"
        case .managerRoster: return "Roster"
        case .managerTimesheets: return "Timesheets"
        case .managerStaff: return "Staff Directory"
        case .managerTasks: return "Team Tasks"
        case .managerAvailability: return "Team Availability"
        case .managerReports: return "Reports & Analytics"
        case .managerTenure: return "Tenure & Hours"
        case .managerWage: return "Wage Awards"
        case .managerPayroll: return "Payroll"
        case .managerLocations: return "Work Locations"
        case .managerCompany: return "Company Details"

        case .account: return "Account Settings"
        }
    }

    var icon: String {
        switch self {
        case .staffHome: return "house.fill"
        case .staffRoster: return "calendar"
        case .staffTasks: return "checklist"
        case .staffAvailability: return "calendar.badge.clock"
        case .staffHistory: return "clock.arrow.circlepath"
        case .staffPayslips: return "doc.text.fill"

        case .managerDashboard: return "square.grid.2x2.fill"
        case .managerRoster: return "calendar"
        case .managerTimesheets: return "clipboard.fill"
        case .managerStaff: return "person.2.fill"
        case .managerTasks: return "list.bullet.clipboard.fill"
        case .managerAvailability: return "calendar.badge.clock"
        case .managerReports: return "chart.bar.xaxis"
        case .managerTenure: return "rosette"
        case .managerWage: return "dollarsign.circle.fill"
        case .managerPayroll: return "banknote.fill"
        case .managerLocations: return "mappin.and.ellipse"
        case .managerCompany: return "building.2.fill"

        case .account: return "gearshape.fill"
        }
    }
}

@MainActor
@Observable
final class MacNavigationModel {
    var selectedStaffDestination: MacDestination = .staffHome
    var selectedManagerDestination: MacDestination = .managerDashboard
    var columnVisibility: NavigationSplitViewVisibility = .all

    var pendingSubmitShiftId: String?
    var pendingAbsentShiftId: String?

    var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    init() {}

    func toggleSidebar() {
        columnVisibility = isSidebarVisible ? .detailOnly : .all
    }

    func showSidebar() {
        columnVisibility = .all
    }

    func select(_ destination: MacDestination) {
        if destination == .account {
            selectedStaffDestination = .account
            selectedManagerDestination = .account
        } else if destination.rawValue.starts(with: "staff_") {
            selectedStaffDestination = destination
        } else {
            selectedManagerDestination = destination
        }
    }
}
#endif
