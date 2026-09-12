#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacSidebar: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacNavigationModel.self) private var nav

    static let minimumWidth: CGFloat = 248
    static let idealWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 340

    init() {}

    private var isManager: Bool {
        repo.currentUser?.role == .manager
    }

    private var companyName: String {
        let name = repo.companyDetails?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Rosterra" : name
    }

    private var selectedDestination: MacDestination {
        isManager ? nav.selectedManagerDestination : nav.selectedStaffDestination
    }

    private var pendingTimesheetCount: Int {
        repo.shifts.reduce(into: 0) { count, shift in
            if repo.timesheet(forShift: shift.id)?.status == .pending {
                count += 1
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            companyHeader

            ScrollView {
                VStack(alignment: .leading, spacing: MacSpace.lg) {
                    if isManager {
                        managerSections
                    } else {
                        staffSections
                    }
                }
                .padding(.horizontal, MacSpace.sm)
                .padding(.top, MacSpace.sm)
                .padding(.bottom, MacSpace.xl)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            profileFooter
        }
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(MacColor.separator.opacity(0.7))
                .frame(width: 1)
                .ignoresSafeArea()
        }
    }

    private var companyHeader: some View {
        HStack(spacing: MacSpace.md) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(companyName)
                    .font(MacType.bodyStrong)
                    .foregroundStyle(MacColor.textPrimary)
                    .lineLimit(1)
                    .help(companyName)

                Text(isManager ? "MANAGER WORKSPACE" : "STAFF WORKSPACE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(MacColor.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MacSpace.lg)
        .padding(.vertical, MacSpace.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MacColor.separator.opacity(0.65))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var managerSections: some View {
        sidebarSection("Workspace") {
            sidebarRow(.managerDashboard)
            sidebarRow(.managerRoster)
            sidebarRow(
                .managerTimesheets,
                badge: pendingTimesheetCount
            )
            sidebarRow(.managerTasks)
            sidebarRow(.managerAvailability)
        }

        sidebarSection("People") {
            sidebarRow(.managerStaff)
            sidebarRow(.managerTenure)
        }

        sidebarSection("Insights & Pay") {
            sidebarRow(.managerReports)
            sidebarRow(.managerWage)
            sidebarRow(.managerPayroll)
        }

        sidebarSection("Organisation") {
            sidebarRow(.managerLocations)
            sidebarRow(.managerCompany)
        }
    }

    @ViewBuilder
    private var staffSections: some View {
        sidebarSection("Workspace") {
            sidebarRow(.staffHome)
            sidebarRow(.staffRoster)
            sidebarRow(.staffTasks)
            sidebarRow(.staffAvailability)
        }

        sidebarSection("Records") {
            sidebarRow(.staffHistory)
            sidebarRow(.staffPayslips)
        }
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.xs) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(MacColor.textTertiary)
                .padding(.horizontal, MacSpace.sm)
                .padding(.bottom, MacSpace.xxs)

            content()
        }
    }

    @ViewBuilder
    private func sidebarRow(_ destination: MacDestination, badge: Int = 0) -> some View {
        MacSidebarRow(
            destination: destination,
            badge: badge,
            isSelected: selectedDestination == destination
        ) {
            nav.select(destination)
        }
    }

    private var profileFooter: some View {
        Button {
            nav.select(.account)
        } label: {
            HStack(spacing: MacSpace.md) {
                MacAvatar(name: repo.currentUser?.name ?? "User", size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.currentUser?.name ?? "User Account")
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(1)

                    Text(isManager ? "Manager account" : "Staff account")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        selectedDestination == .account
                            ? MacColor.sidebarSelectionForeground
                            : MacColor.textTertiary
                    )
            }
            .padding(.horizontal, MacSpace.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .fill(selectedDestination == .account ? MacColor.sidebarSelection : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MacSpace.sm)
        .padding(.top, MacSpace.sm)
        .padding(.bottom, MacSpace.md)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MacColor.separator.opacity(0.65))
                .frame(height: 1)
        }
    }
}

private struct MacSidebarRow: View {
    let destination: MacDestination
    let badge: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MacSpace.sm) {
                Image(systemName: destination.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 20)

                Text(destination.title)
                    .font(MacType.subheadline)
                    .lineLimit(1)

                Spacer(minLength: MacSpace.xs)

                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(MacType.badge)
                        .foregroundStyle(isSelected ? MacColor.textInverse : MacColor.warning)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 24, minHeight: 20)
                        .background(
                            Capsule()
                                .fill(
                                    isSelected
                                        ? MacColor.sidebarSelectionForeground
                                        : MacColor.warning.opacity(0.13)
                                )
                        )
                        .accessibilityLabel("\(badge) pending")
                }
            }
            .foregroundStyle(
                isSelected ? MacColor.sidebarSelectionForeground : MacColor.textSecondary
            )
            .padding(.horizontal, MacSpace.sm)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: MacRadius.small, style: .continuous)
                    .fill(rowBackground)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(MacColor.accent)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isSelected {
            return MacColor.sidebarSelection
        }
        return isHovered ? MacColor.sidebarHover : .clear
    }
}
#endif
