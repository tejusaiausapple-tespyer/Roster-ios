import SwiftUI

/// Today's Daily Jobs at a glance across every staff member — opened from the
/// Dashboard's "Daily Jobs" card. Solves the friction of having to find the
/// right row under Today's Roster Status just to check or assign jobs: this
/// page is dedicated to exactly that, one row per today's shift, tap through
/// to the same DailyJobAssignSheet the roster rows already use.
struct ManagerDailyJobsOverviewView: View {
    @Environment(RosterRepository.self) private var repo
    @State private var selectedShift: Shift? = nil

    private var todaysShifts: [Shift] {
        repo.todaysShifts()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if todaysShifts.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(todaysShifts.enumerated()), id: \.element.id) { index, shift in
                            Button {
                                selectedShift = shift
                            } label: {
                                shiftRow(shift)
                            }
                            .buttonStyle(.plain)
                            .pointerHover()

                            if index < todaysShifts.count - 1 {
                                Divider().overlay(Theme.separator)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                            .fill(Theme.card)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                }
            }
            .padding(Theme.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .tracksTitlePillCollapse()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Daily Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .screenTitlePill("Daily Jobs", icon: "checklist", fraction: 0)
        .macRefreshable {
            await repo.refreshFromServer()
        }
        .sheet(item: $selectedShift) { shift in
            DailyJobAssignSheet(shift: shift)
        }
    }

    private func shiftRow(_ shift: Shift) -> some View {
        let staffMember = repo.user(id: shift.staffId)
        let jobs = repo.dailyJobs(forShift: shift.id)
        let done = jobs.filter(\.completed).count

        return HStack(spacing: 12) {
            Text(staffMember?.initials ?? "?")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.brand.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(staffMember?.fullName ?? "Staff Member")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(shift.rosteredStart) - \(shift.rosteredEnd)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if jobs.isEmpty {
                Text("No jobs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text("\(done)/\(jobs.count) done")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(done == jobs.count ? Theme.accent : Theme.warning)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        Capsule().fill((done == jobs.count ? Theme.accent : Theme.warning).opacity(0.12))
                    )
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No shifts today")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            Text("Daily Jobs can be assigned once a shift is on the roster.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

#Preview {
    NavigationStack {
        ManagerDailyJobsOverviewView()
    }
    .environment(RosterRepository())
}
