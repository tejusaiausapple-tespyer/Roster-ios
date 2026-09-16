#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Mac Manager Timesheets View

struct MacManagerTimesheetsView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var filter: Filter = .pending
    @State private var selectedShift: Shift?
    @State private var rejectionReason: String = ""
    @State private var showingRejectionModal: Bool = false

    enum Filter: String, CaseIterable {
        case pending = "Pending Approval"
        case all = "All Timesheets"
    }

    init() {}

    private var timesheetShifts: [Shift] {
        switch filter {
        case .pending:
            return repo.shifts.filter { repo.timesheet(forShift: $0.id)?.status == .pending }
        case .all:
            return repo.shifts.filter { repo.timesheet(forShift: $0.id) != nil }
        }
    }

    var body: some View {
        MacScreen(
            title: "Timesheet Approvals",
            subtitle: "\(timesheetShifts.count) timesheets in view",
            actions: {
                HStack(spacing: MacSpace.md) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    if filter == .pending && !timesheetShifts.isEmpty {
                        MacAsyncButton(variant: .prominent, size: .small) {
                            let result = await repo.approveTimesheets(ids: timesheetShifts.map(\.id))
                            if result.failedIds.isEmpty {
                                toasts.show("\(result.approvedIds.count) timesheets approved", style: .success)
                            } else {
                                toasts.show("\(result.approvedIds.count) approved · \(result.failedIds.count) failed", style: .warning)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Approve All (\(timesheetShifts.count))")
                            }
                        }
                    }
                }
            }
        ) {
            HStack(spacing: 0) {
                // Queue List
                VStack(spacing: 0) {
                    if timesheetShifts.isEmpty {
                        MacEmptyState(
                            title: "No Timesheets",
                            subtitle: "There are no timesheets awaiting manager approval.",
                            icon: "checkmark.seal.fill"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: MacSpace.sm) {
                                ForEach(timesheetShifts) { shift in
                                    let staff = repo.staffMembers.first(where: { $0.id == shift.staffId })
                                    Button {
                                        selectedShift = shift
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(staff?.name ?? "Staff Member")
                                                    .font(MacType.bodyStrong)
                                                    .foregroundStyle(MacColor.textPrimary)

                                                Text("\(shift.date) • \(shift.startTime) - \(shift.endTime)")
                                                    .font(MacType.mono)
                                                    .foregroundStyle(MacColor.textSecondary)
                                            }
                                            Spacer()
                                            MacStatusPill(
                                                shiftStatus: shift.staffDisplayStatus(
                                                    timesheet: repo.timesheet(forShift: shift.id)
                                                )
                                            )
                                        }
                                        .padding(MacSpace.md)
                                        .background(
                                            selectedShift?.id == shift.id ? MacColor.tableRowSelected : MacColor.cardBackground,
                                            in: RoundedRectangle(cornerRadius: MacRadius.medium)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: MacRadius.medium)
                                                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(MacSpace.md)
                        }
                    }
                }
                .frame(width: 360)
                .background(MacColor.cardBackgroundSecondary)
                .overlay(Rectangle().fill(MacColor.separator).frame(width: 1), alignment: .trailing)

                // Detail Inspector
                if let shift = selectedShift {
                    let staff = repo.staffMembers.first(where: { $0.id == shift.staffId })
                    ScrollView {
                        VStack(alignment: .leading, spacing: MacSpace.xl) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(staff?.name ?? "Staff Member")
                                        .font(MacType.pageTitle)
                                        .foregroundStyle(MacColor.textPrimary)
                                    Text("\(shift.position) on \(shift.date)")
                                        .font(MacType.body)
                                        .foregroundStyle(MacColor.textSecondary)
                                }
                                Spacer()
                                MacStatusPill(
                                    shiftStatus: shift.staffDisplayStatus(
                                        timesheet: repo.timesheet(forShift: shift.id)
                                    )
                                )
                            }

                            // Scheduled vs Actual Card
                            HStack(spacing: MacSpace.lg) {
                                MacCard(title: "Scheduled Shift", icon: "calendar") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(shift.startTime) – \(shift.endTime)")
                                            .font(MacType.monoLarge)
                                            .foregroundStyle(MacColor.textPrimary)
                                        Text("\(shift.durationFormatted)")
                                            .font(MacType.caption)
                                            .foregroundStyle(MacColor.textTertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                MacCard(title: "Actual Recorded", icon: "clock.fill") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(shift.actualStartTime ?? shift.startTime) – \(shift.actualEndTime ?? shift.endTime)")
                                            .font(MacType.monoLarge)
                                            .foregroundStyle(MacColor.accent)
                                        Text("Submitted by staff")
                                            .font(MacType.caption)
                                            .foregroundStyle(MacColor.textTertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Staff Notes
                            if let notes = shift.staffNotes, !notes.isEmpty {
                                MacCard(title: "Staff Notes", icon: "note.text") {
                                    Text(notes)
                                        .font(MacType.body)
                                        .foregroundStyle(MacColor.textSecondary)
                                }
                            }

                            // Action Bar
                            if repo.timesheet(forShift: shift.id)?.status == .pending {
                                HStack(spacing: MacSpace.md) {
                                    Button("Reject Timesheet...") {
                                        showingRejectionModal = true
                                    }
                                    .macButton(.destructive, size: .medium)

                                    Spacer()

                                    MacAsyncButton(variant: .prominent, size: .medium) {
                                        do {
                                            try await repo.approveShiftTimesheet(shiftId: shift.id)
                                            toasts.show("Timesheet approved successfully!", style: .success)
                                            selectedShift = nil
                                        } catch {
                                            toasts.show(error.localizedDescription, style: .error)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark")
                                            Text("Approve Hours")
                                        }
                                    }
                                }
                                .padding(.top, MacSpace.lg)
                            }
                        }
                        .padding(MacSpace.xxl)
                    }
                } else {
                    MacEmptyState(
                        title: "Select a Timesheet",
                        subtitle: "Click any submitted timesheet on the left to inspect recorded hours and verify attendance.",
                        icon: "clipboard"
                    )
                }
            }
        }
        .sheet(isPresented: $showingRejectionModal) {
            if let shift = selectedShift {
                VStack(alignment: .leading, spacing: MacSpace.lg) {
                    Text("Reject Timesheet")
                        .font(MacType.sectionHeader)

                    Text("Please explain why this timesheet cannot be approved. The staff member will receive this feedback.")
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textSecondary)

                    TextField("Reason for rejection", text: $rejectionReason)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Cancel") { showingRejectionModal = false }
                            .macButton(.bordered)
                        Spacer()
                        MacAsyncButton(variant: .destructive) {
                            do {
                                try await repo.rejectShiftTimesheet(shiftId: shift.id, reason: rejectionReason)
                                toasts.show("Timesheet rejected.", style: .warning)
                                showingRejectionModal = false
                                selectedShift = nil
                            } catch {
                                toasts.show(error.localizedDescription, style: .error)
                            }
                        } label: {
                            Text("Confirm Rejection")
                        }
                    }
                }
                .padding(MacSpace.xl)
                .frame(width: 440)
                .macObserved(repo: repo, toasts: toasts)
            }
        }
    }
}

// MARK: - Mac Manager Staff Directory View

struct MacManagerStaffView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var searchText = ""
    @State private var showingAddStaff = false
    @State private var selectedStaffID: String?
    @State private var editingStaffID: String?
    @State private var statusFilter: StatusFilter = .all

    init() {}

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all
        case active
        case inactive
        case locked

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private var allStaff: [AppUser] {
        repo.allUsers
            .filter { $0.role == .staff }
            .sorted {
                let lhsPending = $0.deletion?.status == .requested
                let rhsPending = $1.deletion?.status == .requested
                if lhsPending != rhsPending { return lhsPending }
                return $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
    }

    private var filteredStaff: [AppUser] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allStaff.filter { staff in
            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .active: matchesStatus = staff.status == .active
            case .inactive: matchesStatus = staff.status == .inactive
            case .locked: matchesStatus = staff.status == .locked
            }

            let matchesSearch = query.isEmpty
                || staff.fullName.localizedCaseInsensitiveContains(query)
                || staff.email.localizedCaseInsensitiveContains(query)
                || (staff.phone?.localizedCaseInsensitiveContains(query) ?? false)
                || (staff.defaultDepartment?.localizedCaseInsensitiveContains(query) ?? false)

            return matchesStatus && matchesSearch
        }
    }

    private var selectedStaff: AppUser? {
        guard let selectedStaffID else { return filteredStaff.first }
        return repo.allUsers.first { $0.id == selectedStaffID }
    }

    private var activeCount: Int { count(for: .active) }
    private var pendingDeletionCount: Int {
        allStaff.filter { $0.deletion?.status == .requested }.count
    }

    var body: some View {
        MacScreen(
            title: "Staff Directory",
            subtitle: "\(activeCount) active · \(allStaff.count) total",
            actions: {
                Button {
                    showingAddStaff = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.plus")
                        Text("Add staff")
                    }
                }
                .macNeutralPill(size: .small)
            }
        ) {
            GeometryReader { geometry in
                VStack(spacing: MacSpace.md) {
                    controls
                    summaryStrip

                    HStack(spacing: 0) {
                        directoryList
                            .frame(
                                width: min(
                                    420,
                                    max(340, geometry.size.width * 0.36)
                                )
                            )

                        Rectangle()
                            .fill(MacColor.separator)
                            .frame(width: 1)

                        if let selectedStaff {
                            MacStaffDetailWorkspace(user: selectedStaff)
                                .id(selectedStaff.id)
                        } else {
                            MacEmptyState(
                                title: filteredStaff.isEmpty ? "No staff found" : "Select a staff member",
                                subtitle: filteredStaff.isEmpty
                                    ? "Try changing the search or status filter."
                                    : "Choose someone from the directory to see their details.",
                                icon: filteredStaff.isEmpty ? "person.2.slash" : "person.crop.circle"
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .background(
                        MacColor.cardBackground,
                        in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                            .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
                }
                .padding(MacSpace.xl)
            }
        }
        .sheet(isPresented: $showingAddStaff) {
            ManagerAddStaffSheet()
                .frame(width: 640)
                .frame(minHeight: 680)
                .scrollIndicators(.hidden)
        }
        .onAppear {
            maintainSelection()
        }
        .onChange(of: filteredStaff.map(\.id)) { _, _ in
            maintainSelection()
        }
    }

    private var controls: some View {
        HStack(spacing: MacSpace.md) {
            HStack(spacing: 6) {
                ForEach(StatusFilter.allCases) { filter in
                    statusFilterButton(filter)
                }
            }

            Spacer(minLength: MacSpace.lg)

            HStack(spacing: MacSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MacColor.textTertiary)
                TextField("Search name, email, phone or role", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MacType.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MacColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, MacSpace.md)
            .frame(width: 330)
            .frame(minHeight: 40)
            .background(
                MacColor.cardBackground,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    .strokeBorder(MacColor.cardBorder, lineWidth: 1)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: MacSpace.xl) {
            summaryItem(icon: "person.2.fill", value: "\(allStaff.count)", label: "Staff")
            summaryItem(icon: "checkmark.circle.fill", value: "\(activeCount)", label: "Active", tint: MacColor.success)
            summaryItem(icon: "pause.circle.fill", value: "\(count(for: .inactive))", label: "Inactive")
            summaryItem(icon: "lock.fill", value: "\(count(for: .locked))", label: "Locked", tint: MacColor.error)
            if pendingDeletionCount > 0 {
                summaryItem(
                    icon: "trash.circle.fill",
                    value: "\(pendingDeletionCount)",
                    label: "Deletion requests",
                    tint: MacColor.warning
                )
            }
            Spacer()
            Text("\(filteredStaff.count) shown")
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textSecondary)
        }
        .padding(.horizontal, MacSpace.lg)
        .frame(minHeight: 48)
        .macGlassSurface(cornerRadius: MacRadius.large)
    }

    private var directoryList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TEAM")
                    .font(MacType.badge)
                    .foregroundStyle(MacColor.textTertiary)
                Spacer()
                Text("\(filteredStaff.count)")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textSecondary)
            }
            .padding(.horizontal, MacSpace.lg)
            .frame(height: 44)
            .background(MacColor.tableHeaderBackground)

            if filteredStaff.isEmpty {
                MacEmptyState(
                    title: "No staff found",
                    subtitle: "Try another search or status filter.",
                    icon: "person.2.slash"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredStaff) { staff in
                            staffRow(staff)
                        }
                    }
                    .padding(MacSpace.sm)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(MacColor.cardBackgroundSecondary)
    }

    private func staffRow(_ staff: AppUser) -> some View {
        let isSelected = selectedStaffID == staff.id
            || (selectedStaffID == nil && filteredStaff.first?.id == staff.id)
        let tint = statusTint(staff.status)

        return Button {
            selectedStaffID = staff.id
        } label: {
            HStack(spacing: MacSpace.md) {
                MacAvatar(name: staff.fullName, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(staff.fullName)
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)
                            .lineLimit(1)
                        if staff.deletion?.status == .requested {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MacColor.warning)
                                .help("Deletion requested")
                        }
                    }

                    Text(staffSubtitle(staff))
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                        .lineLimit(1)

                    Text(staff.email)
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: MacSpace.sm)

                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(staff.status.rawValue.capitalized)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacColor.textTertiary)
            }
            .padding(.horizontal, MacSpace.md)
            .padding(.vertical, 10)
            .background(
                isSelected ? MacColor.tableRowSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                selectedStaffID = staff.id
            } label: {
                Label("Show details", systemImage: "sidebar.right")
            }
        }
    }

    private func staffInspector(_ staff: AppUser) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacSpace.xl) {
                HStack(alignment: .top, spacing: MacSpace.lg) {
                    MacAvatar(name: staff.fullName, size: 64)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(staff.fullName)
                            .font(MacType.pageTitle)
                            .foregroundStyle(MacColor.textPrimary)
                        Text(staffSubtitle(staff))
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                        MacStatusPill(
                            text: staff.status.rawValue.capitalized,
                            foreground: statusTint(staff.status),
                            background: statusTint(staff.status).opacity(0.12),
                            border: statusTint(staff.status).opacity(0.3),
                            icon: statusIcon(staff.status)
                        )
                    }

                    Spacer()

                    Button {
                        editingStaffID = staff.id
                    } label: {
                        Label("Edit details", systemImage: "pencil")
                    }
                    .macNeutralPill()
                }

                if staff.deletion?.status == .requested {
                    Label(
                        "This staff member requested account deletion. Edit their details to review the request.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.warning)
                    .padding(MacSpace.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        MacColor.warning.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    )
                }

                HStack(spacing: MacSpace.md) {
                    inspectorMetric(
                        title: "Hourly rate",
                        value: displayHourlyRate(for: staff),
                        icon: "dollarsign.circle"
                    )
                    inspectorMetric(
                        title: "Employment",
                        value: staff.employmentType?.label ?? "Not set",
                        icon: "briefcase"
                    )
                    inspectorMetric(
                        title: "Employee ID",
                        value: staff.employeeId?.isEmpty == false ? staff.employeeId! : "Not set",
                        icon: "number"
                    )
                }

                HStack(alignment: .top, spacing: MacSpace.md) {
                    inspectorCard(title: "Personal & contact", icon: "person.crop.circle") {
                        inspectorRow("Email", staff.email)
                        inspectorRow("Phone", staff.phone?.isEmpty == false ? staff.phone! : "Not provided")
                        inspectorRow(
                            "Address",
                            staff.address?.isEmpty == false ? staff.address! : "Not provided"
                        )
                        inspectorRow("Date of birth", formattedDate(staff.dob))
                    }

                    inspectorCard(title: "Employment", icon: "building.2") {
                        inspectorRow("Role", staff.defaultDepartment?.isEmpty == false ? staff.defaultDepartment! : "Not set")
                        inspectorRow("Type", staff.employmentType?.label ?? "Not set")
                        inspectorRow("Employee ID", staff.employeeId?.isEmpty == false ? staff.employeeId! : "Not set")
                        inspectorRow("Status", staff.status.rawValue.capitalized)
                        inspectorRow("Start date", formattedDate(staff.startDate))
                        inspectorRow("Member since", staff.memberSince ?? "—")
                    }
                }

                HStack(alignment: .top, spacing: MacSpace.md) {
                    inspectorCard(title: "Payroll", icon: "dollarsign.circle") {
                        inspectorRow("Hourly rate", displayHourlyRate(for: staff))
                        inspectorRow("Wage setup", wageAssignmentSummary(for: staff))
                        inspectorRow("TFN", TFN.mask(staff.tfn))
                        inspectorRow(
                            "Super",
                            staff.superRate.map { String(format: "%g%%", $0) } ?? "Default"
                        )
                    }

                    inspectorCard(title: "Emergency contact", icon: "cross.case") {
                        inspectorRow(
                            "Name",
                            staff.emergencyContactName?.isEmpty == false
                                ? staff.emergencyContactName!
                                : (staff.emergencyContact?.isEmpty == false ? staff.emergencyContact! : "Not provided")
                        )
                        inspectorRow(
                            "Phone",
                            staff.emergencyContactPhone?.isEmpty == false
                                ? staff.emergencyContactPhone!
                                : "Not provided"
                        )
                        inspectorRow(
                            "Email",
                            staff.emergencyContactEmail?.isEmpty == false
                                ? staff.emergencyContactEmail!
                                : "Not provided"
                        )
                        inspectorRow(
                            "Address",
                            staff.emergencyContactAddress?.isEmpty == false
                                ? staff.emergencyContactAddress!
                                : "Not provided"
                        )
                    }
                }

                inspectorCard(title: "Account", icon: "person.badge.key") {
                    inspectorRow(
                        "Email change",
                        staff.emailChangeRequired ? "Requested" : "Not requested"
                    )
                    inspectorRow(
                        "Profile update",
                        staff.profileUpdateRequired ? "Required" : "Not required"
                    )
                    inspectorRow(
                        "Last sign in",
                        formattedTimestamp(staff.lastLoginAt)
                    )
                }
            }
            .padding(MacSpace.xxl)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.cardBackground)
    }

    private func statusFilterButton(_ filter: StatusFilter) -> some View {
        let isSelected = statusFilter == filter
        return Button {
            statusFilter = filter
        } label: {
            HStack(spacing: 6) {
                Text(filter.title)
                Text("\(count(for: filter))")
                    .font(MacType.badge)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : MacColor.textTertiary)
            }
            .font(MacType.captionStrong)
            .foregroundStyle(isSelected ? Color.white : MacColor.textPrimary)
            .padding(.horizontal, MacSpace.md)
            .frame(minHeight: 36)
            .background(
                isSelected ? MacColor.textPrimary : MacColor.cardBackground,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : MacColor.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func summaryItem(
        icon: String,
        value: String,
        label: String,
        tint: Color = MacColor.textPrimary
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
        }
    }

    private func inspectorMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.sm) {
            Label(title.uppercased(), systemImage: icon)
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
            Text(value)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MacColor.cardBackgroundSecondary,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func inspectorCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            Label(title, systemImage: icon)
                .font(MacType.sectionHeader)
                .foregroundStyle(MacColor.textPrimary)
            content()
        }
        .padding(MacSpace.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            MacColor.cardBackgroundSecondary,
            in: RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(MacType.body)
                .foregroundStyle(MacColor.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func count(for filter: StatusFilter) -> Int {
        switch filter {
        case .all: return allStaff.count
        case .active: return allStaff.filter { $0.status == .active }.count
        case .inactive: return allStaff.filter { $0.status == .inactive }.count
        case .locked: return allStaff.filter { $0.status == .locked }.count
        }
    }

    private func staffSubtitle(_ staff: AppUser) -> String {
        if let department = staff.defaultDepartment, !department.isEmpty {
            return department
        }
        return staff.employmentType?.label ?? "Team member"
    }

    private func statusTint(_ status: UserStatus) -> Color {
        switch status {
        case .active: return MacColor.success
        case .inactive: return MacColor.textTertiary
        case .locked: return MacColor.error
        }
    }

    private func statusIcon(_ status: UserStatus) -> String {
        switch status {
        case .active: return "checkmark.circle.fill"
        case .inactive: return "pause.circle.fill"
        case .locked: return "lock.fill"
        }
    }

    private func formattedDate(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "Not set" }
        return RosterFormat.date(key)
    }

    private func formattedTimestamp(_ value: String?) -> String {
        guard let value, let date = FS.isoDate(from: value) else { return "Not recorded" }
        return RosterFormat.dateFull(date)
    }

    private func displayHourlyRate(for staff: AppUser) -> String {
        let rate = repo.liveHourlyRate(forStaffId: staff.id)
        return rate > 0 ? String(format: "$%.2f", rate) : "Not set"
    }

    private func wageAssignmentSummary(for staff: AppUser) -> String {
        guard let profile = repo.staffWageProfile(for: staff.id) else { return "Not set" }
        var parts: [String] = []
        if let awardID = profile.awardId,
           let award = repo.wageAwards.first(where: { $0.id == awardID }) {
            parts.append(award.code.isEmpty ? award.name : award.code)
        }
        if let level = profile.classificationLevel, !level.isEmpty {
            parts.append("Level \(level)")
        }
        if !profile.earningsLineIds.isEmpty {
            parts.append("\(profile.earningsLineIds.count) pay item\(profile.earningsLineIds.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    private func maintainSelection() {
        if let selectedStaffID,
           filteredStaff.contains(where: { $0.id == selectedStaffID }) {
            return
        }
        selectedStaffID = filteredStaff.first?.id
    }
}

// MARK: - Mac Staff Detail Workspace

private struct MacStaffDetailWorkspace: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    let user: AppUser

    private struct Draft: Equatable {
        var fullName: String
        var phone: String
        var employeeID: String
        var role: String
        var employmentType: EmploymentType
        var startDate: Date?
        var dob: Date?
        var tfn: String
        var emergencyName: String
        var emergencyPhone: String
        var emergencyEmail: String
        var emergencyAddress: String

        init(user: AppUser) {
            fullName = user.fullName
            phone = user.phone ?? ""
            employeeID = user.employeeId ?? ""
            role = user.defaultDepartment ?? ""
            employmentType = user.employmentType ?? .casual
            startDate = user.startDate.flatMap(RosterFormat.parseISODate)
            dob = user.dob.flatMap(RosterFormat.parseISODate)
            tfn = user.tfn.map(TFN.format) ?? ""
            emergencyName = user.emergencyContactName ?? user.emergencyContact ?? ""
            emergencyPhone = user.emergencyContactPhone ?? ""
            emergencyEmail = user.emergencyContactEmail ?? ""
            emergencyAddress = user.emergencyContactAddress ?? ""
        }
    }

    @State private var draft: Draft
    @State private var baseline: Draft
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var emailRequested: Bool
    @State private var showAddressEditor = false
    @State private var addressDraft: String
    @State private var showWageAssignment = false
    @State private var showLockConfirmation = false
    @State private var showDeleteAccount = false
    @State private var managerPassword = ""
    @State private var sensitiveActionError: String?
    @State private var isAccountWorking = false

    init(user: AppUser) {
        self.user = user
        let initial = Draft(user: user)
        _draft = State(initialValue: initial)
        _baseline = State(initialValue: initial)
        _emailRequested = State(initialValue: user.emailChangeRequired)
        _addressDraft = State(initialValue: user.address ?? "")
    }

    private var liveUser: AppUser {
        repo.allUsers.first(where: { $0.id == user.id }) ?? user
    }

    private var hasChanges: Bool { draft != baseline }

    private var roleOptions: [String] {
        var options = ManagerShiftEditorSheet.roleOptions
        if !draft.role.isEmpty, !options.contains(draft.role) { options.insert(draft.role, at: 0) }
        return options
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: MacSpace.xxl) {
                    if liveUser.deletion?.status == .requested {
                        Label(
                            "Account deletion requested by this staff member.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(MacType.captionStrong)
                        .foregroundStyle(MacColor.warning)
                        .padding(MacSpace.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MacColor.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: MacRadius.medium))
                    }

                    ViewThatFits(in: .horizontal) {
                        detailColumns
                            .frame(minWidth: 760)
                        detailStack
                    }

                    Divider()
                    dangerZone
                }
                .padding(MacSpace.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.cardBackground)
        .sheet(isPresented: $showAddressEditor) { addressEditor }
        .sheet(isPresented: $showDeleteAccount) { deletionConfirmation }
        .sheet(isPresented: $showWageAssignment) {
            StaffWageAssignmentSheet(user: liveUser)
                .frame(width: 680, height: 760)
        }
        .alert(liveUser.status == .locked ? "Unlock this user?" : "Lock this user?", isPresented: $showLockConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(liveUser.status == .locked ? "Unlock User" : "Lock User", role: liveUser.status == .locked ? nil : .destructive) {
                setAccountLock(locked: liveUser.status != .locked)
            }
        } message: {
            Text(liveUser.status == .locked
                 ? "\(liveUser.firstName) will be able to sign in again."
                 : "\(liveUser.firstName) will immediately lose access. Payroll and employment records are retained.")
        }
    }

    private var detailColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: MacSpace.xxl) {
                personalSection
                employmentSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.trailing, MacSpace.xxl)

            Rectangle()
                .fill(MacColor.separator)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: MacSpace.xxl) {
                payrollSection
                emergencySection
                accountSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.leading, MacSpace.xxl)
        }
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: MacSpace.xxl) {
            personalSection
            employmentSection
            Divider()
            payrollSection
            emergencySection
            accountSection
        }
    }

    private var header: some View {
        HStack(spacing: MacSpace.lg) {
            MacAvatar(name: liveUser.fullName, size: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(liveUser.fullName)
                    .font(MacType.pageTitle)
                    .foregroundStyle(MacColor.textPrimary)
                HStack(spacing: MacSpace.sm) {
                    Text(liveUser.defaultDepartment?.isEmpty == false
                         ? liveUser.defaultDepartment!
                         : (liveUser.employmentType?.label ?? "Team member"))
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textSecondary)
                    MacStatusPill(
                        text: liveUser.status.rawValue.capitalized,
                        foreground: statusTint,
                        background: statusTint.opacity(0.1),
                        border: statusTint.opacity(0.25),
                        icon: liveUser.status == .locked ? "lock.fill" : "checkmark.circle.fill"
                    )
                }
            }
            Spacer()

            if isEditing {
                Button("Cancel") {
                    draft = baseline
                    isEditing = false
                }
                .macVisibleGlassPill()

                Button(isSaving ? "Saving…" : "Save changes") { saveChanges() }
                    .macVisibleGlassPill(primary: true)
                    .disabled(isSaving || !hasChanges)
            } else {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit details", systemImage: "pencil")
                }
                .macButton(.bordered)
            }
        }
        .padding(.horizontal, MacSpace.xxl)
        .padding(.vertical, MacSpace.xl)
    }

    private var personalSection: some View {
        detailSection("Personal & contact", icon: "person.crop.circle") {
            editableTextRow("Full name", text: $draft.fullName)
            editableTextRow("Phone", text: $draft.phone)
            actionRow("Email", value: liveUser.email, actionTitle: emailRequested ? "Cancel request" : "Ask to change") {
                toggleEmailChangeRequest()
            }
            actionRow(
                "Address",
                value: liveUser.address?.isEmpty == false ? liveUser.address! : "Not provided",
                actionTitle: "Edit address"
            ) {
                addressDraft = liveUser.address ?? ""
                showAddressEditor = true
            }
            editableDateRow("Date of birth", date: $draft.dob)
        }
    }

    private var employmentSection: some View {
        detailSection("Employment", icon: "briefcase") {
            editablePickerRow("Role", selection: $draft.role, options: roleOptions)
            employmentTypeRow
            editableTextRow("Employee ID", text: $draft.employeeID)
            editableDateRow("Start date", date: $draft.startDate)
            displayRow("Status", liveUser.status.rawValue.capitalized)
            displayRow("Member since", liveUser.memberSince ?? "Not recorded")
        }
    }

    private var payrollSection: some View {
        detailSection("Payroll", icon: "dollarsign.circle") {
            displayRow("Hourly rate", hourlyRate)
            actionRow("Wage setup", value: wageSummary, actionTitle: "Manage") {
                showWageAssignment = true
            }
            editableTextRow("TFN", text: Binding(
                get: { draft.tfn },
                set: { draft.tfn = TFN.format($0) }
            ), secureWhenReadOnly: true)
            displayRow("Super", liveUser.superRate.map { String(format: "%g%%", $0) } ?? "Default")
        }
    }

    private var emergencySection: some View {
        detailSection("Emergency contact", icon: "cross.case") {
            editableTextRow("Name", text: $draft.emergencyName)
            editableTextRow("Phone", text: $draft.emergencyPhone)
            editableTextRow("Email", text: $draft.emergencyEmail)
            editableTextRow("Address", text: $draft.emergencyAddress)
            actionRow(
                "Staff update",
                value: liveUser.emergencyDetailsRequired ? "Required on next app open" : "Not required",
                actionTitle: liveUser.emergencyDetailsRequired ? "Cancel requirement" : "Require details"
            ) {
                toggleEmergencyDetailsRequirement()
            }
        }
    }

    private var accountSection: some View {
        detailSection("Account", icon: "person.badge.key") {
            displayRow("Email change", emailRequested ? "Requested" : "Not requested")
            displayRow("Profile update", liveUser.profileUpdateRequired ? "Required" : "Not required")
            displayRow("Role review", liveUser.roleReviewRequired ? "Required on next app open" : "Acknowledged")
            displayRow("Last sign in", formattedTimestamp(liveUser.lastLoginAt))
        }
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Account access")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Text("Lock access immediately or schedule account deletion. Employment and payroll records are retained.")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }

            HStack(spacing: MacSpace.md) {
                Button {
                    showLockConfirmation = true
                } label: {
                    Label(liveUser.status == .locked ? "Unlock user" : "Lock user", systemImage: liveUser.status == .locked ? "lock.open.fill" : "lock.fill")
                }
                .macButton(liveUser.status == .locked ? .bordered : .destructive)

                deletionAction
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var deletionAction: some View {
        switch liveUser.deletion?.status {
        case .approved:
            Button("Cancel deletion & reinstate") { cancelDeletion() }
                .macButton(.bordered)
        case .authPurged:
            Label("Sign-in removed · records retained", systemImage: "checkmark.shield.fill")
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.textTertiary)
        default:
            Button {
                managerPassword = ""
                sensitiveActionError = nil
                showDeleteAccount = true
            } label: {
                Label(liveUser.deletion?.status == .requested ? "Approve account deletion…" : "Delete account…", systemImage: "trash.fill")
            }
            .macButton(.destructive)
        }
    }

    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            Label(title, systemImage: icon)
                .font(MacType.sectionHeader)
                .foregroundStyle(MacColor.textPrimary)
            content()
        }
    }

    private func displayRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 104, alignment: .leading)
            Text(value.isEmpty ? "Not provided" : value)
                .font(MacType.body)
                .foregroundStyle(MacColor.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private func editableTextRow(_ label: String, text: Binding<String>, secureWhenReadOnly: Bool = false) -> some View {
        HStack(spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 104, alignment: .leading)
            if isEditing {
                TextField(label, text: text)
                    .textFieldStyle(.plain)
                    .font(MacType.body)
                    .padding(.horizontal, MacSpace.md)
                    .frame(height: 36)
                    .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.small))
                    .overlay(RoundedRectangle(cornerRadius: MacRadius.small).strokeBorder(MacColor.cardBorder, lineWidth: 1))
            } else {
                Text(secureWhenReadOnly ? TFN.mask(liveUser.tfn) : (text.wrappedValue.isEmpty ? "Not provided" : text.wrappedValue))
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    private func editablePickerRow(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 104, alignment: .leading)
            if isEditing {
                Picker(label, selection: selection) {
                    Text("Not set").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(MacColor.textPrimary)
                .padding(.horizontal, MacSpace.sm)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.small))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.small).strokeBorder(MacColor.cardBorder, lineWidth: 1))
            } else {
                Text(selection.wrappedValue.isEmpty ? "Not set" : selection.wrappedValue)
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textPrimary)
            }
        }
        .padding(.vertical, 3)
    }

    private var employmentTypeRow: some View {
        HStack(spacing: MacSpace.md) {
            Text("Employment")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 104, alignment: .leading)
            if isEditing {
                Picker("Employment", selection: $draft.employmentType) {
                    ForEach(EmploymentType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(MacColor.textPrimary)
                .padding(.horizontal, MacSpace.sm)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.small))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.small).strokeBorder(MacColor.cardBorder, lineWidth: 1))
            } else {
                Text(draft.employmentType.label)
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textPrimary)
            }
        }
        .padding(.vertical, 3)
    }

    private func editableDateRow(_ label: String, date: Binding<Date?>) -> some View {
        HStack(spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 104, alignment: .leading)
            if isEditing {
                DatePicker(
                    label,
                    selection: Binding(get: { date.wrappedValue ?? Date() }, set: { date.wrappedValue = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()
                .environment(\.timeZone, RosterCalendar.timeZone)
                .tint(MacColor.accent)
                .padding(.horizontal, MacSpace.sm)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.small))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.small).strokeBorder(MacColor.cardBorder, lineWidth: 1))
            } else {
                Text(date.wrappedValue.map { RosterFormat.date(RosterCalendar.dayFormatter.string(from: $0)) } ?? "Not set")
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textPrimary)
            }
        }
        .padding(.vertical, 3)
    }

    private func actionRow(_ label: String, value: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: MacSpace.md) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(MacType.body)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .macButton(.bordered, size: .small)
        }
        .padding(.vertical, 3)
    }

    private var addressEditor: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit address")
                        .font(MacType.sectionHeader)
                    Text("Current address for \(liveUser.fullName)")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }
                Spacer()
                Button { showAddressEditor = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }

            TextEditor(text: $addressDraft)
                .font(MacType.body)
                .padding(MacSpace.sm)
                .frame(height: 110)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).strokeBorder(MacColor.cardBorder))

            HStack {
                Button("Cancel") { showAddressEditor = false }
                    .macButton(.bordered)
                Spacer()
                MacAsyncButton(variant: .prominent) { await saveAddress() } label: { Text("Save address") }
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 520)
    }

    private var deletionConfirmation: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack(alignment: .top) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(MacColor.error)
                    .frame(width: 42, height: 42)
                    .background(MacColor.error.opacity(0.1), in: RoundedRectangle(cornerRadius: MacRadius.medium))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete \(liveUser.fullName)’s account?")
                        .font(MacType.sectionHeader)
                    Text("Access is locked immediately. Sign-in is removed after 30 days; payroll and employment records are retained.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if let sensitiveActionError {
                Text(sensitiveActionError)
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.error)
                    .padding(MacSpace.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacColor.error.opacity(0.08), in: RoundedRectangle(cornerRadius: MacRadius.medium))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm with your manager password")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textSecondary)
                SecureField("Manager password", text: $managerPassword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await confirmDeletion() } }
            }

            HStack {
                Button("Cancel") { showDeleteAccount = false }
                    .macButton(.bordered)
                Spacer()
                MacAsyncButton(variant: .destructive) { await confirmDeletion() } label: {
                    Text("Verify & delete account")
                }
                .disabled(managerPassword.isEmpty || isAccountWorking)
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 540)
    }

    private var statusTint: Color {
        switch liveUser.status {
        case .active: return MacColor.success
        case .inactive: return MacColor.textTertiary
        case .locked: return MacColor.error
        }
    }

    private var hourlyRate: String {
        let value = repo.liveHourlyRate(forStaffId: liveUser.id)
        return value > 0 ? String(format: "$%.2f", value) : "Not set"
    }

    private var wageSummary: String {
        guard let profile = repo.staffWageProfile(for: liveUser.id) else { return "Not set" }
        var parts: [String] = []
        if let awardID = profile.awardId,
           let award = repo.wageAwards.first(where: { $0.id == awardID }) {
            parts.append(award.code.isEmpty ? award.name : award.code)
        }
        if let level = profile.classificationLevel, !level.isEmpty { parts.append("Level \(level)") }
        if !profile.earningsLineIds.isEmpty { parts.append("\(profile.earningsLineIds.count) pay item\(profile.earningsLineIds.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    private func formattedTimestamp(_ value: String?) -> String {
        guard let value, let date = FS.isoDate(from: value) else { return "Not recorded" }
        return RosterFormat.dateFull(date)
    }

    private func dateKey(_ date: Date?) -> String {
        date.map(RosterCalendar.dayFormatter.string) ?? ""
    }

    private func saveChanges() {
        let name = draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            toasts.show("Name can’t be empty.", style: .error)
            return
        }
        if let error = ContactValidation.phoneError(draft.phone, required: false) {
            toasts.show(error, style: .error)
            return
        }
        if let error = ContactValidation.phoneError(draft.emergencyPhone, required: false) {
            toasts.show("Emergency contact: \(error)", style: .error)
            return
        }
        let emergencyEmail = draft.emergencyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = ContactValidation.emailError(emergencyEmail, required: false) {
            toasts.show(error, style: .error)
            return
        }
        if let error = TFN.validationError(draft.tfn) {
            toasts.show(error, style: .error)
            return
        }

        let employeeID = draft.employeeID.uppercased().filter { $0.isLetter || $0.isNumber }
        var fields: [String: Any] = [
            "fullName": name,
            "phone": draft.phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "employeeId": employeeID,
            "defaultDepartment": draft.role,
            "employmentType": draft.employmentType.rawValue,
            "startDate": dateKey(draft.startDate),
            "dob": dateKey(draft.dob),
            "tfn": TFN.normalize(draft.tfn),
            "emergencyContactName": draft.emergencyName,
            "emergencyContact": draft.emergencyName,
            "emergencyContactPhone": draft.emergencyPhone,
            "emergencyContactEmail": emergencyEmail,
            "emergencyContactAddress": draft.emergencyAddress,
        ]
        if draft.role != baseline.role {
            fields["roleReviewRequired"] = true
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await repo.updateStaffFields(staffId: liveUser.id, fields)
                draft.fullName = name
                draft.employeeID = employeeID
                draft.emergencyEmail = emergencyEmail
                baseline = draft
                isEditing = false
                toasts.show("Staff details saved.", style: .success)
            } catch {
                toasts.show("Couldn’t save details. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func toggleEmailChangeRequest() {
        Task {
            do {
                if emailRequested {
                    try await repo.cancelStaffEmailChange(staffId: liveUser.id)
                    emailRequested = false
                    toasts.show("Email change request cancelled.", style: .success)
                } else {
                    try await repo.requestStaffEmailChange(staffId: liveUser.id)
                    emailRequested = true
                    toasts.show("\(liveUser.firstName) will be asked to change their email in the iPhone app.", style: .success)
                }
            } catch {
                toasts.show("Couldn’t update the email request. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func saveAddress() async {
        do {
            try await repo.updateStaffFields(staffId: liveUser.id, [
                "address": addressDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                "profileUpdateRequired": false,
            ])
            showAddressEditor = false
            toasts.show("Address updated.", style: .success)
        } catch {
            toasts.show("Couldn’t update address. \(error.localizedDescription)", style: .error)
        }
    }

    private func toggleEmergencyDetailsRequirement() {
        let required = !liveUser.emergencyDetailsRequired
        Task {
            do {
                try await repo.requestStaffEmergencyDetails(staffId: liveUser.id, required: required)
                toasts.show(
                    required
                        ? "Emergency details will be required before \(liveUser.firstName) can access the iPhone app."
                        : "Emergency details requirement cancelled.",
                    style: .success
                )
            } catch {
                toasts.show("Couldn’t update the requirement. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func setAccountLock(locked: Bool) {
        Task {
            do {
                try await repo.updateStaffFields(staffId: liveUser.id, [
                    "status": (locked ? UserStatus.locked : UserStatus.active).rawValue,
                ])
                toasts.show(locked ? "User locked." : "User unlocked.", style: .success)
            } catch {
                toasts.show("Couldn’t update account access. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func confirmDeletion() async {
        guard !managerPassword.isEmpty, !isAccountWorking else { return }
        isAccountWorking = true
        sensitiveActionError = nil
        defer { isAccountWorking = false }
        do {
            try await AuthService.shared.reauthenticate(password: managerPassword)
            try await repo.approveStaffAccountDeletion(staffId: liveUser.id)
            managerPassword = ""
            showDeleteAccount = false
            toasts.show("Account locked and scheduled for deletion in 30 days.", style: .success)
        } catch {
            sensitiveActionError = error.localizedDescription
        }
    }

    private func cancelDeletion() {
        Task {
            do {
                try await repo.cancelStaffAccountDeletion(staffId: liveUser.id)
                toasts.show("Deletion cancelled and account reinstated.", style: .success)
            } catch {
                toasts.show("Couldn’t cancel deletion. \(error.localizedDescription)", style: .error)
            }
        }
    }
}

// MARK: - Mac Add Staff Modal

struct MacAddStaffModal: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var roleTitle = ""
    @State private var errorMessage: String?

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack {
                Text("Invite New Staff Member")
                    .font(MacType.sectionHeader)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }

            if let errorMessage {
                Text(errorMessage).font(MacType.captionStrong).foregroundStyle(MacColor.error)
            }

            VStack(spacing: MacSpace.md) {
                TextField("Full Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Email Address", text: $email)
                    .textFieldStyle(.roundedBorder)
                TextField("Role Title (e.g. Senior Barista)", text: $roleTitle)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }.macButton(.bordered)
                Spacer()
                MacAsyncButton(variant: .prominent) {
                    do {
                        try await repo.inviteStaffMember(name: name, email: email, roleTitle: roleTitle)
                        toasts.show("Staff invitation sent successfully!", style: .success)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Text("Send Invite")
                }
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 440)
    }
}

// MARK: - Mac Manager Payroll View

struct MacManagerPayrollView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts
    @Environment(MacNavigationModel.self) private var navigation
    @Environment(\.openURL) private var openURL

    private enum ActiveSheet: Identifiable {
        case gaps([PayrollGapItem])
        case publish([Payslip])

        var id: String {
            switch self {
            case .gaps: return "gaps"
            case .publish: return "publish"
            }
        }
    }

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case earnings = "Earnings"
        case taxAndSuper = "Tax & super"
        case history = "History"
        var id: String { rawValue }
    }

    @State private var weekKey = RosterCalendar.dayFormatter.string(
        from: RosterCalendar.addWeeks(-1, to: RosterCalendar.weekStart())
    )
    @State private var activeSheet: ActiveSheet?
    @State private var isGenerating = false
    @State private var selectedPayslipID: String?
    @State private var workingPayslip: Payslip?
    @State private var originalPayslip: Payslip?
    @State private var inspectorTab: InspectorTab = .earnings
    @State private var isSavingPayslip = false
    @State private var regenerationChanges: [PayslipRegenerationChange] = []
    @State private var showRegenerationPrompt = false

    init() {}

    private var weekMonday: Date {
        RosterCalendar.dateFromKey(weekKey) ?? RosterCalendar.weekStart()
    }

    private var periodSlips: [Payslip] {
        repo.payslips
            .filter { $0.periodStart == weekKey }
            .sorted { $0.staffName.localizedCaseInsensitiveCompare($1.staffName) == .orderedAscending }
    }

    private var publishableSlips: [Payslip] {
        periodSlips.filter { $0.status == .draft || $0.status == .underReview || $0.status == .approved }
    }

    private var periodGaps: [PayrollGapItem] {
        repo.payrollGaps(weekStart: weekMonday)
    }

    private var totals: PayrollCalculator.Totals {
        periodSlips.reduce(
            PayrollCalculator.Totals(
                ordinaryAmount: 0, weekendAmount: 0, publicHolidayAmount: 0,
                overtimeAmount: 0, extrasAmount: 0, gross: 0, tax: 0,
                deductions: 0, superAmount: 0, net: 0, totalHours: 0
            )
        ) { result, slip in
            let value = slip.totals
            return PayrollCalculator.Totals(
                ordinaryAmount: result.ordinaryAmount + value.ordinaryAmount,
                weekendAmount: result.weekendAmount + value.weekendAmount,
                publicHolidayAmount: result.publicHolidayAmount + value.publicHolidayAmount,
                overtimeAmount: result.overtimeAmount + value.overtimeAmount,
                extrasAmount: result.extrasAmount + value.extrasAmount,
                gross: result.gross + value.gross,
                tax: result.tax + value.tax,
                deductions: result.deductions + value.deductions,
                superAmount: result.superAmount + value.superAmount,
                net: result.net + value.net,
                totalHours: result.totalHours + value.totalHours
            )
        }
    }

    private var configuredAward: WageAward? {
        repo.wageAwards.first { $0.code.uppercased() == "MA000089" }
    }

    private var configuredClassificationCount: Int {
        guard let award = configuredAward else { return 0 }
        let lineCount = repo.earningsLines.filter {
            $0.active && $0.isClassificationLevel && $0.awardId == award.id
        }.count
        return lineCount > 0 ? lineCount : award.classifications.count
    }

    private var assignedStaffCount: Int {
        guard let award = configuredAward else { return 0 }
        return repo.staffWageProfiles.filter { $0.active && $0.awardId == award.id }.count
    }

    private var missingRateCount: Int {
        periodSlips.filter { $0.baseHourlyRate <= 0 }.count
    }

    private var submittedCount: Int {
        periodSlips.filter { $0.status == .submitted }.count
    }

    private var payslipHasChanges: Bool {
        guard let workingPayslip, let originalPayslip else { return false }
        return workingPayslip != originalPayslip
    }

    var body: some View {
        MacScreen(
            title: "Payroll",
            subtitle: "Review, calculate and publish your weekly Australian pay run",
            actions: {
                Button {
                    generateDrafts()
                } label: {
                    if isGenerating {
                        HStack(spacing: MacSpace.sm) {
                            ProgressView().controlSize(.small)
                            Text("Generating…")
                        }
                    } else {
                        Label(
                            periodSlips.isEmpty ? "Generate Drafts" : "Refresh Pay Run",
                            systemImage: periodSlips.isEmpty ? "wand.and.sparkles" : "arrow.clockwise"
                        )
                    }
                }
                .disabled(isGenerating)
                .macButton(.bordered, size: .small)

                if !publishableSlips.isEmpty {
                    Button {
                        activeSheet = .publish(periodSlips.filter { $0.status != .archived })
                    } label: {
                        Label("Review & Publish", systemImage: "paperplane.fill")
                    }
                    .macButton(.success, size: .small)
                }
            }
        ) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: MacSpace.xl) {
                        periodBar
                        metrics

                        if proxy.size.width >= 1120 {
                            HStack(alignment: .top, spacing: MacSpace.xl) {
                                VStack(spacing: MacSpace.xl) {
                                    payslipRegister
                                    recentPeriodsCard
                                }
                                .frame(maxWidth: .infinity, alignment: .top)

                                payslipInspector
                                    .frame(width: min(430, max(370, proxy.size.width * 0.29)), alignment: .top)
                            }
                        } else {
                            VStack(spacing: MacSpace.xl) {
                                payslipRegister
                                payslipInspector
                                recentPeriodsCard
                            }
                        }
                    }
                    .padding(.horizontal, proxy.size.width >= 1500 ? MacSpace.xxxl : MacSpace.xxl)
                    .padding(.vertical, MacSpace.xxl)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .disabled(isGenerating)
        .onAppear { syncSelectedPayslip(force: true) }
        .onChange(of: weekKey) { syncSelectedPayslip(force: true) }
        .onChange(of: repo.payslips) { syncSelectedPayslip(force: !payslipHasChanges) }
        .alert("Approved timesheet hours changed", isPresented: $showRegenerationPrompt) {
            Button("Cancel", role: .cancel) {
                regenerationChanges = []
            }
            Button("Regenerate payslips") {
                runGeneration(regenerating: regenerationChanges.map(\.payslip))
            }
        } message: {
            Text(regenerationPromptMessage)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .gaps(let gaps):
                PayrollGapsSheet(
                    gaps: gaps,
                    weekLabel: RosterFormat.weekRange(monday: weekMonday),
                    onGenerateAnyway: { checkForTimesheetChanges() }
                )
            case .publish(let payslips):
                PayslipBulkPublishSheet(slips: payslips, weekMonday: weekMonday) { count in
                    toasts.show("Published \(count) payslip\(count == 1 ? "" : "s").", style: .success)
                }
            }
        }
    }

    private var periodBar: some View {
        MacCard {
            HStack(spacing: MacSpace.lg) {
                periodArrow("chevron.left", help: "Previous pay period") { moveWeek(-1) }

                VStack(alignment: .leading, spacing: 3) {
                    Text("PAY PERIOD")
                        .font(MacType.badge)
                        .tracking(0.7)
                        .foregroundStyle(MacColor.textTertiary)
                    Text(RosterFormat.weekRange(monday: weekMonday))
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                }

                periodArrow("chevron.right", help: "Next pay period") { moveWeek(1) }

                Button("Last completed week") {
                    weekKey = RosterCalendar.dayFormatter.string(
                        from: RosterCalendar.addWeeks(-1, to: RosterCalendar.weekStart())
                    )
                }
                .macButton(.bordered, size: .small)

                Spacer()
                Text("\(submittedCount) of \(periodSlips.count) published")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textSecondary)
            }
        }
    }

    private func periodArrow(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacColor.textPrimary)
        .background(MacColor.cardBackgroundSecondary, in: Capsule())
        .overlay(Capsule().strokeBorder(MacColor.cardBorder, lineWidth: 1))
        .help(help)
    }

    private var metrics: some View {
        HStack(spacing: MacSpace.lg) {
            MacStatCard(
                title: "Gross Wages",
                value: RosterFormat.money(totals.gross),
                subtitle: "\(periodSlips.count) payslip\(periodSlips.count == 1 ? "" : "s") · \(String(format: "%.1f", totals.totalHours)) hours",
                icon: "banknote.fill",
                tint: MacColor.accent
            )
            MacStatCard(
                title: "PAYG Withholding",
                value: RosterFormat.money(totals.tax),
                subtitle: "ATO weekly withholding",
                icon: "building.columns.fill",
                tint: MacColor.warning
            )
            MacStatCard(
                title: "Super",
                value: RosterFormat.money(totals.superAmount),
                subtitle: "12% default · payable on payday",
                icon: "shield.checkered",
                tint: MacColor.info
            )
            MacStatCard(
                title: "Net Pay",
                value: RosterFormat.money(totals.net),
                subtitle: "\(submittedCount) of \(periodSlips.count) published",
                icon: "arrow.down.to.line.compact",
                tint: MacColor.success
            )
        }
    }

    private var payslipRegister: some View {
        MacCard(title: "Pay run register", subtitle: "Open a payslip to review its hours, rates, deductions and audit trail", icon: "list.bullet.rectangle") {
            if repo.isLoading {
                MacLoadingView(message: "Loading payroll…")
                    .frame(height: 260)
            } else if periodSlips.isEmpty {
                MacEmptyState(
                    title: "No payslips for this period",
                    subtitle: "Generate drafts from approved timesheets and each staff member’s wage assignment.",
                    icon: "banknote",
                    actionTitle: "Generate Drafts",
                    action: { generateDrafts() }
                )
                .frame(minHeight: 300)
            } else {
                VStack(spacing: 0) {
                    registerHeader
                    ForEach(periodSlips) { payslipRow($0) }
                }
            }
        }
    }

    private var registerHeader: some View {
        HStack(spacing: MacSpace.md) {
            Text("EMPLOYEE").frame(maxWidth: .infinity, alignment: .leading)
            Text("HOURS").frame(width: 62, alignment: .trailing)
            Text("GROSS").frame(width: 90, alignment: .trailing)
            Text("PAYG").frame(width: 80, alignment: .trailing)
            Text("SUPER").frame(width: 80, alignment: .trailing)
            Text("NET PAY").frame(width: 96, alignment: .trailing)
            Text("STATUS").frame(width: 96, alignment: .trailing)
        }
        .font(MacType.badge)
        .tracking(0.5)
        .foregroundStyle(MacColor.textTertiary)
        .padding(.horizontal, MacSpace.md)
        .padding(.vertical, MacSpace.sm)
        .background(MacColor.tableHeaderBackground)
    }

    private func payslipRow(_ slip: Payslip) -> some View {
        Button {
            selectPayslip(slip)
        } label: {
            HStack(spacing: MacSpace.md) {
                MacAvatar(name: slip.staffName, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(slip.staffName)
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)
                        if slip.baseHourlyRate <= 0 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(MacColor.warning)
                        }
                    }
                    Text([slip.classification, slip.employmentType.capitalized]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.1f", slip.totals.totalHours))
                    .frame(width: 62, alignment: .trailing)
                Text(RosterFormat.money(slip.totals.gross))
                    .frame(width: 90, alignment: .trailing)
                Text(RosterFormat.money(slip.totals.tax))
                    .frame(width: 80, alignment: .trailing)
                Text(RosterFormat.money(slip.totals.superAmount))
                    .frame(width: 80, alignment: .trailing)
                Text(RosterFormat.money(slip.totals.net))
                    .fontWeight(.semibold)
                    .frame(width: 96, alignment: .trailing)
                payslipStatus(slip.status)
                    .frame(width: 96, alignment: .trailing)
            }
            .font(MacType.mono)
            .foregroundStyle(MacColor.textSecondary)
            .padding(.horizontal, MacSpace.md)
            .padding(.vertical, MacSpace.md)
            .contentShape(Rectangle())
            .background(selectedPayslipID == slip.id ? MacColor.tableRowSelected : Color.clear)
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().fill(MacColor.separator).frame(height: 1), alignment: .bottom)
        .contextMenu {
            Button("Show Details", systemImage: "sidebar.right") {
                selectPayslip(slip)
            }
        }
    }

    @ViewBuilder
    private var payslipInspector: some View {
        if let slip = workingPayslip {
            MacCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    inspectorHeader(slip)

                    Picker("Payslip section", selection: $inspectorTab) {
                        ForEach(InspectorTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, MacSpace.lg)
                    .padding(.bottom, MacSpace.lg)

                    Divider()

                    Group {
                        switch inspectorTab {
                        case .earnings:
                            earningsInspector(slip)
                        case .taxAndSuper:
                            taxAndSuperInspector(slip)
                        case .history:
                            historyInspector(slip)
                        }
                    }
                    .padding(MacSpace.lg)

                    Divider()
                    inspectorFooter(slip)
                }
            }
        } else {
            MacCard {
                MacEmptyState(
                    title: "Select an employee",
                    subtitle: "Choose a row in the pay run to review hours, rates, tax, super and history here.",
                    icon: "person.crop.rectangle"
                )
                .frame(minHeight: 360)
            }
        }
    }

    private func inspectorHeader(_ slip: Payslip) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            HStack(spacing: MacSpace.md) {
                MacAvatar(name: slip.staffName, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slip.staffName)
                        .font(MacType.sectionHeader)
                        .foregroundStyle(MacColor.textPrimary)
                    Text([slip.classification, slip.employmentType.capitalized]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                payslipStatus(slip.status)
            }

            HStack(spacing: MacSpace.sm) {
                inspectorMetric("Hours", String(format: "%.1f", slip.totals.totalHours))
                inspectorMetric("Gross", RosterFormat.money(slip.totals.gross))
                inspectorMetric("Net", RosterFormat.money(slip.totals.net))
            }
        }
        .padding(MacSpace.lg)
    }

    private func inspectorMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(MacType.badge)
                .foregroundStyle(MacColor.textTertiary)
            Text(value)
                .font(MacType.monoStrong)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, MacSpace.md)
        .padding(.vertical, MacSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
    }

    private func earningsInspector(_ slip: Payslip) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            inspectorSectionTitle("Hours and rates", detail: "Adjust this draft before approval")
            inspectorPayRow("Ordinary", hours: numberBinding(\.ordinaryHours), rate: numberBinding(\.baseHourlyRate), editable: slip.status.isEditable)
            inspectorPayRow("Weekend", hours: numberBinding(\.weekendHours), rate: numberBinding(\.weekendRate), editable: slip.status.isEditable)
            inspectorPayRow("Public holiday", hours: numberBinding(\.publicHolidayHours), rate: numberBinding(\.publicHolidayRate), editable: slip.status.isEditable)
            inspectorPayRow("Overtime", hours: numberBinding(\.overtimeHours), rate: numberBinding(\.overtimeRate), editable: slip.status.isEditable)

            if !slip.extraEarnings.isEmpty {
                Divider().padding(.vertical, MacSpace.xs)
                inspectorSectionTitle("Allowances and other earnings", detail: nil)
                ForEach(slip.extraEarnings) { earning in
                    HStack {
                        Text(earning.name)
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textSecondary)
                        Spacer()
                        Text(RosterFormat.money(earning.amount))
                            .font(MacType.monoStrong)
                            .foregroundStyle(MacColor.textPrimary)
                    }
                }
            }

            if slip.baseHourlyRate <= 0 {
                Label("An hourly rate is required before publishing.", systemImage: "exclamationmark.triangle.fill")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.warning)
                    .padding(.top, MacSpace.xs)
            }
        }
    }

    private func taxAndSuperInspector(_ slip: Payslip) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            inspectorSectionTitle("Tax and deductions", detail: "Weekly Australian withholding inputs")
            inspectorMoneyRow("PAYG withholding", binding: numberBinding(\.payg), editable: slip.status.isEditable)
            inspectorMoneyRow("Other deductions", binding: numberBinding(\.otherDeductions), editable: slip.status.isEditable)
            inspectorMoneyRow("Salary sacrifice", binding: numberBinding(\.salarySacrifice), editable: slip.status.isEditable)

            Toggle("Claims tax-free threshold", isOn: boolBinding(\.claimsTaxFreeThreshold))
                .font(MacType.caption)
                .disabled(!slip.status.isEditable || isSavingPayslip)

            if slip.status.isEditable {
                Button("Recalculate PAYG") {
                    workingPayslip?.payg = PayrollCalculator.calculatedPAYG(for: workingPayslip ?? slip)
                }
                .macButton(.bordered, size: .small)
            }

            Divider().padding(.vertical, MacSpace.xs)
            inspectorSectionTitle("Superannuation", detail: "Employer contribution on ordinary time earnings")
            HStack {
                Text("Super guarantee")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
                Spacer()
                TextField("0", value: nonNegative(numberBinding(\.superRate)), format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 82)
                    .disabled(!slip.status.isEditable || isSavingPayslip)
                Text("%")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }
            HStack {
                Text("Employer super")
                Spacer()
                Text(RosterFormat.money(slip.totals.superAmount))
                    .font(MacType.monoStrong)
            }
            .font(MacType.captionStrong)
            .foregroundStyle(MacColor.textPrimary)
        }
    }

    private func historyInspector(_ slip: Payslip) -> some View {
        VStack(alignment: .leading, spacing: MacSpace.md) {
            inspectorSectionTitle("Pay run history", detail: "Changes to this employee’s payslip")
            if slip.audit.isEmpty {
                Text("No activity recorded yet.")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                ForEach(slip.audit.sorted { $0.at > $1.at }) { entry in
                    HStack(alignment: .top, spacing: MacSpace.sm) {
                        Circle()
                            .fill(MacColor.accent.opacity(0.18))
                            .frame(width: 24, height: 24)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(MacColor.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.detail.isEmpty ? entry.action.capitalized : entry.detail)
                                .font(MacType.captionStrong)
                                .foregroundStyle(MacColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(entry.userName) · \(entry.at.formatted(date: .abbreviated, time: .shortened))")
                                .font(MacType.caption)
                                .foregroundStyle(MacColor.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func inspectorFooter(_ slip: Payslip) -> some View {
        VStack(spacing: MacSpace.md) {
            if payslipHasChanges {
                HStack {
                    Button("Discard") { resetWorkingPayslip() }
                        .macButton(.ghost, size: .small)
                    Spacer()
                    Button(isSavingPayslip ? "Saving…" : "Save changes") { saveWorkingPayslip() }
                        .macButton(.prominent, size: .small)
                        .disabled(isSavingPayslip)
                }
            }

            HStack {
                Text(workflowHint(slip.status))
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                Spacer(minLength: MacSpace.sm)
                if let action = workflowAction(for: slip.status) {
                    Button(action.title) { advanceWorkflow(action.status) }
                        .macButton(action.status == .submitted ? .success : .bordered, size: .small)
                        .disabled(isSavingPayslip || slip.baseHourlyRate <= 0)
                }
            }
        }
        .padding(MacSpace.lg)
    }

    private func inspectorSectionTitle(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
            if let detail {
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }
        }
    }

    private func inspectorPayRow(_ label: String, hours: Binding<Double>, rate: Binding<Double>, editable: Bool) -> some View {
        HStack(spacing: MacSpace.sm) {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("0", value: nonNegative(hours), format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 62)
                .disabled(!editable || isSavingPayslip)
            Text("h ×")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
            TextField("0.00", value: nonNegative(rate), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 78)
                .disabled(!editable || isSavingPayslip)
        }
    }

    private func inspectorMoneyRow(_ label: String, binding: Binding<Double>, editable: Bool) -> some View {
        HStack {
            Text(label)
                .font(MacType.caption)
                .foregroundStyle(MacColor.textSecondary)
            Spacer()
            Text("$")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
            TextField("0.00", value: nonNegative(binding), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 92)
                .disabled(!editable || isSavingPayslip)
        }
    }

    private func numberBinding(_ keyPath: WritableKeyPath<Payslip, Double>) -> Binding<Double> {
        Binding(
            get: { workingPayslip?[keyPath: keyPath] ?? 0 },
            set: { value in workingPayslip?[keyPath: keyPath] = max(0, value) }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<Payslip, Bool>) -> Binding<Bool> {
        Binding(
            get: { workingPayslip?[keyPath: keyPath] ?? false },
            set: { value in workingPayslip?[keyPath: keyPath] = value }
        )
    }

    private func nonNegative(_ binding: Binding<Double>) -> Binding<Double> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = max(0, $0) })
    }

    private var readinessCard: some View {
        MacCard(title: "Ready to publish?", icon: "checklist") {
            VStack(spacing: 0) {
                readinessRow(
                    title: "Approved timesheets",
                    detail: periodGaps.isEmpty ? "No unresolved shifts" : "\(periodGaps.count) shift\(periodGaps.count == 1 ? "" : "s") need action",
                    ready: periodGaps.isEmpty
                )
                Divider().padding(.vertical, MacSpace.md)
                readinessRow(
                    title: "Pay rates assigned",
                    detail: missingRateCount == 0 ? "Every draft has a rate" : "\(missingRateCount) missing rate\(missingRateCount == 1 ? "" : "s")",
                    ready: missingRateCount == 0
                )
                Divider().padding(.vertical, MacSpace.md)
                readinessRow(
                    title: "Award configured",
                    detail: configuredAward?.active == true ? "MA000089 is active · review each payslip" : "Configure MA000089",
                    ready: configuredAward?.active == true
                )

                if !periodSlips.isEmpty {
                    Divider().padding(.vertical, MacSpace.md)
                    HStack {
                        Text("Published")
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.textSecondary)
                        Spacer()
                        Text("\(submittedCount) / \(periodSlips.count)")
                            .font(MacType.monoStrong)
                            .foregroundStyle(MacColor.textPrimary)
                    }
                    ProgressView(value: Double(submittedCount), total: Double(max(periodSlips.count, 1)))
                        .tint(MacColor.success)
                        .padding(.top, MacSpace.sm)
                }
            }
        }
    }

    private var awardCard: some View {
        MacCard(title: "MA000089 review", subtitle: "Vehicle Repair, Services and Retail Award", icon: "shield.text.fill") {
            VStack(alignment: .leading, spacing: MacSpace.md) {
                awardCheck("Correct stream and classification", detail: "Repair/service, fuel retail, sales, junior or apprentice")
                awardCheck("Penalty rates reviewed", detail: "Saturday, Sunday and public holiday rates differ")
                awardCheck("Overtime and allowances", detail: "Check triggers, meal breaks and applicable tools or duties")
                awardCheck("Payday Super", detail: "Confirm 12% qualifying earnings and fund receipt timing")

                HStack(alignment: .top, spacing: MacSpace.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MacColor.warning)
                    Text("Configured rates are not an automatic compliance determination. Review the applicable employee stream and current Fair Work pay guide before publishing.")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MacSpace.md)
                .background(MacColor.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: MacRadius.medium))

                HStack(spacing: MacSpace.sm) {
                    Button("Open Wage Awards") {
                        navigation.select(.managerWage)
                    }
                    .macButton(.bordered, size: .small)

                    Menu("Official sources") {
                        Button("MA000089 Award") {
                            openURL(URL(string: "https://awards.fairwork.gov.au/MA000089.html")!)
                        }
                        Button("Fair Work Pay Guides") {
                            openURL(URL(string: "https://www.fairwork.gov.au/pay-and-wages/minimum-wages/pay-guides")!)
                        }
                        Button("ATO Payday Super") {
                            openURL(URL(string: "https://softwaredevelopers.ato.gov.au/PaydaySuper")!)
                        }
                    }
                    .macButton(.ghost, size: .small)
                }

                Text("\(configuredClassificationCount) classification\(configuredClassificationCount == 1 ? "" : "s") configured · \(assignedStaffCount) staff assigned")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var recentPeriodsCard: some View {
        let grouped = Dictionary(grouping: repo.payslips.filter { $0.periodStart != weekKey }, by: \.periodStart)
        let periods = Array(grouped.keys.sorted(by: >).prefix(4))
        if !periods.isEmpty {
            MacCard(title: "Recent pay runs", icon: "clock.arrow.circlepath") {
                VStack(spacing: 0) {
                    ForEach(periods, id: \.self) { period in
                        Button {
                            weekKey = period
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(RosterFormat.weekRange(monday: RosterCalendar.dateFromKey(period) ?? Date()))
                                        .font(MacType.captionStrong)
                                        .foregroundStyle(MacColor.textPrimary)
                                    Text("\(grouped[period]?.count ?? 0) payslips")
                                        .font(MacType.caption)
                                        .foregroundStyle(MacColor.textTertiary)
                                }
                                Spacer()
                                Text(RosterFormat.money((grouped[period] ?? []).reduce(0) { $0 + $1.totals.net }))
                                    .font(MacType.monoStrong)
                                    .foregroundStyle(MacColor.textPrimary)
                            }
                            .padding(.vertical, MacSpace.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func readinessRow(title: String, detail: String, ready: Bool) -> some View {
        HStack(alignment: .top, spacing: MacSpace.md) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ready ? MacColor.success : MacColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textPrimary)
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func awardCheck(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: MacSpace.sm) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacColor.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textPrimary)
                Text(detail)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusBadge(_ text: String, tint: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(MacType.captionStrong)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.1), in: Capsule())
    }

    private func payslipStatus(_ status: PayslipStatus) -> some View {
        let tint: Color = {
            switch status {
            case .draft: return MacColor.warning
            case .underReview: return MacColor.info
            case .approved, .submitted: return MacColor.success
            case .archived: return MacColor.textTertiary
            }
        }()
        return Text(status.label)
            .font(MacType.captionStrong)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.1), in: Capsule())
    }

    private func moveWeek(_ offset: Int) {
        weekKey = RosterCalendar.dayFormatter.string(
            from: RosterCalendar.addWeeks(offset, to: weekMonday)
        )
    }

    private func selectPayslip(_ slip: Payslip) {
        guard selectedPayslipID != slip.id else { return }
        guard !payslipHasChanges else {
            toasts.show("Save or discard your changes before selecting another employee.", style: .warning)
            return
        }
        selectedPayslipID = slip.id
        workingPayslip = slip
        originalPayslip = slip
        inspectorTab = .earnings
    }

    private func syncSelectedPayslip(force: Bool) {
        guard let selectedPayslipID,
              let fresh = periodSlips.first(where: { $0.id == selectedPayslipID }) else {
            let first = periodSlips.first
            self.selectedPayslipID = first?.id
            workingPayslip = first
            originalPayslip = first
            inspectorTab = .earnings
            return
        }
        guard force else { return }
        workingPayslip = fresh
        originalPayslip = fresh
    }

    private func resetWorkingPayslip() {
        workingPayslip = originalPayslip
    }

    private func saveWorkingPayslip() {
        guard let slip = workingPayslip,
              let original = originalPayslip,
              let manager = repo.currentUser,
              slip.status.isEditable else { return }
        isSavingPayslip = true
        Task {
            defer { isSavingPayslip = false }
            do {
                try await repo.savePayslip(slip, original: original, editedBy: manager)
                originalPayslip = slip
                toasts.show("Saved \(slip.staffName)’s payslip.", style: .success)
            } catch {
                toasts.show("Couldn’t save payslip. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func workflowAction(for status: PayslipStatus) -> (title: String, status: PayslipStatus)? {
        switch status {
        case .draft: return ("Start review", .underReview)
        case .underReview: return ("Approve", .approved)
        case .approved: return ("Publish payslip", .submitted)
        case .submitted, .archived: return nil
        }
    }

    private func workflowHint(_ status: PayslipStatus) -> String {
        switch status {
        case .draft: return "Draft employee adjustment"
        case .underReview: return "Ready for approval"
        case .approved: return "Approved · editable until published"
        case .submitted: return "Published to employee"
        case .archived: return "Archived record"
        }
    }

    private func advanceWorkflow(_ status: PayslipStatus) {
        guard let slip = workingPayslip,
              let original = originalPayslip,
              let manager = repo.currentUser else { return }
        isSavingPayslip = true
        Task {
            defer { isSavingPayslip = false }
            do {
                if payslipHasChanges {
                    try await repo.savePayslip(slip, original: original, editedBy: manager)
                }
                if status == .submitted {
                    try await repo.publishPayslips([slip], by: manager)
                } else {
                    try await repo.setPayslipStatus(slip, to: status, by: manager)
                }
                var updated = slip
                updated.status = status
                workingPayslip = updated
                originalPayslip = updated
                toasts.show(status == .submitted ? "Payslip published." : "Moved to \(status.label).", style: .success)
            } catch {
                toasts.show("Couldn’t update payslip. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func generateDrafts() {
        guard !isGenerating else { return }
        let gaps = periodGaps
        if !gaps.isEmpty {
            activeSheet = .gaps(gaps)
        } else {
            checkForTimesheetChanges()
        }
    }

    private var regenerationPromptMessage: String {
        let rows = regenerationChanges.prefix(8).map {
            "\($0.payslip.staffName): \(String(format: "%.1f", $0.previousHours)) → \(String(format: "%.1f", $0.latestHours)) hours"
        }
        let remainder = regenerationChanges.count > 8
            ? "\n…and \(regenerationChanges.count - 8) more."
            : ""
        return "The latest approved timesheets differ from the current pay run:\n\n"
            + rows.joined(separator: "\n")
            + remainder
            + "\n\nRegenerating recalculates pay, PAYG and super and replaces manual edits. Approved payslips return to Draft for review. Published payslips are never changed."
    }

    private func checkForTimesheetChanges() {
        guard !isGenerating else { return }
        isGenerating = true
        Task {
            do {
                let changes = try await repo.payslipsNeedingRegeneration(weekStart: weekMonday)
                isGenerating = false
                if changes.isEmpty {
                    runGeneration()
                } else {
                    regenerationChanges = changes
                    showRegenerationPrompt = true
                }
            } catch {
                isGenerating = false
                toasts.show("Couldn’t check approved timesheets. \(error.localizedDescription)", style: .error)
            }
        }
    }

    private func runGeneration(regenerating slips: [Payslip] = []) {
        guard !isGenerating else { return }
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let created = try await repo.generateDraftPayslips(weekStart: weekMonday)
                for slip in slips {
                    try await repo.regenerateDraftPayslip(slip)
                }
                regenerationChanges = []
                if created > 0 || !slips.isEmpty {
                    let createdText = created > 0 ? "Created \(created) new" : ""
                    let separator = created > 0 && !slips.isEmpty ? " and " : ""
                    let refreshedText = slips.isEmpty ? "" : "regenerated \(slips.count)"
                    toasts.show("\(createdText)\(separator)\(refreshedText) payslip\((created + slips.count) == 1 ? "" : "s") from the latest approved timesheets.", style: .success)
                } else {
                    toasts.show("Pay run is up to date with approved timesheets.", style: .info)
                }
            } catch {
                toasts.show("Couldn’t generate payroll. \(error.localizedDescription)", style: .error)
            }
        }
    }
}
#endif
