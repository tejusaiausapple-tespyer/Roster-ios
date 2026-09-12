import SwiftUI

struct ManagerShiftEditorSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss
    
    let shift: Shift?
    let defaultDateKey: String
    
    /// Roles offered in the dropdown (replaces the old free-text field).
    static let roleOptions = ["Console Operator", "Junior Attendee"]

    @State private var selectedStaffId: String = ""
    @State private var date: Date = Date()
    @State private var startDateTime: Date = Date()
    @State private var endDateTime: Date = Date()
    @State private var breakMinutes: Int = 0 // default: No break
    @State private var location: String = ""
    @State private var department: String = ManagerShiftEditorSheet.roleOptions.first ?? ""
    @State private var notes: String = ""
    @State private var isPublished: Bool = false

    // Inline "add location" form state
    @State private var showAddLocation = false
    @State private var newSuburb: String = ""
    @State private var newState: String = "SA"
    @State private var newCity: String = RosterLocation.capital(for: "SA")
    @State private var isSavingLocation = false

    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var showDeleteConfirm = false
    @State private var showConflictConfirm = false

    private var staffMembers: [AppUser] {
        repo.allUsers.filter { $0.role == .staff }
    }

    private var dateKey: String { RosterCalendar.dayFormatter.string(from: date) }

    /// Every staff member graded against the shift *as currently configured* —
    /// recomputed as the date and the start/end times change, best fit first.
    /// This is what removes the trip to the Availability tab: it answers "who
    /// can actually work this slot", not just "who ticked this weekday".
    private var staffFits: [StaffShiftFit] {
        ShiftFit.fits(
            staff: staffMembers,
            dateKey: dateKey,
            start: RosterFormat.hhmm(startDateTime),
            end: RosterFormat.hhmm(endDateTime),
            shifts: repo.shifts,
            excluding: shift?.id
        )
    }

    private var selectedFit: StaffShiftFit? {
        staffFits.first { $0.user.id == selectedStaffId }
    }

    private var freeCount: Int {
        staffFits.filter { $0.verdict == .free }.count
    }

    /// Saved locations plus the shift's current value when it isn't in the
    /// saved list (so editing an old shift never silently changes it).
    private var locationOptions: [String] {
        var options = repo.locations.map { $0.displayName }
        if !location.isEmpty, !options.contains(location) {
            options.insert(location, at: 0)
        }
        return options
    }

    /// Role options plus the shift's existing value for legacy free-text data.
    private var roleOptions: [String] {
        var options = Self.roleOptions
        if !department.isEmpty, !options.contains(department) {
            options.insert(department, at: 0)
        }
        return options
    }
    
    init(shift: Shift? = nil, defaultDateKey: String) {
        self.shift = shift
        self.defaultDateKey = defaultDateKey
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Staff & Schedule") {
                    Picker("Staff Member", selection: $selectedStaffId) {
                        Text("Select Staff").tag("")
                        ForEach(staffMembers) { member in
                            Text(member.fullName).tag(member.id)
                        }
                    }
                    .onChange(of: selectedStaffId) { _, newId in
                        applyDefaultRole(forStaffId: newId)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, RosterCalendar.timeZone)

                    DatePicker("Start Time", selection: $startDateTime, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, RosterCalendar.timeZone)

                    DatePicker("End Time", selection: $endDateTime, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, RosterCalendar.timeZone)

                    availabilityRow
                }
                
                Section("Break & Role Details") {
                    Picker("Break Duration", selection: $breakMinutes) {
                        Text("No break").tag(0)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                        Text("60 minutes").tag(60)
                    }

                    Picker("Role", selection: $department) {
                        ForEach(roleOptions, id: \.self) { role in
                            Text(role).tag(role)
                        }
                    }
                }

                Section("Location") {
                    if locationOptions.isEmpty {
                        Text("No locations yet — add one below.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Picker("Location", selection: $location) {
                            ForEach(locationOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    }

                    if showAddLocation {
                        TextField("Suburb", text: $newSuburb)
                            .textInputAutocapitalization(.words)
                        Picker("State", selection: $newState) {
                            ForEach(RosterLocation.states, id: \.self) { state in
                                Text(state).tag(state)
                            }
                        }
                        .onChange(of: newState) { _, state in
                            newCity = RosterLocation.capital(for: state)
                        }
                        TextField("City", text: $newCity)
                            .textInputAutocapitalization(.words)
                        HStack {
                            Button("Cancel", role: .cancel) {
                                withAnimation { showAddLocation = false }
                            }
                            .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button {
                                saveNewLocation()
                            } label: {
                                if isSavingLocation {
                                    ProgressView()
                                } else {
                                    Text("Save Location").fontWeight(.semibold)
                                }
                            }
                            .disabled(newSuburb.trimmingCharacters(in: .whitespaces).isEmpty || isSavingLocation)
                        }
                    } else {
                        Button {
                            withAnimation { showAddLocation = true }
                        } label: {
                            Label("Add new location", systemImage: "plus.circle")
                        }
                    }
                }
                
                Section("Settings & Notes") {
                    Toggle("Publish Shift (Visible to Staff)", isOn: $isPublished)
                        .tint(Theme.brand)
                    
                    TextField("Shift Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                    .listRowBackground(Color.clear)
                }
                
                if shift != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Shift", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(shift == nil ? "New Shift" : "Edit Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveShift() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedStaffId.isEmpty || isSaving)
                }
            }
            .disabled(isSaving)
            .onAppear {
                setupInitialFields()
            }
            .alert("Delete shift?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteShift() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove this shift from the roster.")
            }
            .alert("Availability conflict", isPresented: $showConflictConfirm, presenting: selectedFit) { _ in
                Button("Roster anyway", role: .destructive) { performSave() }
                Button("Cancel", role: .cancel) {}
            } message: { fit in
                Text("\(fit.user.fullName) — \(fit.detail).")
            }
        }
    }
    
    // MARK: - Availability

    /// The "who can work this" row: a live count, graded chips, and — when the
    /// current pick has a problem — the reason, spelled out.
    private var availabilityRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Who can work this shift")
                    .styleCaptionStrong()
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Text("\(freeCount) free")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(freeCount == 0 ? Theme.warning : Theme.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(staffFits) { fit in
                        StaffFitChip(fit: fit, isSelected: fit.user.id == selectedStaffId) {
                            selectedStaffId = fit.user.id
                            applyDefaultRole(forStaffId: fit.user.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if let selectedFit, !selectedFit.isClean {
                conflictBanner(selectedFit)
            }
        }
        .padding(.vertical, 4)
    }

    private func conflictBanner(_ fit: StaffShiftFit) -> some View {
        let tint = fit.verdict.tint
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: fit.verdict.iconName)
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(fit.verdict.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(fit.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    // MARK: - Helpers

    private func setupInitialFields() {
        if let shift {
            selectedStaffId = shift.staffId
            date = RosterCalendar.dateFromKey(shift.date) ?? Date()
            
            // Align pickers with shift values
            startDateTime = BusinessRules.shiftStartDateTime(date: shift.date, time: shift.rosteredStart)
            endDateTime = BusinessRules.shiftEndDateTime(date: shift.date, start: shift.rosteredStart, end: shift.rosteredEnd)
            breakMinutes = shift.breakMinutes
            location = shift.location ?? ""
            department = (shift.department?.isEmpty == false) ? (shift.department ?? "") : (Self.roleOptions.first ?? "")
            notes = shift.notes ?? ""
            isPublished = shift.status == .published
        } else {
            // Default values for new shift
            let targetDate = RosterCalendar.dateFromKey(defaultDateKey) ?? Date()
            date = targetDate
            
            // Default shift: 09:00 to 17:00 in the business timezone
            // (Australia/Adelaide), so a manager on a travelling device still
            // seeds Adelaide-clock shifts.
            startDateTime = RosterCalendar.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: targetDate) ?? targetDate
            endDateTime = RosterCalendar.calendar.date(bySettingHour: 17, minute: 0, second: 0, of: targetDate) ?? targetDate
            
            if let firstStaff = staffMembers.first {
                selectedStaffId = firstStaff.id
                applyDefaultRole(forStaffId: firstStaff.id)
            }
            // Preselect the first saved location, if any (no seeded data).
            location = repo.locations.first?.displayName ?? ""
        }
    }

    /// Auto-fills Role from the selected staff member's saved default — only
    /// for a brand-new shift (an existing shift keeps its own department
    /// regardless of who it's reassigned to), and only when that staff
    /// member actually has a default set (a manager's already-chosen Role
    /// is never silently cleared by switching the staff picker).
    private func applyDefaultRole(forStaffId staffId: String) {
        guard shift == nil else { return }
        guard let dept = repo.user(id: staffId)?.defaultDepartment, !dept.isEmpty else { return }
        department = dept
    }

    private func saveNewLocation() {
        let suburb = newSuburb.trimmingCharacters(in: .whitespaces)
        guard !suburb.isEmpty else { return }
        let city = newCity.trimmingCharacters(in: .whitespaces)
        let newLocation = RosterLocation(suburb: suburb, state: newState,
                                         city: city.isEmpty ? nil : city)
        isSavingLocation = true
        Task {
            defer { isSavingLocation = false }
            do {
                try await repo.addLocation(newLocation)
                location = newLocation.displayName
                newSuburb = ""
                withAnimation { showAddLocation = false }
                Haptics.success()
            } catch {
                errorMessage = "Couldn't save location. \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }
    
    /// Rostering over a stated conflict is allowed — managers do it knowingly —
    /// but never silently: confirm first, then commit.
    private func saveShift() {
        if let selectedFit, !selectedFit.isClean {
            showConflictConfirm = true
            return
        }
        performSave()
    }

    private func performSave() {
        errorMessage = nil
        isSaving = true

        let dateKey = RosterCalendar.dayFormatter.string(from: date)
        
        // Serialize in the business timezone — pairs with the Adelaide-clock
        // seeding above so the round-trip is device-timezone-independent.
        let startTimeString = RosterFormat.hhmm(startDateTime)
        let endTimeString = RosterFormat.hhmm(endDateTime)
        
        // Validation: only reject a zero-duration shift. Comparing the raw
        // Start/End Dates would reject every overnight shift (e.g. 22:00 ->
        // 06:00), since the pickers only ever edit hour/minute and both
        // Dates share the same calendar day. The rest of the app (Business
        // Rules' shiftEndDateTime/calcWorkedHours, plus the roster grid's
        // drag-copy flow) already treats end <= start as "crosses midnight",
        // so match that convention here by comparing clock times, not Dates.
        if startTimeString == endTimeString {
            errorMessage = "Start and end time can't be the same."
            isSaving = false
            return
        }
        
        Task {
            do {
                try await repo.saveShift(
                    id: shift?.id,
                    staffId: selectedStaffId,
                    date: dateKey,
                    start: startTimeString,
                    end: endTimeString,
                    breakMinutes: breakMinutes,
                    location: location,
                    department: department,
                    notes: notes,
                    status: isPublished ? .published : .draft
                )
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
    
    private func deleteShift() {
        guard let shift = shift else { return }
        isSaving = true
        Task {
            do {
                try await repo.deleteShift(id: shift.id)
                Haptics.light()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

extension StaffShiftFit.Verdict {
    var iconName: String {
        switch self {
        case .free:         return "checkmark.circle.fill"
        case .secondShift:  return "clock.arrow.circlepath"
        case .outsideHours: return "clock.badge.exclamationmark"
        case .doubleBooked: return "calendar.badge.exclamationmark"
        case .unavailable:  return "xmark.circle.fill"
        }
    }

    var headline: String {
        switch self {
        case .free:         return "Available"
        case .secondShift:  return "Second shift today"
        case .outsideHours: return "Outside stated hours"
        case .doubleBooked: return "Double-booked"
        case .unavailable:  return "Unavailable"
        }
    }

    var tint: Color {
        switch self {
        case .free, .secondShift:       return Theme.accent
        case .outsideHours:             return Theme.warning
        case .doubleBooked, .unavailable: return Theme.error
        }
    }
}

/// One staff member in the editor's "who can work this shift" row. Carries the
/// verdict on its face (icon + short reason) so the manager doesn't have to
/// select someone to discover they don't fit. Tapping assigns them.
private struct StaffFitChip: View {
    let fit: StaffShiftFit
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let tint = fit.verdict.tint
        let outline = isSelected ? Theme.brand : tint

        return Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: fit.verdict.iconName)
                    .font(.caption2)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(fit.user.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(fit.shortLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.16 : 0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(outline.opacity(isSelected ? 0.9 : 0.28),
                                  lineWidth: isSelected ? 2 : 1)
            )
            // Unavailable/clashing staff stay tappable — a manager may still
            // need to roster them — but read as the last resort they are.
            .opacity(fit.isClean ? 1 : 0.75)
        }
        .buttonStyle(.plain)
        .pointerHover()
        .help("\(fit.verdict.headline) — \(fit.detail)")
        .accessibilityLabel("\(fit.user.fullName), \(fit.verdict.headline), \(fit.detail)")
    }
}