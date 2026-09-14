#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

struct MacShellView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(MacNavigationModel.self) private var nav
    @Environment(MacToastCenter.self) private var toasts

    init() {}

    private var isManager: Bool {
        repo.currentUser?.role == .manager
    }

    var body: some View {
        @Bindable var nav = nav

        NavigationSplitView(columnVisibility: $nav.columnVisibility) {
            MacSidebar()
                .navigationSplitViewColumnWidth(
                    min: MacSidebar.minimumWidth,
                    ideal: MacSidebar.idealWidth,
                    max: MacSidebar.maximumWidth
                )
                .macObserved(repo: repo, auth: auth, nav: nav, toasts: toasts)
        } detail: {
            detail
                .macObserved(repo: repo, auth: auth, nav: nav, toasts: toasts)
        }
        .navigationSplitViewStyle(.balanced)
        .background(MacColor.windowBackground)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                MacSidebarToggleButton()
            }
        }
        .onAppear {
            MacWindow.configureAllScenes()
        }
    }

    private var detail: some View {
        ZStack {
            if isManager {
                managerDetailView
            } else {
                staffDetailView
            }

            MacToastHost()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Staff Workspace

    @ViewBuilder
    private var staffDetailView: some View {
        switch nav.selectedStaffDestination {
        case .staffHome:
            MacStaffHomeView()
        case .staffRoster:
            MacStaffRosterView()
        case .staffTasks:
            MacStaffTasksView()
        case .staffAvailability:
            MacStaffAvailabilityView()
        case .staffHistory:
            MacStaffHistoryView()
        case .staffPayslips:
            MacStaffPayslipsView()
        case .account:
            MacAccountView()
        default:
            MacStaffHomeView()
        }
    }

    // MARK: - Manager Workspace

    @ViewBuilder
    private var managerDetailView: some View {
        switch nav.selectedManagerDestination {
        case .managerDashboard:
            MacManagerDashboardView()
        case .managerRoster:
            MacManagerRosterView()
        case .managerJobs:
            MacManagerJobsView()
        case .managerTimesheets:
            MacManagerTimesheetsWorkspace()
        case .managerStaff:
            MacManagerStaffView()
        case .managerTasks:
            MacManagerTasksView()
        case .managerAvailability:
            MacManagerAvailabilityView()
        case .managerReports:
            MacManagerReportsView()
        case .managerTenure:
            MacManagerTenureView()
        case .managerWage:
            MacManagerWageView()
        case .managerPayroll:
            MacManagerPayrollView()
        case .managerLocations:
            MacManagerLocationsView()
        case .managerCompany:
            MacManagerCompanyView()
        case .account:
            MacAccountView()
        default:
            MacManagerDashboardView()
        }
    }
}
#endif
