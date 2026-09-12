#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacStaffRosterView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var currentWeekStart: Date = RosterCalendar.startOfWeek(for: Date())
    @State private var submittingShift: Shift?
    @State private var absentShift: Shift?

    init() {}

    private var currentUserId: String {
        repo.currentUser?.id ?? ""
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: currentWeekStart) }
    }

    private var staffShifts: [Shift] {
        let weekDates = Set(weekDays.map { RosterCalendar.dateString(from: $0) })
        return repo.shifts.filter { $0.staffId == currentUserId && weekDates.contains($0.date) }
    }

    var body: some View {
        MacScreen(
            title: "My Roster",
            subtitle: "\(RosterCalendar.formatDateRange(start: currentWeekStart, end: weekDays.last ?? currentWeekStart))",
            actions: {
                HStack(spacing: MacSpace.sm) {
                    Button {
                        if let prev = Calendar.current.date(byAdding: .day, value: -7, to: currentWeekStart) {
                            currentWeekStart = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .macButton(.bordered, size: .small)

                    Button("Today") {
                        currentWeekStart = RosterCalendar.startOfWeek(for: Date())
                    }
                    .macButton(.bordered, size: .small)

                    Button {
                        if let next = Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart) {
                            currentWeekStart = next
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .macButton(.bordered, size: .small)
                }
            }
        ) {
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: MacSpace.xl) {
                    // Week Summary Bar
                    HStack(spacing: MacSpace.lg) {
                        MacStatCard(
                            title: "Total Shifts",
                            value: "\(staffShifts.count)",
                            subtitle: "Scheduled shifts this week",
                            icon: "calendar",
                            tint: MacColor.accent
                        )

                        let totalHours = staffShifts.reduce(0.0) { $0 + $1.durationHours }
                        MacStatCard(
                            title: "Rostered Hours",
                            value: String(format: "%.1fh", totalHours),
                            subtitle: "Regular working hours",
                            icon: "clock.fill",
                            tint: MacColor.info
                        )
                    }

                    // 7-Day Columns
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: MacSpace.md), count: 7), spacing: MacSpace.md) {
                        ForEach(weekDays, id: \.self) { day in
                            dayColumn(for: day)
                        }
                    }
                }
                .padding(MacSpace.xl)
                .frame(minWidth: 880)
            }
        }
        .sheet(item: $submittingShift) { shift in
            MacSubmitHoursSheet(shift: shift)
                .macObserved(repo: repo, toasts: toasts)
        }
        .sheet(item: $absentShift) { shift in
            MacReportAbsenceSheet(shift: shift)
                .macObserved(repo: repo, toasts: toasts)
        }
    }

    private func dayColumn(for date: Date) -> some View {
        let dateString = RosterCalendar.dateString(from: date)
        let isToday = Calendar.current.isDateInToday(date)
        let shifts = staffShifts.filter { $0.date == dateString }

        return VStack(alignment: .leading, spacing: MacSpace.sm) {
            // Day Header
            VStack(alignment: .leading, spacing: 2) {
                Text(RosterCalendar.dayOfWeek(from: date))
                    .font(MacType.captionStrong)
                    .foregroundStyle(isToday ? MacColor.accent : MacColor.textTertiary)
                    .textCase(.uppercase)

                Text(RosterCalendar.dayOfMonth(from: date))
                    .font(MacType.sectionHeader)
                    .foregroundStyle(isToday ? MacColor.accent : MacColor.textPrimary)
            }
            .padding(.bottom, 4)

            if shifts.isEmpty {
                VStack {
                    Spacer()
                    Text("Off")
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(MacColor.cardBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: MacRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).strokeBorder(MacColor.cardBorder.opacity(0.5), lineWidth: 1))
            } else {
                ForEach(shifts) { shift in
                    shiftCard(shift)
                }
            }
        }
    }

    private func shiftCard(_ shift: Shift) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MacStatusPill(
                shiftStatus: shift.staffDisplayStatus(
                    timesheet: repo.timesheet(forShift: shift.id)
                )
            )

            Text(shift.position)
                .font(MacType.bodyStrong)
                .foregroundStyle(MacColor.textPrimary)
                .lineLimit(1)

            Text("\(shift.startTime) - \(shift.endTime)")
                .font(MacType.mono)
                .foregroundStyle(MacColor.textSecondary)

            if !shift.locationName.isEmpty {
                Text(shift.locationName)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Actions for submitting hours / reporting absence
            if BusinessRules.canSubmitHours(shift: shift, timesheet: repo.timesheet(forShift: shift.id)) {
                Button("Submit Hours") {
                    submittingShift = shift
                }
                .macButton(.prominent, size: .small, fullWidth: true)
            } else if BusinessRules.canReportAbsence(shift: shift, timesheet: repo.timesheet(forShift: shift.id)) {
                Button("Report Absent") {
                    absentShift = shift
                }
                .macButton(.bordered, size: .small, fullWidth: true)
            }
        }
        .padding(MacSpace.md)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.medium))
        .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).strokeBorder(MacColor.cardBorder, lineWidth: 1))
    }
}

// MARK: - Mac Submit Hours Sheet

struct MacSubmitHoursSheet: View {
    let shift: Shift
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var actualStart: String = ""
    @State private var actualEnd: String = ""
    @State private var notes: String = ""

    init(shift: Shift) {
        self.shift = shift
        _actualStart = State(initialValue: shift.startTime)
        _actualEnd = State(initialValue: shift.endTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack {
                Text("Submit Worked Hours")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(MacColor.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("Shift: \(shift.position) on \(shift.date)")
                .font(MacType.body)
                .foregroundStyle(MacColor.textSecondary)

            HStack(spacing: MacSpace.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Time")
                        .font(MacType.captionStrong)
                    TextField("09:00", text: $actualStart)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End Time")
                        .font(MacType.captionStrong)
                    TextField("17:00", text: $actualEnd)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes (optional)")
                    .font(MacType.captionStrong)
                TextEditor(text: $notes)
                    .frame(height: 70)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(MacColor.cardBorder, lineWidth: 1))
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .macButton(.bordered)
                Spacer()
                MacAsyncButton(variant: .prominent) {
                    do {
                        try await repo.submitShiftTimesheet(
                            shiftId: shift.id,
                            actualStartTime: actualStart,
                            actualEndTime: actualEnd,
                            notes: notes
                        )
                        toasts.show("Hours submitted for manager review.", style: .success)
                        dismiss()
                    } catch {
                        toasts.show(error.localizedDescription, style: .error)
                    }
                } label: {
                    Text("Submit for Approval")
                }
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 440)
    }
}

// MARK: - Mac Report Absence Sheet

struct MacReportAbsenceSheet: View {
    let shift: Shift
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""

    init(shift: Shift) {
        self.shift = shift
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacSpace.lg) {
            HStack {
                Text("Report Shift Absence")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(MacColor.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("Are you unable to attend your shift for \(shift.position) on \(shift.date)?")
                .font(MacType.body)
                .foregroundStyle(MacColor.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason for absence")
                    .font(MacType.captionStrong)
                TextField("Illness, family emergency, etc.", text: $reason)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .macButton(.bordered)
                Spacer()
                MacAsyncButton(variant: .destructive) {
                    do {
                        try await repo.reportShiftAbsence(shiftId: shift.id, reason: reason)
                        toasts.show("Absence reported to management.", style: .warning)
                        dismiss()
                    } catch {
                        toasts.show(error.localizedDescription, style: .error)
                    }
                } label: {
                    Text("Confirm Absence")
                }
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 440)
    }
}
#endif
