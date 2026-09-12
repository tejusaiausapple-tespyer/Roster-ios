#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacStaffHomeView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(MacToastCenter.self) private var toasts

    @State private var showingSubmitShift: Shift?
    @State private var showingAbsentShift: Shift?

    init() {}

    private var currentUserId: String {
        repo.currentUser?.id ?? ""
    }

    private var todayShifts: [Shift] {
        let today = RosterCalendar.todayString()
        return repo.shifts.filter { $0.staffId == currentUserId && $0.date == today }
    }

    private var activeClockSession: ClockSession? {
        repo.activeClockSession
    }

    private var assignedJobs: [DailyJob] {
        let today = RosterCalendar.todayString()
        return repo.dailyJobs.filter { $0.date == today && $0.assignedStaffId == currentUserId }
    }

    var body: some View {
        MacScreen(
            title: "Staff Overview",
            subtitle: "Today, \(RosterCalendar.todayFormattedLong())"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    // Top Hero: Clock In / Clock Out Card
                    clockInHeroCard

                    // Middle Grid: Assigned Daily Jobs & Today's Schedule
                    HStack(alignment: .top, spacing: MacSpace.xl) {
                        // Left: Today's Shift & Status
                        VStack(alignment: .leading, spacing: MacSpace.md) {
                            Text("Today's Shifts")
                                .font(MacType.sectionHeader)
                                .foregroundStyle(MacColor.textPrimary)

                            if todayShifts.isEmpty {
                                MacCard {
                                    HStack(spacing: MacSpace.md) {
                                        Image(systemName: "sun.max.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(MacColor.warning)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("No shifts scheduled for today")
                                                .font(MacType.bodyStrong)
                                                .foregroundStyle(MacColor.textPrimary)
                                            Text("Enjoy your time off or check the Roster tab for upcoming work.")
                                                .font(MacType.caption)
                                                .foregroundStyle(MacColor.textTertiary)
                                        }
                                        Spacer()
                                    }
                                }
                            } else {
                                ForEach(todayShifts) { shift in
                                    todayShiftCard(shift)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Right: Assigned Jobs Checklist
                        VStack(alignment: .leading, spacing: MacSpace.md) {
                            Text("Assigned Daily Jobs (\(assignedJobs.count))")
                                .font(MacType.sectionHeader)
                                .foregroundStyle(MacColor.textPrimary)

                            if assignedJobs.isEmpty {
                                MacCard {
                                    HStack(spacing: MacSpace.md) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(MacColor.success)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("All caught up!")
                                                .font(MacType.bodyStrong)
                                                .foregroundStyle(MacColor.textPrimary)
                                            Text("No daily jobs assigned to you for today.")
                                                .font(MacType.caption)
                                                .foregroundStyle(MacColor.textTertiary)
                                        }
                                        Spacer()
                                    }
                                }
                            } else {
                                ForEach(assignedJobs) { job in
                                    jobChecklistRow(job)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Bottom: Announcements & Messages
                    if !repo.announcements.isEmpty {
                        VStack(alignment: .leading, spacing: MacSpace.md) {
                            Text("Company Announcements")
                                .font(MacType.sectionHeader)
                                .foregroundStyle(MacColor.textPrimary)

                            ForEach(repo.announcements) { announcement in
                                MacCard(
                                    title: announcement.title,
                                    subtitle: "\(announcement.authorName) • \(announcement.formattedDate)",
                                    icon: "megaphone.fill"
                                ) {
                                    Text(announcement.content)
                                        .font(MacType.body)
                                        .foregroundStyle(MacColor.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }

    // MARK: - Clock In Hero

    private var clockInHeroCard: some View {
        let isClockedIn = activeClockSession != nil

        return MacCard {
            HStack(spacing: MacSpace.xl) {
                ZStack {
                    Circle()
                        .fill(isClockedIn ? MacColor.success.opacity(0.15) : MacColor.accent.opacity(0.15))
                        .frame(width: 58, height: 58)
                    Image(systemName: isClockedIn ? "clock.badge.checkmark.fill" : "clock.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isClockedIn ? MacColor.success : MacColor.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: MacSpace.sm) {
                        Text(isClockedIn ? "Currently On Shift" : "Ready to Start Shift?")
                            .font(MacType.sectionHeader)
                            .foregroundStyle(MacColor.textPrimary)

                        MacStatusPill(
                            text: isClockedIn ? "CLOCKED IN" : "OFF CLOCK",
                            foreground: isClockedIn ? MacColor.success : MacColor.textTertiary,
                            background: isClockedIn ? MacColor.success.opacity(0.12) : MacColor.cardBorder.opacity(0.4),
                            border: isClockedIn ? MacColor.success.opacity(0.3) : MacColor.cardBorder
                        )
                    }

                    if isClockedIn, let session = activeClockSession {
                        Text("Clocked in at \(session.formattedStartTime) • \(session.elapsedDurationString)")
                            .font(MacType.monoStrong)
                            .foregroundStyle(MacColor.textSecondary)
                    } else {
                        Text("Record your attendance directly from your Mac desktop.")
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.textTertiary)
                    }
                }

                Spacer()

                if isClockedIn {
                    MacAsyncButton(variant: .destructive, size: .medium) {
                        do {
                            try await repo.endCurrentClockSession()
                            toasts.show("Clocked out successfully.", style: .success)
                        } catch {
                            toasts.show(error.localizedDescription, style: .error)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                            Text("End Shift")
                        }
                    }
                } else {
                    MacAsyncButton(variant: .prominent, size: .medium) {
                        do {
                            try await repo.startClockSession(staffId: currentUserId)
                            toasts.show("Clocked in successfully!", style: .success)
                        } catch {
                            toasts.show(error.localizedDescription, style: .error)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                            Text("Start Shift")
                        }
                    }
                }
            }
        }
    }

    private func todayShiftCard(_ shift: Shift) -> some View {
        MacCard {
            HStack(spacing: MacSpace.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: MacSpace.sm) {
                        Text(shift.position)
                            .font(MacType.bodyStrong)
                            .foregroundStyle(MacColor.textPrimary)

                        MacStatusPill(
                            shiftStatus: shift.staffDisplayStatus(
                                timesheet: repo.timesheet(forShift: shift.id)
                            )
                        )
                    }

                    Text("\(shift.startTime) – \(shift.endTime) (\(shift.durationFormatted))")
                        .font(MacType.mono)
                        .foregroundStyle(MacColor.textSecondary)

                    if !shift.locationName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 11))
                            Text(shift.locationName)
                                .font(MacType.caption)
                        }
                        .foregroundStyle(MacColor.textTertiary)
                    }
                }
                Spacer()
            }
        }
    }

    private func jobChecklistRow(_ job: DailyJob) -> some View {
        MacCard(padding: MacSpace.md) {
            HStack(spacing: MacSpace.md) {
                Button {
                    Task {
                        try? await repo.toggleDailyJobCompletion(jobId: job.id)
                    }
                } label: {
                    Image(systemName: job.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(job.isCompleted ? MacColor.success : MacColor.cardBorder)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(job.isCompleted ? MacColor.textTertiary : MacColor.textPrimary)
                        .strikethrough(job.isCompleted)
                }
                Spacer()
            }
        }
    }
}
#endif
