#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacShiftEditorModal: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    private let existingShift: Shift?

    @State private var staffId: String
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var breakMinutes: Int
    @State private var department: String
    @State private var location: String
    @State private var notes: String
    @State private var status: ShiftStatus
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(shift: Shift) {
        self.existingShift = shift
        let day = RosterCalendar.dateFromKey(shift.date) ?? Date()
        _staffId = State(initialValue: shift.staffId)
        _date = State(initialValue: day)
        _startTime = State(initialValue: Self.timeDate(shift.rosteredStart, on: day))
        _endTime = State(initialValue: Self.timeDate(shift.rosteredEnd, on: day))
        _breakMinutes = State(initialValue: shift.breakMinutes)
        _department = State(initialValue: shift.department ?? "")
        _location = State(initialValue: shift.location ?? "")
        _notes = State(initialValue: shift.notes ?? "")
        _status = State(initialValue: shift.status)
    }

    init(initialDate: String, initialStaffId: String? = nil) {
        self.existingShift = nil
        let day = RosterCalendar.dateFromKey(initialDate) ?? Date()
        _staffId = State(initialValue: initialStaffId ?? "")
        _date = State(initialValue: day)
        _startTime = State(initialValue: Self.timeDate("09:00", on: day))
        _endTime = State(initialValue: Self.timeDate("17:00", on: day))
        _breakMinutes = State(initialValue: 0)
        _department = State(initialValue: "")
        _location = State(initialValue: "")
        _notes = State(initialValue: "")
        _status = State(initialValue: .draft)
    }

    private var dateKey: String { RosterCalendar.dateString(from: date) }
    private var startHHmm: String { RosterFormat.hhmm(startTime) }
    private var endHHmm: String { RosterFormat.hhmm(endTime) }
    private var scheduledHours: Double {
        BusinessRules.calcWorkedHours(start: startHHmm, end: endHHmm, breakMinutes: breakMinutes)
    }

    private var staffMembers: [AppUser] {
        repo.staffMembers
            .filter { $0.status == .active || $0.id == staffId }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private var selectedStaff: AppUser? {
        staffMembers.first(where: { $0.id == staffId })
    }

    private var selectedStaffName: String {
        selectedStaff?.fullName ?? "Select staff"
    }

    private var locationOptions: [String] {
        var options = repo.locations.map(\.displayName)
        if !location.isEmpty, !options.contains(location) {
            options.insert(location, at: 0)
        }
        return options
    }

    private var roleOptions: [String] {
        var options = ManagerShiftEditorSheet.roleOptions
        if !department.isEmpty, !options.contains(department) {
            options.insert(department, at: 0)
        }
        return options
    }

    private var statusOptions: [ShiftStatus] {
        if status == .completed {
            return [.draft, .published, .completed, .cancelled]
        }
        return [.draft, .published, .cancelled]
    }

    private var breakOptions: [Int] {
        var options = [0, 15, 30, 45, 60]
        if !options.contains(breakMinutes) {
            options.append(breakMinutes)
            options.sort()
        }
        return options
    }

    private var weekDays: [Date] {
        RosterCalendar.weekDays(for: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                assignmentColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Divider()
                scheduleColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, MacSpace.xl)
            .padding(.vertical, MacSpace.lg)
            Divider()
            footer
        }
        .frame(width: 920)
        .background(MacColor.windowBackground)
        .alert("Delete this shift?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Shift", role: .destructive) {
                Task { await deleteExisting() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            if existingShift == nil {
                applyStaffDefaults(staffId)
            }
        }
        .onChange(of: date) { _, newDate in
            startTime = Self.replacingDay(of: startTime, with: newDate)
            endTime = Self.replacingDay(of: endTime, with: newDate)
        }
        .onChange(of: staffId) { _, newId in
            applyStaffDefaults(newId)
        }
    }

    private var header: some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: existingShift == nil ? "calendar.badge.plus" : "calendar.badge.clock")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MacColor.textPrimary)
                .frame(width: 42, height: 42)
                .macGlassSurface(cornerRadius: MacRadius.medium)

            VStack(alignment: .leading, spacing: 2) {
                Text(existingShift != nil ? "Edit shift" : "Create shift")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Text("\(selectedStaffName) · \(RosterFormat.date(dateKey))")
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                Text(RosterFormat.hours(scheduledHours))
                    .font(MacType.monoLarge)
            }
            .foregroundStyle(scheduledHours > 0 ? MacColor.textPrimary : MacColor.error)
            .padding(.horizontal, MacSpace.md)
            .frame(minHeight: 42)
            .macGlassSurface(cornerRadius: MacRadius.medium)
            .accessibilityLabel("Rostered hours")
            .accessibilityValue(RosterFormat.hours(scheduledHours))

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .macGlassSurface(cornerRadius: MacRadius.pill)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
    }

    private var assignmentColumn: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.error)
                    .padding(MacSpace.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        MacColor.error.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                    )
            }

            fieldLabel("Staff member")
            Menu {
                ForEach(staffMembers) { staff in
                    Button {
                        staffId = staff.id
                    } label: {
                        Text(staff.fullName)
                    }
                }
            } label: {
                HStack(spacing: MacSpace.md) {
                    MacAvatar(name: selectedStaffName, size: 36)
                    Text(selectedStaffName)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MacColor.textTertiary)
                }
                .padding(.horizontal, MacSpace.md)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(
                    MacColor.cardBackground,
                    in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                        .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)

            fieldLabel("Shift status")
            chipRow(statusOptions, id: \.self, selection: status) { option in
                Button {
                    status = option
                } label: {
                    Text(option.rawValue.capitalized)
                }
            }

            fieldLabel("Role")
            Menu {
                Button("No role") { department = "" }
                if !roleOptions.isEmpty { Divider() }
                ForEach(roleOptions, id: \.self) { role in
                    Button(role) { department = role }
                }
            } label: {
                pickerValue(department.isEmpty ? "Optional" : department)
            }
            .menuStyle(.borderlessButton)

            fieldLabel("Location")
            Menu {
                Button("No location") { location = "" }
                if !locationOptions.isEmpty { Divider() }
                ForEach(locationOptions, id: \.self) { name in
                    Button(name) { location = name }
                }
            } label: {
                pickerValue(location.isEmpty ? "No location" : location)
            }
            .menuStyle(.borderlessButton)

            fieldLabel("Notes")
            TextField("Optional shift notes", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
        }
        .padding(.trailing, MacSpace.lg)
    }

    private var scheduleColumn: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            fieldLabel("Date")
            HStack(spacing: MacSpace.sm) {
                Button {
                    date = RosterCalendar.addDays(-1, to: date)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .macButton(.bordered, size: .small)
                .accessibilityLabel("Previous day")

                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.large)
                    .environment(\.timeZone, RosterCalendar.timeZone)

                Button {
                    date = RosterCalendar.addDays(1, to: date)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .macButton(.bordered, size: .small)
                .accessibilityLabel("Next day")

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    let selected = RosterCalendar.calendar.isDate(day, inSameDayAs: date)
                    Button {
                        date = day
                    } label: {
                        VStack(spacing: 2) {
                            Text(weekdayShort(day))
                                .font(MacType.badge)
                            Text(dayNumber(day))
                                .font(MacType.bodyStrong)
                        }
                        .foregroundStyle(selected ? Color.white : MacColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selected ? MacColor.brandStrong : MacColor.cardBackground,
                            in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                                .strokeBorder(selected ? Color.clear : MacColor.cardBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RosterFormat.date(RosterCalendar.dateString(from: day)))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            HStack(alignment: .top, spacing: MacSpace.md) {
                VStack(alignment: .leading, spacing: MacSpace.sm) {
                    fieldLabel("Starts")
                    MacShiftTimeControl(selection: $startTime)
                }
                VStack(alignment: .leading, spacing: MacSpace.sm) {
                    fieldLabel("Ends")
                    MacShiftTimeControl(selection: $endTime)
                }
            }

            fieldLabel("Unpaid break")
            chipRow(breakOptions, id: \.self, selection: breakMinutes) { minutes in
                Button {
                    breakMinutes = minutes
                } label: {
                    Text(minutes == 0 ? "None" : "\(minutes)m")
                }
            }
        }
        .padding(.leading, MacSpace.lg)
    }

    private var footer: some View {
        HStack(spacing: MacSpace.md) {
            if existingShift != nil {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete shift", systemImage: "trash")
                }
                .macButton(.destructive)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .macButton(.bordered)
                .keyboardShortcut(.cancelAction)

            MacAsyncButton(variant: .prominent) {
                await saveShift()
            } label: {
                Text(existingShift != nil ? "Save changes" : "Create shift")
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, MacSpace.xl)
        .padding(.vertical, MacSpace.lg)
        .background(.bar)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(MacType.captionStrong)
            .foregroundStyle(MacColor.textTertiary)
    }

    private func pickerValue(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(MacType.body)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MacColor.textTertiary)
        }
        .padding(.horizontal, MacSpace.md)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            MacColor.cardBackground,
            in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func chipRow<Data: RandomAccessCollection, ID: Hashable, Content: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: ID,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Hashable {
        HStack(spacing: 6) {
            ForEach(data, id: id) { item in
                let isSelected = item[keyPath: id] == selection
                content(item)
                    .font(MacType.captionStrong)
                    .foregroundStyle(isSelected ? Color.white : MacColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(
                        isSelected ? MacColor.brandStrong : MacColor.cardBackground,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(isSelected ? Color.clear : MacColor.cardBorder, lineWidth: 1)
                    }
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func weekdayShort(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = RosterCalendar.calendar
        formatter.timeZone = RosterCalendar.timeZone
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "EEE"
        return formatter.string(from: day)
    }

    private func dayNumber(_ day: Date) -> String {
        "\(RosterCalendar.calendar.component(.day, from: day))"
    }

    private func applyStaffDefaults(_ id: String) {
        guard let user = repo.user(id: id) else { return }
        if department.isEmpty, let role = user.defaultDepartment, !role.isEmpty {
            department = role
        }
        if location.isEmpty, let loc = user.defaultLocation, !loc.isEmpty {
            location = loc
        }
    }

    private func saveShift() async {
        guard !staffId.isEmpty else {
            errorMessage = "Please select a staff member."
            return
        }
        guard scheduledHours > 0 else {
            errorMessage = "End time must be after start time."
            return
        }

        do {
            try await repo.saveShift(
                id: existingShift?.id,
                staffId: staffId,
                date: dateKey,
                start: startHHmm,
                end: endHHmm,
                breakMinutes: breakMinutes,
                location: location.isEmpty ? nil : location,
                department: department.isEmpty ? nil : department,
                notes: notes.isEmpty ? nil : notes,
                status: status
            )
            toasts.show(existingShift != nil ? "Shift updated" : "Shift created", style: .success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteExisting() async {
        guard let existingShift else { return }
        do {
            try await repo.deleteShift(existingShift.id)
            toasts.show("Shift deleted", style: .info)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func timeDate(_ hhmm: String, on day: Date) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var comps = RosterCalendar.calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = parts.first ?? 9
        comps.minute = parts.count > 1 ? parts[1] : 0
        comps.timeZone = RosterCalendar.timeZone
        return RosterCalendar.calendar.date(from: comps) ?? day
    }

    private static func replacingDay(of time: Date, with day: Date) -> Date {
        var comps = RosterCalendar.calendar.dateComponents([.hour, .minute], from: time)
        let dayComps = RosterCalendar.calendar.dateComponents([.year, .month, .day], from: day)
        comps.year = dayComps.year
        comps.month = dayComps.month
        comps.day = dayComps.day
        comps.timeZone = RosterCalendar.timeZone
        return RosterCalendar.calendar.date(from: comps) ?? time
    }
}

private struct MacShiftTimeControl: View {
    @Binding var selection: Date

    private var hour24: Int {
        RosterCalendar.calendar.component(.hour, from: selection)
    }

    private var hour12: Int {
        hour24 % 12 == 0 ? 12 : hour24 % 12
    }

    private var minute: Int {
        RosterCalendar.calendar.component(.minute, from: selection)
    }

    private var isPM: Bool { hour24 >= 12 }

    var body: some View {
        HStack(spacing: 6) {
            column(
                value: "\(hour12)",
                accessibilityLabel: "Hour",
                increment: { adjust(minutes: 60) },
                decrement: { adjust(minutes: -60) }
            ) {
                ForEach(1...12, id: \.self) { hour in
                    Button("\(hour)") { setHour12(hour) }
                }
            }

            Text(":")
                .font(MacType.monoLarge)
                .foregroundStyle(MacColor.textSecondary)
                .padding(.bottom, 2)

            column(
                value: String(format: "%02d", minute),
                accessibilityLabel: "Minute",
                increment: { stepMinutes(1) },
                decrement: { stepMinutes(-1) }
            ) {
                ForEach([0, 15, 30, 45], id: \.self) { value in
                    Button(String(format: "%02d", value)) { setMinute(value) }
                }
            }

            column(
                value: isPM ? "PM" : "AM",
                accessibilityLabel: "AM or PM",
                increment: { adjust(minutes: 12 * 60) },
                decrement: { adjust(minutes: -12 * 60) }
            ) {
                Button("AM") { setPM(false) }
                Button("PM") { setPM(true) }
            }
        }
        .padding(.horizontal, MacSpace.sm)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            MacColor.cardBackground,
            in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        }
    }

    private func column<MenuContent: View>(
        value: String,
        accessibilityLabel: String,
        increment: @escaping () -> Void,
        decrement: @escaping () -> Void,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        VStack(spacing: 2) {
            Button(action: increment) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase \(accessibilityLabel)")

            Menu(content: menu) {
                Text(value)
                    .font(MacType.monoLarge)
                    .foregroundStyle(MacColor.textPrimary)
                    .frame(width: 56, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(value)

            Button(action: decrement) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease \(accessibilityLabel)")
        }
        .foregroundStyle(MacColor.textSecondary)
        .frame(maxWidth: .infinity)
    }

    private func adjust(minutes: Int) {
        selection = RosterCalendar.calendar.date(
            byAdding: .minute,
            value: minutes,
            to: selection
        ) ?? selection
    }

    private func stepMinutes(_ direction: Int) {
        let current = minute
        let delta: Int
        if direction > 0 {
            delta = ((current / 15) + 1) * 15 - current
        } else if current % 15 == 0 {
            delta = -15
        } else {
            delta = (current / 15) * 15 - current
        }
        adjust(minutes: delta)
    }

    private func setHour12(_ hour: Int) {
        let hour24 = (hour % 12) + (isPM ? 12 : 0)
        set(hour: hour24, minute: minute)
    }

    private func setMinute(_ value: Int) {
        set(hour: hour24, minute: value)
    }

    private func setPM(_ pm: Bool) {
        var hour = hour24
        if pm, hour < 12 { hour += 12 }
        if !pm, hour >= 12 { hour -= 12 }
        set(hour: hour, minute: minute)
    }

    private func set(hour: Int, minute: Int) {
        var comps = RosterCalendar.calendar.dateComponents(
            [.year, .month, .day],
            from: selection
        )
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        comps.timeZone = RosterCalendar.timeZone
        selection = RosterCalendar.calendar.date(from: comps) ?? selection
    }
}
#endif
