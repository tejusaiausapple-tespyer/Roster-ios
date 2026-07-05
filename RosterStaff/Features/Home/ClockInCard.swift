import SwiftUI

/// Start Shift / break / End Shift controls for today's shift.
///
/// The session is device-local (see ClockSession): the recorded start, end
/// and break times prefill SubmitHoursSheet, which writes the timesheet —
/// that's where the data joins the rest of the system.
struct ClockInCard: View {
    @Environment(RosterRepository.self) private var repo

    let shift: Shift
    let onSubmitHours: () -> Void

    private var session: ClockSession? {
        guard let s = repo.clockSession, s.shiftId == shift.id else { return nil }
        return s
    }

    var body: some View {
        Card {
            if let session {
                if session.isActive {
                    activeBody(session)
                } else {
                    endedBody(session)
                }
            } else {
                idleBody
            }
        }
    }

    // MARK: Not clocked in yet

    private var idleBody: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to start?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Clock in when your shift begins.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                repo.startClockSession(shiftId: shift.id)
                Haptics.success()
            } label: {
                Label("Start Shift", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
        }
    }

    // MARK: Clocked in

    private func activeBody(_ session: ClockSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(session.isOnBreak ? Theme.warning : Theme.accent)
                                .frame(width: 8, height: 8)
                            Text(session.isOnBreak ? "On break" : "On the clock")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Text("Started \(RosterFormat.time(TimeConvert.hhmm(from: session.clockInAt)))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(elapsed(session.workedSeconds(at: context.date)))
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

                HStack(spacing: 10) {
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

                    Button {
                        repo.endClockSession()
                        Haptics.success()
                    } label: {
                        Label("End Shift", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                }
            }
        }
    }

    // MARK: Clocked out, hours not yet submitted

    private func endedBody(_ session: ClockSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shift ended")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                let brk = session.timesheetBreakMinutes()
                Text("\(RosterFormat.decimalHours(session.workedSeconds() / 3600))h worked · \(brk > 0 ? "\(brk)m break" : "no break")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                onSubmitHours()
            } label: {
                Label("Submit hours", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
        }
    }

    private func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
