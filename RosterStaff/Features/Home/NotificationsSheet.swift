import SwiftUI

/// The in-app messages inbox (manager -> staff tasks). Mirrors the Home
/// notifications modal: active (non-expired) messages, newest first, auto-marked
/// read on open.
struct NotificationsSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    private var activeMessages: [Message] {
        repo.messages.filter { $0.isActive() }.sorted { $0.sentAt > $1.sentAt }
    }

    private var dailyJobs: [DailyJobAssignment] {
        repo.activeDailyJobsForStaff
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeMessages.isEmpty && dailyJobs.isEmpty {
                    EmptyStateView(icon: "bell.slash",
                                   title: "No notifications",
                                   message: "You're all caught up.")
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if !dailyJobs.isEmpty {
                                dailyJobsSection
                            }
                            ForEach(activeMessages) { message in
                                messageCard(message)
                            }
                        }
                        .padding(20)
                    }
                    .background(Theme.background.ignoresSafeArea())
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            let unread = activeMessages.filter { !$0.read }.map { $0.id }
            await repo.markMessagesRead(unread)
        }
    }

    // MARK: - Daily Jobs (assigned per shift by the manager; visible until
    // the shift ends — see docs/daily-jobs-feature.md)

    private var dailyJobsSection: some View {
        Card(accentColor: repo.pendingDailyJobCount > 0 ? Theme.warning : Theme.accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Daily Jobs", systemImage: "checklist")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(dailyJobs.filter(\.completed).count)/\(dailyJobs.count) done")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(repo.pendingDailyJobCount > 0 ? Theme.warning : Theme.accent)
                }

                ForEach(dailyJobs) { job in
                    HStack(spacing: 10) {
                        Image(systemName: job.completed ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(job.completed ? Theme.accent : Theme.textTertiary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(job.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .strikethrough(job.completed, color: Theme.textTertiary)
                            if job.completed, let at = job.completedAt {
                                Text("Done \(RosterFormat.dateTime(at))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                        }

                        Spacer()

                        Button {
                            toggle(job)
                        } label: {
                            Text(job.completed ? "Undo" : "Complete")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(job.completed
                                                   ? Theme.textTertiary.opacity(0.15)
                                                   : Theme.brand)
                                )
                                .foregroundStyle(job.completed ? Theme.textSecondary : .white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func toggle(_ job: DailyJobAssignment) {
        Task {
            try? await repo.setDailyJobCompleted(job, completed: !job.completed)
            Haptics.tabChange()
        }
    }

    private func messageCard(_ message: Message) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(message.senderName ?? "Manager")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let date = message.sentDate {
                        Text(RosterFormat.dateTime(date))
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                let lines = message.bodyLines
                if lines.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(Theme.brand).frame(width: 4, height: 4).padding(.top, 6)
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } else {
                    Text(message.body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
