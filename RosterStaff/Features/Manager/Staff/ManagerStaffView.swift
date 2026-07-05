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
        .searchable(text: $searchText, prompt: "Search name or email")
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

    private enum Field: Hashable { case name, phone, employment, superRate }

    @State private var fullName: String
    @State private var phone: String
    @State private var employmentType: EmploymentType
    @State private var superRateText: String
    @State private var unlocked: Set<Field> = []
    @State private var savingField: Field?
    @State private var emailRequested: Bool
    @State private var showAddressConfirm = false
    @State private var showWageAssignment = false
    @State private var toast: ToastMessage?

    init(user: AppUser) {
        self.user = user
        _fullName = State(initialValue: user.fullName)
        _phone = State(initialValue: user.phone ?? "")
        _employmentType = State(initialValue: user.employmentType ?? .casual)
        _superRateText = State(initialValue: user.superRate.map { String(format: "%g", $0) } ?? "")
        _emailRequested = State(initialValue: user.emailChangeRequired)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    textRow(.name, label: "Full name", text: $fullName)
                    textRow(.phone, label: "Phone", text: $phone, keyboard: .phonePad)
                    employmentRow
                } header: {
                    Text("Details")
                } footer: {
                    Text("Tap the pencil to edit a field, then the checkmark to save it.")
                }

                emailSection

                Section("Address") {
                    Text(user.address?.isEmpty == false ? user.address! : "No address on file")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        showAddressConfirm = true
                    } label: {
                        Label("Require new address on next login", systemImage: "house.badge.exclamationmark")
                            .foregroundStyle(Theme.warning)
                    }
                }

                // Manager-only pay settings. Earnings-line assignments live in
                // the `wages` collection (staff can't read it); the super %
                // sits on the user doc but is never rendered in the staff UI.
                Section {
                    superRateRow
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
                    Text("Award, classification and earnings lines are only visible to managers. Set up awards and lines in the Wage tab first.")
                }

                Section("Record") {
                    infoRow("Status", user.status.rawValue.capitalized)
                    infoRow("Hourly rate", user.hourlyRate.map { String(format: "$%.2f", $0) } ?? "—")
                    infoRow("Member since", user.memberSince ?? "—")
                    infoRow("Start date", user.startDate ?? "—")
                    infoRow("Date of birth", user.dob ?? "—")
                    infoRow("Emergency", user.emergencyContact ?? "—")
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

    // MARK: - Rows (locked by default; pencil unlocks a single field)

    private func textRow(_ field: Field, label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if unlocked.contains(field) {
                TextField(label, text: text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(field == .name ? .words : .never)
                    .foregroundStyle(Theme.textPrimary)
                commitButton(field)
            } else {
                Text(text.wrappedValue.isEmpty ? "—" : text.wrappedValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                editButton(field)
            }
        }
    }

    private var superRateRow: some View {
        HStack {
            Text("Superannuation")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if unlocked.contains(.superRate) {
                TextField("12", text: $superRateText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .foregroundStyle(Theme.textPrimary)
                Text("%").foregroundStyle(Theme.textSecondary)
                commitButton(.superRate)
            } else {
                Text(superRateText.isEmpty ? "—" : "\(superRateText)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                editButton(.superRate)
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
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    private var employmentRow: some View {
        HStack {
            Text("Employment")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if unlocked.contains(.employment) {
                Picker("", selection: $employmentType) {
                    ForEach(EmploymentType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .labelsHidden()
                commitButton(.employment)
            } else {
                Text(employmentType.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                editButton(.employment)
            }
        }
    }

    // Email is a sign-in credential, so the manager only *requests* a change;
    // the staff member changes their own email via Firebase's verified flow.
    private var emailSection: some View {
        Section {
            infoRow("Email", user.email)
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

    private func editButton(_ field: Field) -> some View {
        Button {
            unlocked.insert(field)
            Haptics.selection()
        } label: {
            Image(systemName: "pencil")
                .font(.footnote)
                .foregroundStyle(Theme.brand)
                .padding(.leading, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(String(describing: field))")
    }

    private func commitButton(_ field: Field) -> some View {
        Button {
            commit(field)
        } label: {
            if savingField == field {
                ProgressView()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
        }
        .buttonStyle(.plain)
        .disabled(savingField != nil)
        .padding(.leading, 6)
        .accessibilityLabel("Save \(String(describing: field))")
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func commit(_ field: Field) {
        let key: String
        let value: Any
        switch field {
        case .name:
            let trimmed = fullName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                toast = ToastMessage(kind: .error, text: "Name can't be empty.")
                Haptics.error()
                return
            }
            key = "fullName"; value = trimmed
        case .phone:
            key = "phone"; value = phone.trimmingCharacters(in: .whitespaces)
        case .employment:
            key = "employmentType"; value = employmentType.rawValue
        case .superRate:
            let trimmed = superRateText.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty || Double(trimmed) != nil else {
                toast = ToastMessage(kind: .error, text: "Super must be a number (e.g. 12).")
                Haptics.error()
                return
            }
            key = "superRate"; value = Double(trimmed).map { $0 as Any } ?? NSNull()
        }
        savingField = field
        Task {
            defer { savingField = nil }
            do {
                try await repo.updateStaffFields(staffId: user.id, [key: value])
                unlocked.remove(field)
                Haptics.success()
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
    @State private var isSaving = false
    @State private var toast: ToastMessage?
    @State private var seeded = false

    private var selectedAward: WageAward? {
        repo.wageAwards.first { $0.id == awardId }
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
                    if let award = selectedAward, !award.classifications.isEmpty {
                        Picker("Classification", selection: $classificationLevel) {
                            Text("None").tag("")
                            ForEach(award.classifications) { classification in
                                Text("L\(classification.level) — \(classification.title) ($\(String(format: "%.2f", classification.baseHourlyRate))/h)")
                                    .tag(classification.level)
                            }
                        }
                    }
                }

                Section {
                    if repo.earningsLines.isEmpty {
                        Text("No earnings lines yet — create them in the Wage tab first.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(repo.earningsLines.filter { $0.active || selectedLineIds.contains($0.id) }) { line in
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
                    Text("Earnings lines")
                } footer: {
                    Text("Only managers can see these. They'll drive \(user.firstName)'s payroll calculations in the upcoming Wages/Payslip features.")
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
        }
    }

    private func save() {
        isSaving = true
        let profile = StaffWageProfile(
            staffId: user.id,
            awardId: awardId.isEmpty ? nil : awardId,
            classificationLevel: classificationLevel.isEmpty ? nil : classificationLevel,
            earningsLineIds: Array(selectedLineIds)
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
