import SwiftUI

struct AvailabilityView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var weekOffset = 0
    @State private var form: UserAvailability = .defaultAvailability
    @State private var original: UserAvailability = .defaultAvailability
    @State private var saveAsDefault = false
    @State private var editingDay: Weekday?
    @State private var isWorking = false
    @State private var toastMessage: ToastMessage?

    // Confirmation dialogs
    @State private var pendingWeekChange: Int?
    @State private var showSaveDefaultConfirm = false
    @State private var showResetMenu = false

    private var now: Date { Date() }
    private var boundsMin: Int { BusinessRules.availabilityMinWeekOffset }
    private var boundsMax: Int { BusinessRules.availabilityMaxWeekOffset }
    private var monday: Date { RosterCalendar.addWeeks(weekOffset, to: RosterCalendar.weekStart(now)) }
    private var weekKey: String { RosterCalendar.dayFormatter.string(from: monday) }
    private var isManagerLocked: Bool {
        repo.lockedAvailabilityWeeks.contains(weekKey)
            && !BusinessRules.isWeekLockedForStaff(weekStartKey: weekKey, at: now)
    }
    private var isLocked: Bool {
        BusinessRules.isWeekLockedForStaff(weekStartKey: weekKey,
                                           managerLockedWeeks: repo.lockedAvailabilityWeeks,
                                           at: now)
    }
    private var isDirty: Bool { form != original }
    private var hasCustomWeek: Bool { repo.currentUser?.weeklyAvailability[weekKey] != nil }

    var body: some View {
        NavigationStack {
            TabScroll {
                weekNav
                if isManagerLocked {
                    Banner(kind: .info,
                           title: "Locked by your manager",
                           message: "The roster for this week has been published and locked. Contact your manager to change availability.")
                } else if isLocked {
                    Banner(kind: .info,
                           title: "This week is locked",
                           message: "You can only change availability for upcoming weeks. Navigate forward to edit.")
                }
                dayList
                if !isLocked {
                    footer
                }
            }
            .navigationTitle("Availability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitlePill(title: "Availability", icon: "calendar.badge.clock")
                }
                if !isLocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        ToolbarSaveButton(
                            isEnabled: isDirty || saveAsDefault,
                            isWorking: isWorking
                        ) {
                            if saveAsDefault { showSaveDefaultConfirm = true } else { Task { await save() } }
                        }
                    }
                }
            }
            .sheet(item: $editingDay) { day in
                DayEditSheet(weekday: day, dateKey: dateKey(for: day), day: binding(for: day))
            }
            .confirmationDialog("Discard changes?",
                                isPresented: Binding(get: { pendingWeekChange != nil }, set: { if !$0 { pendingWeekChange = nil } }),
                                titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    if let target = pendingWeekChange { weekOffset = target }
                    pendingWeekChange = nil
                }
                Button("Keep editing", role: .cancel) { pendingWeekChange = nil }
            } message: {
                Text("You have unsaved changes for this week.")
            }
            .confirmationDialog("Set as default?",
                                isPresented: $showSaveDefaultConfirm, titleVisibility: .visible) {
                Button("Apply to this and all upcoming weeks") {
                    saveAsDefault = true
                    Task { await save() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This overwrites availability for this week and every following unlocked week.")
            }
            .confirmationDialog("Reset options", isPresented: $showResetMenu, titleVisibility: .visible) {
                Button("Reset this week to default") { Task { await resetThisWeek() } }
                Button("Reset all following weeks", role: .destructive) { Task { await resetFollowingWeeks() } }
                Button("Cancel", role: .cancel) { }
            }
            .toast($toastMessage)
            .task(id: weekKey) { loadForm() }
            .task(id: repo.currentUser?.updatedAt) { loadForm() }
        }
    }

    // MARK: Week navigation

    private var weekNav: some View {
        Card {
            HStack {
                navButton(system: "chevron.left", enabled: weekOffset > boundsMin) { requestWeekChange(weekOffset - 1) }
                Spacer()
                VStack(spacing: 4) {
                    Text(RosterFormat.weekRange(monday: monday))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        weekBadge(isManagerLocked ? "Locked by manager" : (isLocked ? "Locked" : (weekOffset == 0 ? "Current" : "Upcoming")),
                                  tint: isLocked ? Theme.textTertiary : Theme.brand)
                        weekBadge(hasCustomWeek ? "Custom" : "Default",
                                  tint: hasCustomWeek ? Theme.accent : Theme.textTertiary)
                    }
                }
                Spacer()
                navButton(system: "chevron.right", enabled: weekOffset < boundsMax) { requestWeekChange(weekOffset + 1) }
            }
        }
    }

    private func weekBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func navButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: system)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? Theme.brand : Theme.textTertiary)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.brand.opacity(enabled ? 0.10 : 0.04)))
        }
        .disabled(!enabled)
    }

    // MARK: Day list

    private var dayList: some View {
        VStack(spacing: 10) {
            ForEach(Weekday.allCases) { day in
                dayRow(day)
            }
        }
    }

    private func dayRow(_ day: Weekday) -> some View {
        let value = form[day]
        return Button {
            guard !isLocked else { return }
            Haptics.light()
            editingDay = day
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(value.available ? Theme.accent.opacity(0.15) : Theme.textTertiary.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: value.available ? "checkmark" : "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(value.available ? Theme.accent : Theme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.fullLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary(value))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if !isLocked {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card))
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.55 : 1)
        .disabled(isLocked)
    }

    private func summary(_ value: DayAvailability) -> String {
        guard value.available else { return "Unavailable" }
        if value.allDay { return "Available all day" }
        return "\(RosterFormat.time(value.start ?? "09:00")) – \(RosterFormat.time(value.end ?? "17:00"))"
    }

    // MARK: Footer

    // Save now lives as a pill in the navigation bar (enabled only when
    // there are unsaved changes) — the footer keeps the recurring toggle
    // and reset options.
    private var footer: some View {
        VStack(spacing: 12) {
            Card {
                Toggle(isOn: $saveAsDefault) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set as recurring")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Apply to this and all upcoming weeks")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .tint(Theme.brand)
            }

            if hasCustomWeek {
                Button {
                    showResetMenu = true
                } label: {
                    Label("Reset options", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.textSecondary))
            }
        }
    }

    // MARK: Binding helper

    private func binding(for day: Weekday) -> Binding<DayAvailability> {
        Binding(
            get: { form[day] },
            set: { form[day] = $0 }
        )
    }

    private func dateKey(for day: Weekday) -> String {
        let index = Weekday.allCases.firstIndex(of: day) ?? 0
        let date = RosterCalendar.addDays(index, to: monday)
        return RosterCalendar.dayFormatter.string(from: date)
    }

    // MARK: Data

    private func loadForm() {
        guard let me = repo.currentUser else { return }
        let loaded = me.weeklyAvailability[weekKey] ?? me.availability ?? .defaultAvailability
        if !isDirty || original != loaded {
            form = loaded
            original = loaded
            saveAsDefault = false
        }
    }

    private func requestWeekChange(_ target: Int) {
        let clamped = min(max(target, boundsMin), boundsMax)
        guard clamped != weekOffset else { return }
        if isDirty {
            pendingWeekChange = clamped
        } else {
            weekOffset = clamped
        }
    }

    private func save() async {
        guard let me = repo.currentUser else { return }
        isWorking = true
        defer { isWorking = false }
        var weekly = me.weeklyAvailability
        let keys = saveAsDefault ? BusinessRules.recurringWeekKeys(fromMonday: monday, at: now) : [weekKey]
        for key in keys where !BusinessRules.isWeekLockedForStaff(weekStartKey: key,
                                                                  managerLockedWeeks: repo.lockedAvailabilityWeeks,
                                                                  at: now) {
            weekly[key] = form
        }
        do {
            try await repo.saveWeeklyAvailability(weekly)
            original = form
            Haptics.success()
            toastMessage = ToastMessage(kind: .success, text: saveAsDefault ? "Saved for upcoming weeks" : "Availability saved")
            saveAsDefault = false
        } catch {
            toastMessage = ToastMessage(kind: .error, text: error.localizedDescription)
            Haptics.error()
        }
    }

    private func resetThisWeek() async {
        guard let me = repo.currentUser else { return }
        var weekly = me.weeklyAvailability
        weekly.removeValue(forKey: weekKey)
        await performReset(weekly, message: "This week reset to default")
    }

    private func resetFollowingWeeks() async {
        guard let me = repo.currentUser else { return }
        let currentWeekKey = RosterCalendar.weekStartKey(now)
        var weekly = me.weeklyAvailability
        for key in weekly.keys where key > weekKey && key > currentWeekKey
            && !repo.lockedAvailabilityWeeks.contains(key) {
            weekly.removeValue(forKey: key)
        }
        await performReset(weekly, message: "Following weeks reset")
    }

    private func performReset(_ weekly: [String: UserAvailability], message: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.saveWeeklyAvailability(weekly)
            loadForm()
            Haptics.success()
            toastMessage = ToastMessage(kind: .success, text: message)
        } catch {
            toastMessage = ToastMessage(kind: .error, text: error.localizedDescription)
            Haptics.error()
        }
    }
}
