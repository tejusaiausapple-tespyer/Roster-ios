import SwiftUI

struct ManagerShiftEditorSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss
    
    let shift: Shift?
    let defaultDateKey: String
    
    @State private var selectedStaffId: String = ""
    @State private var date: Date = Date()
    @State private var startDateTime: Date = Date()
    @State private var endDateTime: Date = Date()
    @State private var breakMinutes: Int = 30
    @State private var location: String = "Melbourne HQ"
    @State private var department: String = "Sales"
    @State private var notes: String = ""
    @State private var isPublished: Bool = true
    
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var showDeleteConfirm = false
    
    private var staffMembers: [AppUser] {
        repo.allUsers.filter { $0.role == .staff }
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
                    
                    TextField("Role / Department", text: $department)
                    
                    Picker("Location", selection: $location) {
                        Text("Melbourne HQ").tag("Melbourne HQ")
                        Text("Sydney HQ").tag("Sydney HQ")
                        Text("Brisbane Branch").tag("Brisbane Branch")
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
            location = shift.location ?? "Melbourne HQ"
            department = shift.department ?? "Sales"
            notes = shift.notes ?? ""
            isPublished = shift.status == .published
        } else {
            // Default values for new shift
            let targetDate = RosterCalendar.dateFromKey(defaultDateKey) ?? Date()
            date = targetDate
            
            // Default shift: 09:00 to 17:00
            // NOTE: uses device-local `Calendar.current` to seed the default
            // start/end times. The date is unaffected, but if we later want the
            // default times to be strictly Australia/Adelaide-consistent (e.g.
            // for users travelling / non-Adelaide devices), switch these two
            // lines to `RosterCalendar.calendar`. Left as-is for now per product.
            startDateTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: targetDate) ?? targetDate
            endDateTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: targetDate) ?? targetDate
            
            if let firstStaff = staffMembers.first {
                selectedStaffId = firstStaff.id
            }
        }
    }
    
    private func saveShift() {
        errorMessage = nil
        isSaving = true
        
        let dateKey = RosterCalendar.dayFormatter.string(from: date)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let startTimeString = timeFormatter.string(from: startDateTime)
        let endTimeString = timeFormatter.string(from: endDateTime)
        
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