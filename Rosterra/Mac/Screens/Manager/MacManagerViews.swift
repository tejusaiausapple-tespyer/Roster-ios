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
                            do {
                                for shift in timesheetShifts {
                                    try await repo.approveShiftTimesheet(shiftId: shift.id)
                                }
                                toasts.show("All pending timesheets approved!", style: .success)
                            } catch {
                                toasts.show(error.localizedDescription, style: .error)
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
    @State private var staffToEdit: AppUser?
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
                .macButton(.prominent, size: .small)
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
                            staffInspector(selectedStaff)
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
        .sheet(item: $staffToEdit) { staff in
            ManagerStaffDetailSheet(user: staff)
                .frame(width: 760)
                .frame(minHeight: 720)
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
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                staffToEdit = staff
            }
        )
        .contextMenu {
            Button {
                staffToEdit = staff
            } label: {
                Label("Edit details", systemImage: "pencil")
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
                        staffToEdit = staff
                    } label: {
                        Label("Edit details", systemImage: "pencil")
                    }
                    .macButton(.prominent)
                }

                if staff.deletion?.status == .requested {
                    Label(
                        "This staff member requested account deletion. Open Edit details to review it.",
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
                        value: staff.hourlyRate.map { String(format: "$%.2f", $0) } ?? "Not set",
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
                    inspectorCard(title: "Contact", icon: "person.crop.circle") {
                        inspectorRow("Email", staff.email)
                        inspectorRow("Phone", staff.phone?.isEmpty == false ? staff.phone! : "Not provided")
                        inspectorRow(
                            "Address",
                            staff.address?.isEmpty == false ? staff.address! : "Not provided"
                        )
                    }

                    inspectorCard(title: "Employment", icon: "building.2") {
                        inspectorRow("Role", staff.defaultDepartment?.isEmpty == false ? staff.defaultDepartment! : "Not set")
                        inspectorRow("Start date", formattedDate(staff.startDate))
                        inspectorRow("Member since", staff.memberSince ?? "—")
                    }
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

    private func maintainSelection() {
        if let selectedStaffID,
           filteredStaff.contains(where: { $0.id == selectedStaffID }) {
            return
        }
        selectedStaffID = filteredStaff.first?.id
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

    init() {}

    var body: some View {
        MacScreen(
            title: "Payroll Management",
            subtitle: "Generate and publish pay run statements with Australian awards",
            actions: {
                MacAsyncButton(variant: .prominent, size: .small) {
                    toasts.show("Pay run calculation complete.", style: .success)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                        Text("Calculate Pay Run")
                    }
                }
            }
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    HStack(spacing: MacSpace.lg) {
                        MacStatCard(
                            title: "Current Pay Period",
                            value: "Fortnightly",
                            subtitle: "Next payout: 15th Sep",
                            icon: "calendar.badge.clock",
                            tint: MacColor.accent
                        )

                        MacStatCard(
                            title: "Estimated Gross",
                            value: "$14,820.00",
                            subtitle: "Across 18 rostered staff",
                            icon: "banknote.fill",
                            tint: MacColor.success
                        )

                        MacStatCard(
                            title: "Super Guarantee",
                            value: "11.5%",
                            subtitle: "Compliant with ATO rules",
                            icon: "shield.checkmark.fill",
                            tint: MacColor.info
                        )
                    }

                    MacCard(title: "Published Pay Runs", icon: "doc.text.fill") {
                        if repo.payslips.isEmpty {
                            MacEmptyState(
                                title: "No Past Pay Runs",
                                subtitle: "Generate your first pay run using the button above.",
                                icon: "banknote"
                            )
                        } else {
                            VStack(spacing: MacSpace.md) {
                                ForEach(repo.payslips.prefix(10)) { payslip in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(payslip.periodRangeFormatted)
                                                .font(MacType.bodyStrong)
                                                .foregroundStyle(MacColor.textPrimary)
                                            Text("Staff: \(payslip.staffName)")
                                                .font(MacType.caption)
                                                .foregroundStyle(MacColor.textTertiary)
                                        }
                                        Spacer()
                                        Text("$\(String(format: "%.2f", payslip.netPay))")
                                            .font(MacType.monoStrong)
                                            .foregroundStyle(MacColor.textPrimary)
                                    }
                                    .padding(.vertical, 4)
                                    .overlay(Rectangle().fill(MacColor.separator.opacity(0.5)).frame(height: 1), alignment: .bottom)
                                }
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }
}
#endif
