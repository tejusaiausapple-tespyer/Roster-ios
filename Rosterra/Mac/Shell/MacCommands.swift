#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacCommands: Commands {
    var repository: RosterRepository
    var auth: AuthViewModel
    var router: AppRouter
    var navigation: MacNavigationModel
    @Binding var colorSchemeSetting: String

    init(
        repository: RosterRepository,
        auth: AuthViewModel,
        router: AppRouter,
        navigation: MacNavigationModel,
        colorSchemeSetting: Binding<String>
    ) {
        self.repository = repository
        self.auth = auth
        self.router = router
        self.navigation = navigation
        self._colorSchemeSetting = colorSchemeSetting
    }

    var body: some Commands {
        // File Commands
        CommandGroup(replacing: .newItem) {
            Button("New Shift...") {
                NotificationCenter.default.post(name: .macNewShiftRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(repository.currentUser?.role != .manager)

            Button("New Task...") {
                NotificationCenter.default.post(name: .macNewTaskRequested, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(repository.currentUser?.role != .manager)
        }

        // View Commands
        CommandGroup(after: .sidebar) {
            Button(navigation.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                navigation.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh Data") {
                NotificationCenter.default.post(name: .rosterraRefreshRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Menu("Appearance") {
                Button("System") { colorSchemeSetting = "system" }
                Button("Light Mode") { colorSchemeSetting = "light" }
                Button("Dark Mode") { colorSchemeSetting = "dark" }
            }
        }

        // Navigation (Go) Menu
        CommandMenu("Go") {
            if repository.currentUser?.role == .manager {
                Button("Dashboard") { navigation.select(.managerDashboard) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Roster") { navigation.select(.managerRoster) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Timesheets") { navigation.select(.managerTimesheets) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Staff Directory") { navigation.select(.managerStaff) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Team Tasks") { navigation.select(.managerTasks) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Team Availability") { navigation.select(.managerAvailability) }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Reports & Analytics") { navigation.select(.managerReports) }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Payroll") { navigation.select(.managerPayroll) }
                    .keyboardShortcut("8", modifiers: .command)
            } else {
                Button("Overview") { navigation.select(.staffHome) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("My Roster") { navigation.select(.staffRoster) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("My Tasks") { navigation.select(.staffTasks) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("My Availability") { navigation.select(.staffAvailability) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Timesheet History") { navigation.select(.staffHistory) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("My Payslips") { navigation.select(.staffPayslips) }
                    .keyboardShortcut("6", modifiers: .command)
            }

            Divider()

            Button("Account Settings") { navigation.select(.account) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let macNewShiftRequested = Notification.Name("MacNewShiftRequested")
    static let macNewTaskRequested = Notification.Name("MacNewTaskRequested")
}
#endif
