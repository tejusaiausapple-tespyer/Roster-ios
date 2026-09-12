import SwiftUI

/// Staff Daily Jobs page, pushed from the Home card (not its own tab).
/// Lives inside HomeView's NavigationStack — do not wrap another stack here.
struct DailyJobsView: View {
    @Environment(RosterRepository.self) private var repo
    @State private var toastMessage: ToastMessage?
    @State private var inFlightJobIds: Set<String> = []

    private var dailyJobs: [DailyJobAssignment] {
        repo.activeDailyJobsForStaff
    }

    private var doneCount: Int {
        dailyJobs.filter(\.completed).count
    }

    var body: some View {
        Group {
            if dailyJobs.isEmpty {
                EmptyStateView(
                    icon: "checklist",
                    title: "No jobs today",
                    message: "Your manager hasn't assigned any daily jobs for today yet."
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        // Already manager-order-sorted (activeDailyJobsForStaff) —
                        // the number is just this row's live position in that
                        // array, so it stays sequential if the manager reorders.
                        ForEach(Array(dailyJobs.enumerated()), id: \.element.id) { index, job in
                            jobRow(job, number: index + 1)
                        }
                    }
                    .padding(Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .platformScrollIndicators()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Daily Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 6) {
                    Text("Daily Jobs")
                        .font(.headline)
                    if !dailyJobs.isEmpty {
                        progressBadge
                    }
                }
            }
        }
        .macRefreshable {
            await repo.refreshFromServer()
        }
        .toast($toastMessage)
    }

    private var progressBadge: some View {
        let tint = repo.pendingDailyJobCount > 0 ? Theme.warning : Theme.accent
        return Text("\(doneCount)/\(dailyJobs.count) Done")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
            .accessibilityLabel("\(doneCount) of \(dailyJobs.count) daily jobs done")
    }

    private func jobRow(_ job: DailyJobAssignment, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.textTertiary.opacity(0.12)))
            // No checkmark for a completed job — the card's own green fill
            // already says "done"; a second green tick was redundant.
            if !job.completed {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(job.completed ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(job.completed, color: Theme.textTertiary)
                if job.completed, let at = job.completedAt {
                    Text("Done \(RosterFormat.time(at))")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer(minLength: 8)

            let isWorking = inFlightJobIds.contains(job.id)
            Button {
                toggle(job)
            } label: {
                if isWorking {
                    ProgressView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                } else {
                    Text(job.completed ? "Undo" : "Complete")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(job.completed
                                           ? Theme.textTertiary.opacity(0.15)
                                           : Theme.brand)
                        )
                        .foregroundStyle(job.completed ? Theme.textSecondary : .white)
                }
            }
            .buttonStyle(.plain)
            .pointerHover()
            .disabled(isWorking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(job.completed ? Theme.accent.opacity(0.06) : Theme.card)
        )
        .animation(.easeInOut(duration: 0.18), value: job.completed)
    }

    private func toggle(_ job: DailyJobAssignment) {
        guard !inFlightJobIds.contains(job.id) else { return }
        inFlightJobIds.insert(job.id)
        Task {
            defer { inFlightJobIds.remove(job.id) }
            do {
                try await repo.setDailyJobCompleted(job, completed: !job.completed)
                Haptics.tabChange()
            } catch {
                toastMessage = ToastMessage(kind: .error, text: "Couldn't update \"\(job.title)\". \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}

#Preview {
    DailyJobsView()
        .environment(RosterRepository())
}
