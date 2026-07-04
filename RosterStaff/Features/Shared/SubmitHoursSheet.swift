import SwiftUI

/// Native bottom sheet for submitting (or resubmitting) worked hours.
/// Mirrors SubmitHoursModal: prefilled times, live worked-hours calc, break
/// stepper (0–90, step 5), and validation.
struct SubmitHoursSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    let shift: Shift
    let existing: Timesheet?

    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: Int
    @State private var notes: String
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingUncompletedTasksAlert = false
    @State private var forceSubmit = false

    init(shift: Shift, existing: Timesheet?) {
        self.shift = shift
        self.existing = existing
        let startSeed = existing.flatMap { TimeConvert.date(from: $0.actualStart) } ?? TimeConvert.date(from: shift.rosteredStart) ?? Date()
        let endSeed = existing.flatMap { TimeConvert.date(from: $0.actualEnd) } ?? TimeConvert.date(from: shift.rosteredEnd) ?? Date()
        _start = State(initialValue: startSeed)
        _end = State(initialValue: endSeed)
        _breakMinutes = State(initialValue: existing?.actualBreakMinutes ?? shift.breakMinutes)
        _notes = State(initialValue: existing?.staffNotes ?? "")
    }

    private var startHHmm: String { TimeConvert.hhmm(from: start) }
    private var endHHmm: String { TimeConvert.hhmm(from: end) }
    private var workedHours: Double {
        BusinessRules.calcWorkedHours(start: startHHmm, end: endHHmm, breakMinutes: breakMinutes)
    }
    private var scheduledDiff: Double { workedHours - shift.scheduledHours }
    
    private var pendingTasksCount: Int {
        let weekday = weekdayNumber(for: shift.date)
        let activeTasks = repo.tasks.filter { task in
            if task.frequency == "once" {
                return task.date == shift.date
            } else if task.frequency == "weekly" {
                return task.dayOfWeek?.contains(weekday) ?? false
            } else {
                return true // "daily"
            }
        }
        let completedCount = activeTasks.filter { task in
            repo.taskCompletions.contains { $0.taskId == task.id && $0.date == shift.date && $0.completed }
        }
        .count
        return activeTasks.count - completedCount
    }
    
    private func weekdayNumber(for dateKey: String) -> Int {
        guard let date = RosterCalendar.dateFromKey(dateKey) else { return 1 }
        let raw = RosterCalendar.calendar.component(.weekday, from: date)
        if raw == 1 { return 7 }
        return raw - 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    summaryHeader

                    Card {
                        VStack(spacing: 16) {
                            timeRow(title: "Start", selection: $start)
                            Divider().overlay(Theme.separator)
                            timeRow(title: "End", selection: $end)
                            Divider().overlay(Theme.separator)
                            breakRow
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES (OPTIONAL)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                            TextField("Anything your manager should know?", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }

                    if let errorMessage {
                        Banner(kind: .error, title: errorMessage)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking { ProgressView().tint(.white) }
                        else { Text(existing?.status == .rejected ? "Resubmit hours" : "Submit hours") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWorking || workedHours <= 0)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Submit Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Pending Tasks", isPresented: $showingUncompletedTasksAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Submit Anyway") {
                    forceSubmit = true
                    Task { await submit() }
                }
            } message: {
                Text("You have \(pendingTasksCount) uncompleted task(s) for today. Have you completed all of your duties?")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var summaryHeader: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(RosterFormat.date(shift.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(RosterFormat.decimalHours(workedHours))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("hours worked")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                if abs(scheduledDiff) > 0.5 {
                    Text(scheduledDiff > 0
                         ? "\(RosterFormat.hours(scheduledDiff)) more than scheduled"
                         : "\(RosterFormat.hours(-scheduledDiff)) less than scheduled")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func timeRow(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private var breakRow: some View {
        HStack {
            Text("Break")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 14) {
                stepButton(system: "minus") {
                    breakMinutes = BusinessRules.clampBreakMinutes(breakMinutes - BusinessRules.breakMinutesStep)
                    Haptics.light()
                }
                Text("\(breakMinutes)m")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                stepButton(system: "plus") {
                    breakMinutes = BusinessRules.clampBreakMinutes(breakMinutes + BusinessRules.breakMinutesStep)
                    Haptics.light()
                }
            }
        }
    }

    private func stepButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.brand)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.brand.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func submit() async {
        errorMessage = nil
        guard workedHours > 0 else { errorMessage = "Worked hours must be greater than zero."; return }
        guard let user = repo.currentUser else { errorMessage = "Not signed in."; return }
        
        if pendingTasksCount > 0 && !forceSubmit {
            showingUncompletedTasksAlert = true
            return
        }
        
        isWorking = true
        defer { isWorking = false; forceSubmit = false }
        do {
            if let existing, existing.status == .rejected {
                try await repo.resubmitTimesheet(id: existing.id, actualStart: startHHmm, actualEnd: endHHmm,
                                                 breakMinutes: breakMinutes, workedHours: workedHours, notes: notes)
            } else {
                try await repo.submitTimesheet(shiftId: shift.id, staffId: user.id, actualStart: startHHmm,
                                               actualEnd: endHHmm, breakMinutes: breakMinutes,
                                               workedHours: workedHours, notes: notes)
            }
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

/// HH:mm <-> Date helpers (only hour/minute are meaningful).
enum TimeConvert {
    static func date(from hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var comps = DateComponents()
        comps.hour = parts[0]
        comps.minute = parts[1]
        comps.year = 2000; comps.month = 1; comps.day = 1
        return Calendar.current.date(from: comps)
    }

    static func hhmm(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
