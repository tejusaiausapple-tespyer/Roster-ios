import SwiftUI

/// Start Shift / break / End Shift controls for today's shift.
///
/// The device-local session (ClockSession) drives the live timer and prefills
/// SubmitHoursSheet. Alongside it, every start/end tap writes a verified
/// attendance record (ShiftAttendance): server-authoritative timestamps plus
/// a GPS fix checked against the shift's workplace geofence.
struct ClockInCard: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Presentation: Equatable {
        case card
        case embedded
    }

    let shift: Shift
    var presentation: Presentation = .card
    let onSubmitHours: () -> Void

    @State private var isWorking = false
    @State private var showEndConfirmation = false
    @State private var showEndChoice = false
    @State private var showEarlyLeaveNote = false
    @State private var earlyLeaveNote = ""
    /// Note held across the async end flow so it isn't lost mid-flow.
    @State private var pendingEndNote: String?
    /// "Use rostered end time" choice held across the async end flow.
    @State private var pendingUseRosteredEnd = false
    @State private var geofencePrompt: GeofencePrompt?
    @State private var blockedAlert: String?
    @State private var errorAlert: String?

    /// Pending start/end held while the user confirms an unverified or
    /// out-of-area location.
    private struct GeofencePrompt: Identifiable {
        enum Action { case start, end }
        let id = UUID()
        let action: Action
        let fix: ShiftAttendance.Fix?
        let message: String

        var confirmLabel: String { action == .start ? "Start Anyway" : "End Anyway" }
    }

    private var session: ClockSession? {
        guard let s = repo.clockSession, s.shiftId == shift.id else { return nil }
        return s
    }

    var body: some View {
        Group {
            if presentation == .card {
                Card { clockContent }
            } else {
                clockContent
            }
        }
        .task(id: router.pendingClockAction) {
            await handlePendingLiveActivityAction()
        }
        .confirmationDialog(
            "Are you sure you want to end your shift?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Shift", role: .destructive) {
                if ServerClock.shared.now < shift.endDateTime {
                    // Early leave: offer a note for the manager first.
                    showEarlyLeaveNote = true
                } else {
                    // At/after the rostered end: stayed back, or on time?
                    showEndChoice = true
                }
            }
            Button("Keep Working", role: .cancel) {}
        } message: {
            if ServerClock.shared.now < shift.endDateTime {
                Text("Your rostered shift runs until \(RosterFormat.time(shift.rosteredEnd)). Ending now can't be undone.")
            } else {
                Text("Ending your shift can't be undone.")
            }
        }
        .confirmationDialog(
            "How did your shift finish?",
            isPresented: $showEndChoice,
            titleVisibility: .visible
        ) {
            Button("Stayed back for extra work") {
                pendingUseRosteredEnd = false
                Task { await endShift() }
            }
            Button("Finished at my rostered time (\(RosterFormat.time(shift.rosteredEnd)))") {
                pendingUseRosteredEnd = true
                Task { await endShift() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"Stayed back\" records your actual finish time — you can adjust the hours before submitting. Otherwise your rostered end time is used.")
        }
        .alert("Leaving early?", isPresented: $showEarlyLeaveNote) {
            TextField("E.g. feeling unwell", text: $earlyLeaveNote)
            Button("End Shift") {
                pendingEndNote = earlyLeaveNote
                pendingUseRosteredEnd = false
                Task { await endShift() }
            }
            Button("Cancel", role: .cancel) { earlyLeaveNote = "" }
        } message: {
            Text("Add a short note for your manager about why you're ending your shift early (optional).")
        }
        .confirmationDialog(
            "Location check",
            isPresented: Binding(
                get: { geofencePrompt != nil },
                set: { if !$0 { geofencePrompt = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let prompt = geofencePrompt {
                Button(prompt.confirmLabel) {
                    let held = prompt
                    geofencePrompt = nil
                    Task { await commit(action: held.action, fix: held.fix) }
                }
                Button("Cancel", role: .cancel) { geofencePrompt = nil }
            }
        } message: {
            if let prompt = geofencePrompt {
                Text(prompt.message)
            }
        }
        .alert("You are outside the work zone", isPresented: Binding(
            get: { blockedAlert != nil },
            set: { if !$0 { blockedAlert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(blockedAlert ?? "")
        }
        .alert("Couldn't sync your shift", isPresented: Binding(
            get: { errorAlert != nil },
            set: { if !$0 { errorAlert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
    }

    @ViewBuilder
    private var clockContent: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            if let session {
                if session.isActive {
                    activeBody(session)
                } else {
                    endedBody(session)
                }
            } else if ServerClock.shared.now > shift.endDateTime {
                missedBody
            } else {
                idleBody
            }
        }
    }

    // MARK: Not clocked in yet

    /// Instant the Start button unlocks: 5 minutes before the rostered start,
    /// judged against server-corrected time so the device clock can't open
    /// the window early.
    private var unlockDate: Date {
        shift.startDateTime.addingTimeInterval(-AppConfig.earlyClockInWindow)
    }

    private var responsiveLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private var idleBody: some View {
        // Re-evaluates every few seconds so the button appears on its own
        // the moment the early check-in window opens.
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            let serverNow = ServerClock.shared.now
            responsiveLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(serverNow >= unlockDate ? "Ready to start?" : "Starts soon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if serverNow >= unlockDate {
                        Text(serverNow < shift.startDateTime
                             ? "Early check-in is open — paid time starts \(RosterFormat.time(shift.rosteredStart))."
                             : "Clock in when your shift begins.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Start Shift unlocks at \(RosterFormat.time(TimeConvert.hhmm(from: unlockDate))) — 5 min before your shift.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if serverNow >= unlockDate {
                    Button {
                        Task { await startShift() }
                    } label: {
                        if isWorking || repo.isStartingClockSession {
                            ProgressView().tint(Theme.brand)
                        } else {
                            Label("Start Shift", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .frame(minHeight: 44)
                    // repo.isStartingClockSession disables every today's-shift
                    // card's Start button the moment any one of them begins,
                    // not just the tapped card's own isWorking.
                    .disabled(isWorking || repo.isStartingClockSession)
                } else {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    // MARK: Missed clock-in

    /// Shown once the shift's rostered end has passed with no clock-in at all — starting now
    /// would produce a meaningless near-zero session, so skip straight to manual submission.
    private var missedBody: some View {
        let submittable = shift.isSubmittable(at: ServerClock.shared.now)
        return responsiveLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Missed clocking in")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(submittable
                     ? "This shift ended without a clock-in. You can still submit your hours directly."
                     : "This shift ended without a clock-in. Hours can be submitted after \(RosterFormat.time(shift.rosteredEnd)).")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onSubmitHours()
            } label: {
                Label("Submit hours", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .frame(minHeight: 44)
            .disabled(!submittable)
        }
    }

    // MARK: Clocked in

    private func activeBody(_ session: ClockSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 14) {
                responsiveLayout {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(session.isOnBreak ? Theme.warning : Theme.accent)
                                .frame(width: 8, height: 8)
                            Text(session.isOnBreak ? "On break" : "On the clock")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if session.clockInAt < shift.startDateTime {
                            Text("Checked in \(RosterFormat.time(TimeConvert.hhmm(from: session.clockInAt))) · paid from \(RosterFormat.time(shift.rosteredStart))")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Text("Started \(RosterFormat.time(TimeConvert.hhmm(from: session.clockInAt)))")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        // startShift writes the local session before the
                        // server attendance record; a network failure at
                        // that point leaves the local timer running with
                        // nothing verified server-side yet. Surfacing it
                        // here at least makes the gap visible — the write
                        // itself gets a fresh attempt automatically the
                        // moment End Shift is tapped (endShift's setData
                        // merge doesn't require the doc, or clockInAt, to
                        // already exist).
                        if repo.attendance(forShift: shift.id)?.clockInAt == nil {
                            Text("Clock-in hasn't synced to the server yet.")
                                .font(.caption2)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        Text(elapsed(session.paidWorkedSeconds(rosterStart: shift.startDateTime, at: context.date)))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        if session.totalBreakSeconds(at: context.date) >= 60 {
                            Text("\(Int(session.totalBreakSeconds(at: context.date) / 60))m break")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 10) { activeButtons(session) }
                    } else {
                        HStack(spacing: 10) { activeButtons(session) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activeButtons(_ session: ClockSession) -> some View {
                    Button {
                        if session.isOnBreak { repo.endClockBreak() } else { repo.startClockBreak() }
                        Haptics.light()
                    } label: {
                        Label(session.isOnBreak ? "End Break" : "Start Break",
                              systemImage: session.isOnBreak ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.warning)
                    .frame(minHeight: 44)
                    .disabled(isWorking)

                    Button {
                        showEndConfirmation = true
                    } label: {
                        if isWorking {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Label("End Shift", systemImage: "stop.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .frame(minHeight: 44)
                    .disabled(isWorking)
    }

    // MARK: Clocked out, hours not yet submitted

    private func endedBody(_ session: ClockSession) -> some View {
        // The backend accepts a timesheet once the rostered shift has ended
        // (`submittableAfter`) OR a verified clock-out is on the attendance
        // record (early leavers) — mirror that gate here. The attendance
        // check waits for the server's confirmation via the live listener,
        // so the button unlocks moments after a successful early clock-out.
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            // A verified clockOutAt still missing here (unlike clockInAt,
            // which start's local mutation always precedes a write for)
            // means the end-shift write never reached the server — offline,
            // a transient failure, etc. Ending isn't itself restricted, so
            // there was previously no way back to a button that retries it
            // once the UI has already moved to this "ended" state.
            let syncPending = repo.attendance(forShift: shift.id)?.clockOutAt == nil
            let submittable = shift.isSubmittable(at: ServerClock.shared.now)
                || repo.attendance(forShift: shift.id)?.clockOutAt != nil
            responsiveLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shift ended")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    let brk = session.timesheetBreakMinutes()
                    Text("\(RosterFormat.decimalHours(session.paidWorkedSeconds(rosterStart: shift.startDateTime) / 3600))h worked · \(brk > 0 ? "\(brk)m break" : "no break")")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if syncPending {
                        Text("Your clock-out hasn't synced to the server yet.")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    } else if !submittable {
                        Text("Hours can be submitted after \(RosterFormat.time(shift.rosteredEnd)).")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if syncPending {
                    Button {
                        Task { await retryEndSync() }
                    } label: {
                        if isWorking {
                            ProgressView().tint(Theme.brand)
                        } else {
                            Label("Retry sync", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .frame(minHeight: 44)
                    .disabled(isWorking)
                } else {
                    Button {
                        onSubmitHours()
                    } label: {
                        Label("Submit hours", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .frame(minHeight: 44)
                    .disabled(!submittable)
                }
            }
        }
    }

    // MARK: - Start / End orchestration

    private func startShift() async {
        await capture(action: .start)
    }

    private func endShift() async {
        await capture(action: .end)
    }

    private func handlePendingLiveActivityAction() async {
        guard let action = router.pendingClockAction,
              action.shiftId == shift.id else { return }
        router.pendingClockAction = nil

        switch action.kind {
        case .start:
            guard session == nil, ServerClock.shared.now >= unlockDate else { return }
            await startShift()
        case .end:
            guard session?.isActive == true else { return }
            showEndConfirmation = true
        }
    }

    /// Re-attempts the end-shift server write after it failed to sync the
    /// first time. Ending has no gating restriction, so this is exactly the
    /// same flow as a fresh End Shift tap — a new GPS fix, then the same
    /// `shift_attendance` write `commit(action: .end, fix:)` already does.
    private func retryEndSync() async {
        await capture(action: .end)
    }

    /// Lenient allowance for starting a shift when the location's geofence
    /// is not enforced.
    private static let lenientStartRadius: Double = 250

    /// Get a GPS fix and run the geofence policy:
    /// - START, geofence enforced: outside the configured radius = blocked.
    /// - START, not enforced: allowed within 250 m; further out warns and
    ///   records but can proceed.
    /// - END: never restricted — the fix is recorded for the audit trail
    ///   only, so staff can end from home without prompts.
    private func capture(action: GeofencePrompt.Action) async {
        // Closes the double-start race window: starting awaits a GPS fix
        // before repo.clockSession is ever set, so without a shared guard
        // two different today's-shift cards could both proceed. Scoped to
        // .start only — ending has no such restriction (see doc comment above).
        if action == .start {
            guard !repo.isStartingClockSession else { return }
            repo.isStartingClockSession = true
        }
        isWorking = true
        defer {
            isWorking = false
            if action == .start { repo.isStartingClockSession = false }
        }

        let workplace = repo.workplace(for: shift)
        let enforced = workplace?.geofenceEnforced ?? false
        let location = try? await LocationService.shared.currentLocation()

        // Ending: best-effort capture, no gating of any kind.
        if action == .end {
            let fix = location.map { ShiftAttendance.Fix(location: $0, workplace: workplace) }
            await commit(action: .end, fix: fix)
            return
        }

        // Starting: no GPS fix at all → explain and let them decide.
        guard let location else {
            geofencePrompt = GeofencePrompt(
                action: .start, fix: nil,
                message: "Your location couldn't be determined, so it won't be verified if you start the shift now."
            )
            Haptics.warning()
            return
        }

        let fix = ShiftAttendance.Fix(
            location: location, workplace: workplace,
            allowedRadius: enforced ? nil : Self.lenientStartRadius
        )

        if fix.geofence == .outside, let workplace {
            let distance = fix.distanceFromWorkplace.map { Self.formatDistance($0) } ?? "some distance"
            if enforced {
                blockedAlert = "You appear to be \(distance) from \(workplace.displayName). Move inside the work zone to start your shift."
                Haptics.error()
                return
            }
            geofencePrompt = GeofencePrompt(
                action: .start, fix: fix,
                message: "You appear to be \(distance) from \(workplace.displayName). This will be recorded on your attendance."
            )
            Haptics.warning()
            return
        }

        await commit(action: .start, fix: fix)
    }

    private func commit(action: GeofencePrompt.Action, fix: ShiftAttendance.Fix?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch action {
            case .start:
                try await repo.startShift(shift, fix: fix)
            case .end:
                try await repo.endShift(shift, fix: fix, note: pendingEndNote,
                                        useRosteredEnd: pendingUseRosteredEnd)
                pendingEndNote = nil
                pendingUseRosteredEnd = false
                earlyLeaveNote = ""
            }
            Haptics.success()
        } catch {
            // The local session already reflects the tap (the timer keeps
            // working offline); only the verified record failed to sync.
            errorAlert = "Your shift was recorded on this device, but the verified time couldn't reach the server: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    private static func formatDistance(_ metres: Double) -> String {
        metres >= 1000
            ? String(format: "%.1f km", metres / 1000)
            : "\(Int(metres.rounded())) m"
    }

    private func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
