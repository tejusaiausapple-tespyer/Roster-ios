import SwiftUI

// Manager Staff directory. The detail sheet lets a manager edit name, phone,
// email and employment type, and require a staff member to re-enter their
// address on next login. Width-adaptive card grid with Liquid Glass filters.
struct ManagerStaffView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var selected: AppUser? = nil

    var embedInNavigationStack = true

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, active, inactive, locked
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private var staff: [AppUser] {
        repo.allUsers.filter { $0.role == .staff }
    }

    private func statusMatches(_ user: AppUser) -> Bool {
        switch statusFilter {
        case .all: return true
        case .active: return user.status == .active
        case .inactive: return user.status == .inactive
        case .locked: return user.status == .locked
        }
    }

    private func count(_ filter: StatusFilter) -> Int {
        switch filter {
        case .all: return staff.count
        case .active: return staff.filter { $0.status == .active }.count
        case .inactive: return staff.filter { $0.status == .inactive }.count
        case .locked: return staff.filter { $0.status == .locked }.count
        }
    }

    private var filtered: [AppUser] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return staff
            .filter { statusMatches($0) }
            .filter { q.isEmpty || $0.fullName.lowercased().contains(q) || $0.email.lowercased().contains(q) }
            .sorted { $0.fullName < $1.fullName }
    }

    var body: some View {
        if embedInNavigationStack {
            NavigationStack { rootContent }
        } else {
            rootContent
        }
    }

    private var rootContent: some View {
        GeometryReader { _ in
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterBar
                    rosterGrid
                    summaryBar
                }
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Staff")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Staff Directory", icon: "person.2.fill")
            }
        }
        // .always pins the search field: with .automatic it hides until pulled,
        // so the pull-to-refresh gesture dragged it down over the filter bar.
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name or email")
        .sheet(item: $selected) { user in
            ManagerStaffDetailSheet(user: user)
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(StatusFilter.allCases) { filter in
                statusChip(filter)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusChip(_ filter: StatusFilter) -> some View {
        let selectedChip = statusFilter == filter
        return Button {
            statusFilter = filter
            Haptics.selection()
        } label: {
            HStack(spacing: 5) {
                Text(filter.title)
                Text("\(count(filter))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selectedChip ? .white : Theme.brand)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selectedChip ? .white : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(selectedChip ? Theme.brandStrong : Theme.card)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selectedChip ? Color.clear : Theme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var rosterGrid: some View {
        ScrollView {
            // One container so the fade tracking sees the full scroll content.
            VStack(spacing: 0) {
                TitlePillCollapseReporter()
                if filtered.isEmpty {
                    emptyState.padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { user in
                            Button {
                                selected = user
                                Haptics.selection()
                            } label: {
                                staffCard(user)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .scrollFadeContentTracking(in: "manager-staff-grid")
        }
        // Content fades out beneath the filter bar (top) and summary bar
        // (bottom) while scrolling — geometry-driven, so it holds on any
        // device size or orientation.
        .fadedScrollHints(coordinateSpace: "manager-staff-grid", showsChevrons: false)
        .refreshable { await repo.refreshFromServer() }
    }

    private func staffCard(_ user: AppUser) -> some View {
        let style = statusStyle(user.status)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(user.initials)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(style.tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(style.soft))

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.fullName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(user.employmentType?.label ?? "—")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(user.status.rawValue.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(style.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(style.soft))
            }

            Divider().overlay(Theme.separator)

            HStack {
                Label(user.phone?.isEmpty == false ? user.phone! : "No phone", systemImage: "phone")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                if let rate = user.hourlyRate {
                    Text(String(format: "$%.0f/hr", rate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(searchText.isEmpty ? "No \(statusFilter == .all ? "" : statusFilter.title.lowercased() + " ")staff" : "No matches for \"\(searchText)\"")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Summary footer

    private var summaryBar: some View {
        let content = HStack(spacing: 16) {
            summaryChip(icon: "person.2", text: "\(staff.count) staff")
            summaryChip(icon: "checkmark.circle", text: "\(count(.active)) active")
            if count(.locked) > 0 {
                summaryChip(icon: "lock", text: "\(count(.locked)) locked", tint: Theme.error)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)

        return ViewThatFits(in: .horizontal) {
            content
            ScrollView(.horizontal, showsIndicators: false) { content }
        }
        .glassCapsule()
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func summaryChip(icon: String, text: String, tint: Color = Theme.textPrimary) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    private func statusStyle(_ status: UserStatus) -> Theme.StatusStyle {
        switch status {
        case .active: return Theme.StatusStyle(tint: Theme.accent, soft: Theme.accent.opacity(0.14))
        case .inactive: return Theme.StatusStyle(tint: Theme.textTertiary, soft: Theme.textTertiary.opacity(0.14))
        case .locked: return Theme.StatusStyle(tint: Theme.error, soft: Theme.error.opacity(0.14))
        }
    }
}

// MARK: - Staff detail / edit sheet

struct ManagerStaffDetailSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss
    let user: AppUser

    @State private var fullName: String
    @State private var phone: String
    @State private var employmentType: EmploymentType
    @State private var status: UserStatus
    @State private var startDate: Date?
    @State private var dob: Date?
    @State private var emergencyName: String
    @State private var emergencyPhone: String
    @State private var emergencyAddress: String
    @State private var emergencyEmail: String

    @State private var isEditMode = false
    @State private var isSaving = false
    @State private var emailRequested: Bool
    @State private var showAddressConfirm = false
    @State private var showWageAssignment = false
    @State private var toast: ToastMessage?

    @State private var savedBaseline: Baseline

    private struct Baseline: Equatable {
        let fullName: String
        let phone: String
        let employmentType: EmploymentType
        let status: UserStatus
        let startDateKey: String?
        let dobKey: String?
        let emergencyName: String
        let emergencyPhone: String
        let emergencyAddress: String
        let emergencyEmail: String
    }

    init(user: AppUser) {
        self.user = user
        let phoneValue = user.phone ?? ""
        let emergencyNameValue = user.emergencyContactName ?? user.emergencyContact ?? ""
        _fullName = State(initialValue: user.fullName)
        _phone = State(initialValue: phoneValue)
        _employmentType = State(initialValue: user.employmentType ?? .casual)
        _status = State(initialValue: user.status)
        _startDate = State(initialValue: user.startDate.flatMap { RosterFormat.parseISODate($0) })
        _dob = State(initialValue: user.dob.flatMap { RosterFormat.parseISODate($0) })
        _emergencyName = State(initialValue: emergencyNameValue)
        _emergencyPhone = State(initialValue: user.emergencyContactPhone ?? "")
        _emergencyAddress = State(initialValue: user.emergencyContactAddress ?? "")
        _emergencyEmail = State(initialValue: user.emergencyContactEmail ?? "")
        _emailRequested = State(initialValue: user.emailChangeRequired)
        _savedBaseline = State(initialValue: Baseline(
            fullName: user.fullName,
            phone: phoneValue,
            employmentType: user.employmentType ?? .casual,
            status: user.status,
            startDateKey: user.startDate,
            dobKey: user.dob,
            emergencyName: emergencyNameValue,
            emergencyPhone: user.emergencyContactPhone ?? "",
            emergencyAddress: user.emergencyContactAddress ?? "",
            emergencyEmail: user.emergencyContactEmail ?? ""
        ))
    }

    private var hasChanges: Bool {
        currentBaseline != savedBaseline
    }

    private var currentBaseline: Baseline {
        Baseline(
            fullName: fullName,
            phone: phone,
            employmentType: employmentType,
            status: status,
            startDateKey: dateKey(startDate),
            dobKey: dateKey(dob),
            emergencyName: emergencyName,
            emergencyPhone: emergencyPhone,
            emergencyAddress: emergencyAddress,
            emergencyEmail: emergencyEmail
        )
    }

    private var valueColor: Color {
        isEditMode ? Theme.textPrimary : Theme.textTertiary
    }

    private var primaryActionTitle: String {
        isEditMode && hasChanges ? "Save" : "Edit"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    editableTextRow(label: "Full name", text: $fullName, capitalization: .words)
                    editableTextRow(label: "Phone", text: $phone, keyboard: .phonePad)
                    employmentRow
                }

                emailSection

                Section("Address") {
                    Text(user.address?.isEmpty == false ? user.address! : "No address on file")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                    Button {
                        showAddressConfirm = true
                    } label: {
                        Label("Require new address on next login", systemImage: "house.badge.exclamationmark")
                            .foregroundStyle(Theme.warning)
                    }
                }

                Section {
                    Button {
                        showWageAssignment = true
                    } label: {
                        HStack {
                            Label("Wage assignment", systemImage: "dollarsign.circle")
                                .foregroundStyle(Theme.brand)
                            Spacer()
                            Text(wageAssignmentSummary)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: {
                    Text("Pay (manager only)")
                } footer: {
                    Text("Award, classification, earnings lines and superannuation are managed in the wage assignment — only visible to managers. Set up awards and lines in the Wage tab first.")
                }

                Section("Record") {
                    statusRow
                    readOnlyRow("Member since", displayValue(displayedMemberSince))
                    editableDateRow(label: "Start date", date: $startDate)
                    editableDateRow(label: "Date of birth", date: $dob)
                }

                Section("Emergency contact") {
                    editableTextRow(label: "Name", text: $emergencyName, capitalization: .words)
                    editableTextRow(label: "Phone", text: $emergencyPhone, keyboard: .phonePad)
                    editableTextRow(label: "Address", text: $emergencyAddress, capitalization: .words)
                    editableTextRow(label: "Email", text: $emergencyEmail, keyboard: .emailAddress, capitalization: .never)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(user.firstName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(primaryActionTitle) { handlePrimaryAction() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .toast($toast)
            .sheet(isPresented: $showWageAssignment) {
                StaffWageAssignmentSheet(user: user)
            }
            .confirmationDialog(
                "Require new address?",
                isPresented: $showAddressConfirm,
                titleVisibility: .visible
            ) {
                Button("Require new address", role: .destructive) { requireAddress() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(user.firstName) will be asked to enter a new address next time they open the app, and won't reach their dashboard until they do. They can sign out from that screen instead.")
            }
        }
    }

    // MARK: - Rows

    private func editableTextRow(
        label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if isEditMode {
                TextField(label, text: text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text(displayValue(text.wrappedValue))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
    }

    private func editableDateRow(label: String, date: Binding<Date?>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if isEditMode {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date.wrappedValue ?? Date() },
                        set: { date.wrappedValue = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .environment(\.timeZone, RosterCalendar.timeZone)
            } else {
                Text(displayValue(date.wrappedValue.map { RosterFormat.date(RosterCalendar.dayFormatter.string(from: $0)) }))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func readOnlyRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var statusRow: some View {
        HStack {
            Text("Status")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if isEditMode, user.status != .locked {
                Picker("", selection: $status) {
                    Text("Active").tag(UserStatus.active)
                    Text("Inactive").tag(UserStatus.inactive)
                }
                .labelsHidden()
                .tint(Theme.textPrimary)
            } else {
                Text(status.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueColor)
            }
        }
    }

    private var employmentRow: some View {
        HStack {
            Text("Employment")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if isEditMode {
                Picker("", selection: $employmentType) {
                    ForEach(EmploymentType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .labelsHidden()
                .tint(Theme.textPrimary)
            } else {
                Text(employmentType.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueColor)
            }
        }
    }

    private var wageAssignmentSummary: String {
        guard let profile = repo.staffWageProfile(for: user.id) else { return "Not set" }
        var parts: [String] = []
        if let awardId = profile.awardId,
           let award = repo.wageAwards.first(where: { $0.id == awardId }) {
            parts.append(award.code.isEmpty ? award.name : award.code)
            if let level = profile.classificationLevel, !level.isEmpty {
                parts.append("L\(level)")
            }
        }
        if !profile.earningsLineIds.isEmpty {
            parts.append("\(profile.earningsLineIds.count) line\(profile.earningsLineIds.count == 1 ? "" : "s")")
        }
        if !profile.superEnabled {
            parts.append("No super")
        }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    // Email is a sign-in credential, so the manager only *requests* a change;
    // the staff member changes their own email via Firebase's verified flow.
    private var emailSection: some View {
        Section {
            readOnlyRow("Email", user.email)
            if emailRequested {
                Label("Change requested — waiting for \(user.firstName) to update it", systemImage: "clock.badge")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                Button("Cancel request", role: .destructive) { cancelEmailRequest() }
            } else {
                Button {
                    requestEmailChange()
                } label: {
                    Label("Ask \(user.firstName) to change their email", systemImage: "envelope.badge")
                        .foregroundStyle(Theme.brand)
                }
            }
        } header: {
            Text("Email")
        } footer: {
            Text("Email is a sign-in credential, so \(user.firstName) changes it themselves. They'll be prompted in the app and confirm via a Firebase verification link.")
        }
    }

    // MARK: - Helpers

    private var displayedMemberSince: String? {
        if let startDate {
            return RosterFormat.monthYear(startDate)
        }
        return user.memberSince
    }

    private func displayValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return value
    }

    private func dateKey(_ date: Date?) -> String? {
        guard let date else { return nil }
        return RosterCalendar.dayFormatter.string(from: date)
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        if isEditMode {
            if hasChanges {
                saveChanges()
            } else {
                isEditMode = false
                Haptics.selection()
            }
        } else {
            isEditMode = true
            Haptics.selection()
        }
    }

    private func saveChanges() {
        let trimmedName = fullName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            toast = ToastMessage(kind: .error, text: "Name can't be empty.")
            Haptics.error()
            return
        }

        let trimmedEmail = emergencyEmail.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty, !trimmedEmail.contains("@") {
            toast = ToastMessage(kind: .error, text: "Enter a valid emergency contact email.")
            Haptics.error()
            return
        }

        var fields: [String: Any] = [:]
        if trimmedName != savedBaseline.fullName { fields["fullName"] = trimmedName }
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        if trimmedPhone != savedBaseline.phone { fields["phone"] = trimmedPhone }
        if employmentType != savedBaseline.employmentType { fields["employmentType"] = employmentType.rawValue }
        if status != savedBaseline.status, user.status != .locked { fields["status"] = status.rawValue }

        let startKey = dateKey(startDate)
        if startKey != savedBaseline.startDateKey { fields["startDate"] = startKey ?? "" }
        let dobKeyValue = dateKey(dob)
        if dobKeyValue != savedBaseline.dobKey { fields["dob"] = dobKeyValue ?? "" }

        let trimmedEmergencyName = emergencyName.trimmingCharacters(in: .whitespaces)
        if trimmedEmergencyName != savedBaseline.emergencyName {
            fields["emergencyContactName"] = trimmedEmergencyName
            fields["emergencyContact"] = trimmedEmergencyName
        }
        let trimmedEmergencyPhone = emergencyPhone.trimmingCharacters(in: .whitespaces)
        if trimmedEmergencyPhone != savedBaseline.emergencyPhone { fields["emergencyContactPhone"] = trimmedEmergencyPhone }
        let trimmedEmergencyAddress = emergencyAddress.trimmingCharacters(in: .whitespaces)
        if trimmedEmergencyAddress != savedBaseline.emergencyAddress { fields["emergencyContactAddress"] = trimmedEmergencyAddress }
        if trimmedEmail != savedBaseline.emergencyEmail { fields["emergencyContactEmail"] = trimmedEmail }

        guard !fields.isEmpty else {
            isEditMode = false
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await repo.updateStaffFields(staffId: user.id, fields)
                fullName = trimmedName
                phone = trimmedPhone
                emergencyName = trimmedEmergencyName
                emergencyPhone = trimmedEmergencyPhone
                emergencyAddress = trimmedEmergencyAddress
                emergencyEmail = trimmedEmail
                savedBaseline = currentBaseline
                isEditMode = false
                Haptics.success()
                toast = ToastMessage(kind: .success, text: "Staff details saved.")
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func requestEmailChange() {
        Task {
            do {
                try await repo.requestStaffEmailChange(staffId: user.id)
                emailRequested = true
                Haptics.success()
                toast = ToastMessage(kind: .success, text: "\(user.firstName) will be asked to update their email.")
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't request. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func cancelEmailRequest() {
        Task {
            do {
                try await repo.cancelStaffEmailChange(staffId: user.id)
                emailRequested = false
                Haptics.light()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't cancel. \(error.localizedDescription)")
            }
        }
    }

    private func requireAddress() {
        Task {
            do {
                try await repo.requestStaffAddressUpdate(staffId: user.id)
                Haptics.success()
                dismiss()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't update. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}

// MARK: - Per-staff wage assignment (manager-only)

/// Assign an award, classification level, and earnings lines to a staff
/// member. Stored in the manager-only `wages` collection, never on the user
/// doc — staff cannot see any of this.
struct StaffWageAssignmentSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss
    let user: AppUser

    @State private var awardId: String = ""
    @State private var classificationLevel: String = ""
    @State private var selectedLineIds: Set<String> = []
    @State private var employmentType: String = ""
    @State private var ageGroup: String = ""
    @State private var rateOverrideText: String = ""
    @State private var effectiveDate: Date = RosterCalendar.startOfDay(Date())
    @State private var hasEffectiveDate = false
    @State private var superEnabled = true
    @State private var superRateText = ""
    @State private var active = true
    @State private var isSaving = false
    @State private var toast: ToastMessage?
    @State private var seeded = false

    private var selectedAward: WageAward? {
        repo.wageAwards.first { $0.id == awardId }
    }

    /// Classification levels for the selected award (earnings lines first, legacy award fallback).
    private var classificationOptions: [(level: String, label: String)] {
        let lines = repo.earningsLines.filter {
            $0.isClassificationLevel && ($0.active || $0.level == classificationLevel)
                && ($0.awardId == awardId || (awardId.isEmpty && $0.awardId == nil))
        }
        if !lines.isEmpty {
            return lines.map { line in
                (level: line.level, label: line.rateSummary.isEmpty
                    ? line.classificationTitle
                    : "\(line.classificationTitle) (\(line.rateSummary))")
            }
        }
        return (selectedAward?.classifications ?? []).map { classification in
            let rateLabel = classification.weekendHourlyRate > 0
                ? String(format: "$%.2f M–F · $%.2f Wknd/PH", classification.baseHourlyRate, classification.weekendHourlyRate)
                : String(format: "$%.2f/h", classification.baseHourlyRate)
            return (level: classification.level, label: "\(classification.title) (\(rateLabel))")
        }
    }

    /// Overtime, allowances, and other non-classification pay items.
    private var supplementalLines: [EarningsLine] {
        repo.earningsLines.filter {
            ($0.active || selectedLineIds.contains($0.id)) && !$0.isClassificationLevel
        }
    }

    private func classificationLineId(for level: String) -> String? {
        repo.earningsLines.first {
            $0.isClassificationLevel && $0.level == level
                && ($0.awardId == awardId || (awardId.isEmpty && $0.awardId == nil))
        }?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Award") {
                    Picker("Wage award", selection: $awardId) {
                        Text("None").tag("")
                        ForEach(repo.wageAwards.filter { $0.active || $0.id == awardId }) { award in
                            Text(award.code.isEmpty ? award.name : "\(award.name) (\(award.code))").tag(award.id)
                        }
                    }
                    if !classificationOptions.isEmpty {
                        Picker("Classification", selection: $classificationLevel) {
                            Text("None").tag("")
                            ForEach(classificationOptions, id: \.level) { option in
                                Text(option.label).tag(option.level)
                            }
                        }
                        .onChange(of: classificationLevel) { _, newLevel in
                            guard !newLevel.isEmpty, let lineId = classificationLineId(for: newLevel) else { return }
                            selectedLineIds.insert(lineId)
                        }
                    } else if awardId.isEmpty == false {
                        Text("No classification levels for this award — add them in Wage → Classification Levels.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section {
                    Picker("Employment type", selection: $employmentType) {
                        Text("From staff profile").tag("")
                        ForEach(EmploymentType.allCases, id: \.rawValue) { type in
                            Text(type.label).tag(type.rawValue)
                        }
                    }
                    LabeledContent("Age group") {
                        TextField("e.g. Under 18, Adult", text: $ageGroup)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Rate override ($/h)") {
                        TextField("Award rate", text: $rateOverrideText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    Toggle("Effective date", isOn: $hasEffectiveDate.animation())
                        .tint(Theme.brand)
                    if hasEffectiveDate {
                        DatePicker("Effective from", selection: $effectiveDate, displayedComponents: .date)
                            .environment(\.timeZone, RosterCalendar.timeZone)
                    }
                    Toggle("Active", isOn: $active)
                        .tint(Theme.brand)
                } header: {
                    Text("Payroll settings")
                } footer: {
                    Text("A rate override replaces the classification level rate. Inactive assignments are skipped by automatic draft payslip generation. Changes only affect future payroll — already generated payslips keep their snapshot.")
                }

                Section {
                    Toggle("Superannuation", isOn: $superEnabled.animation())
                        .tint(Theme.brand)
                    if superEnabled {
                        LabeledContent("Super guarantee (%)") {
                            TextField(String(format: "%g", user.superRate ?? 12), text: $superRateText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 80)
                        }
                    }
                } header: {
                    Text("Superannuation")
                } footer: {
                    Text(superEnabled
                         ? "Leave the percentage empty to use the default (\(String(format: "%g", user.superRate ?? 12))%). New payslips use this rate."
                         : "Super is OFF — e.g. staff under 18 working 30 hours or less per week are not entitled to super guarantee. New payslips will show no superannuation.")
                }

                Section {
                    if supplementalLines.isEmpty {
                        Text("No additional pay items — add overtime or allowances in Wage → Classification Levels if needed.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(supplementalLines) { line in
                            Toggle(isOn: Binding(
                                get: { selectedLineIds.contains(line.id) },
                                set: { on in
                                    if on { selectedLineIds.insert(line.id) } else { selectedLineIds.remove(line.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.name).font(.subheadline)
                                    Text("\(line.category.label) · \(line.rateSummary)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .tint(Theme.brand)
                        }
                    }
                } header: {
                    Text("Additional pay items")
                } footer: {
                    Text("Optional overtime multipliers, allowances, or bonuses — assigned alongside the classification level above.")
                }
            }
            .navigationTitle("Wage Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
            .toast($toast)
            .onAppear { seedIfNeeded() }
        }
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        if let profile = repo.staffWageProfile(for: user.id) {
            awardId = profile.awardId ?? ""
            classificationLevel = profile.classificationLevel ?? ""
            selectedLineIds = Set(profile.earningsLineIds)
            employmentType = profile.employmentType ?? ""
            ageGroup = profile.ageGroup ?? ""
            if let override = profile.hourlyRateOverride, override > 0 {
                rateOverrideText = String(format: "%.2f", override)
            }
            if let effective = profile.effectiveDate,
               let date = RosterCalendar.dateFromKey(effective) {
                hasEffectiveDate = true
                effectiveDate = date
            }
            superEnabled = profile.superEnabled
            if let rate = profile.superRate, rate > 0 {
                superRateText = String(format: "%g", rate)
            }
            active = profile.active
        } else if let userType = user.employmentType {
            employmentType = userType.rawValue
        }
    }

    private func save() {
        isSaving = true
        let override = Double(rateOverrideText)
        var lineIds = selectedLineIds
        if !classificationLevel.isEmpty, let lineId = classificationLineId(for: classificationLevel) {
            lineIds.insert(lineId)
        }
        let profile = StaffWageProfile(
            staffId: user.id,
            awardId: awardId.isEmpty ? nil : awardId,
            classificationLevel: classificationLevel.isEmpty ? nil : classificationLevel,
            earningsLineIds: Array(lineIds),
            hourlyRateOverride: (override ?? 0) > 0 ? override : nil,
            employmentType: employmentType.isEmpty ? nil : employmentType,
            ageGroup: ageGroup.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ageGroup.trimmingCharacters(in: .whitespaces),
            effectiveDate: hasEffectiveDate ? RosterCalendar.dayFormatter.string(from: effectiveDate) : nil,
            superEnabled: superEnabled,
            superRate: (Double(superRateText) ?? 0) > 0 ? Double(superRateText) : nil,
            active: active
        )
        Task {
            defer { isSaving = false }
            do {
                try await repo.saveStaffWageProfile(profile)
                Haptics.success()
                dismiss()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}

#Preview {
    ManagerStaffView()
        .environment(RosterRepository())
}
