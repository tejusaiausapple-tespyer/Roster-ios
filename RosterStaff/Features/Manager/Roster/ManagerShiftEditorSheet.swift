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
    @State private var department: String = ManagerShiftEditorSheet.roleOptions[0]
    @State private var notes: String = ""
    @State private var isPublished: Bool = true

    // Inline "add location" form state
    @State private var showAddLocation = false
    @State private var newSuburb: String = ""
    @State private var newState: String = "SA"
    @State private var newCity: String = RosterLocation.capital(for: "SA")
    @State private var isSavingLocation = false

    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var showDeleteConfirm = false

    private var staffMembers: [AppUser] {
        repo.allUsers.filter { $0.role == .staff }
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
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    
                    DatePicker("Start Time", selection: $startDateTime, displayedComponents: .hourAndMinute)
                    
                    DatePicker("End Time", selection: $endDateTime, displayedComponents: .hourAndMinute)
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveShift() }
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
        }
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
            department = (shift.department?.isEmpty == false) ? shift.department! : Self.roleOptions[0]
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
            }
            // Preselect the first saved location, if any (no seeded data).
            location = repo.locations.first?.displayName ?? ""
        }
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
    
    private func saveShift() {
        errorMessage = nil
        isSaving = true
        
        let dateKey = RosterCalendar.dayFormatter.string(from: date)
        
        // Serialize in the business timezone — pairs with the Adelaide-clock
        // seeding above so the round-trip is device-timezone-independent.
        let startTimeString = RosterFormat.hhmm(startDateTime)
        let endTimeString = RosterFormat.hhmm(endDateTime)
        
        // Validation: end must be after start
        if startDateTime >= endDateTime {
            errorMessage = "End time must be after start time."
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