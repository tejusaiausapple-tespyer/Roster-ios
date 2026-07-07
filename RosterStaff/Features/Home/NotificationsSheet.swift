import SwiftUI

/// The in-app messages inbox (manager -> staff tasks). Mirrors the Home
/// notifications modal: active (non-expired) messages, newest first, auto-marked
/// read on open.
struct NotificationsSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetent: PresentationDetent = .medium

    private var activeMessages: [Message] {
        repo.messages.filter { $0.isActive() }.sorted { $0.sentAt > $1.sentAt }
    }

    private var dailyJobs: [DailyJobAssignment] {
        repo.activeDailyJobsForStaff
    }

    private var dailyJobsOnly: Bool {
        !dailyJobs.isEmpty && activeMessages.isEmpty
    }

    private var isLargeDetent: Bool {
        selectedDetent == .large
    }

    private var dailyJobsLayout: DailyJobsLayout {
        guard isLargeDetent else { return .compact }
        return dailyJobsOnly ? .expandedFillingSheet : .expandedInScroll
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeMessages.isEmpty && dailyJobs.isEmpty {
                    EmptyStateView(icon: "bell.slash",
                                   title: "No notifications",
                                   message: "You're all caught up.")
                } else if dailyJobsLayout == .expandedFillingSheet {
                    VStack(spacing: 0) {
                        dailyJobsSection(layout: .expandedFillingSheet)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Theme.background.ignoresSafeArea())
                } else {
                    FadedScrollView("notificationsSheet") {
                        VStack(spacing: 12) {
                            if !dailyJobs.isEmpty {
                                dailyJobsSection(layout: dailyJobsLayout)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 6) {
                        Text("Notifications")
                            .font(.headline)
                        if !dailyJobs.isEmpty {
                            dailyJobsProgressBadge
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .task {
            let unread = activeMessages.filter { !$0.read }.map { $0.id }
            await repo.markMessagesRead(unread)
        }
    }

    // MARK: - Daily Jobs (assigned per shift by the manager; visible until
    // end of day — see docs/daily-jobs-feature.md)

    private enum DailyJobsLayout {
        /// Medium detent: capped nested scroll so the sheet stays usable.
        case compact
        /// Large detent, jobs only: card fills the sheet; list scrolls inside.
        case expandedFillingSheet
        /// Large detent with messages below: no nested scroll; outer scroll handles overflow.
        case expandedInScroll
    }

    private var dailyJobsProgressBadge: some View {
        let done = dailyJobs.filter(\.completed).count
        let total = dailyJobs.count
        let tint = repo.pendingDailyJobCount > 0 ? Theme.warning : Theme.accent

        return Text("\(done)/\(total) Done")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
            .accessibilityLabel("\(done) of \(total) daily jobs done")
    }

    private func dailyJobsSection(layout: DailyJobsLayout) -> some View {
        Card(accentColor: repo.pendingDailyJobCount > 0 ? Theme.warning : Theme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Daily Jobs", systemImage: "checklist")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                dailyJobsList(layout: layout)
            }
            .frame(maxHeight: layout == .expandedFillingSheet ? .infinity : nil, alignment: .top)
        }
        .frame(maxHeight: layout == .expandedFillingSheet ? .infinity : nil, alignment: .top)
    }

    @ViewBuilder
    private func dailyJobsList(layout: DailyJobsLayout) -> some View {
        switch layout {
        case .compact:
            FadedScrollView("dailyJobsCompact", fadeColor: Theme.card) {
                dailyJobsListContent
            }
            .frame(maxHeight: 320)
        case .expandedFillingSheet:
            FadedScrollView("dailyJobsExpanded", fadeColor: Theme.card) {
                dailyJobsListContent
            }
            .frame(maxHeight: .infinity)
        case .expandedInScroll:
            dailyJobsListContent
        }
    }

    private var dailyJobsListContent: some View {
        VStack(spacing: 10) {
            ForEach(dailyJobs) { job in
                jobRow(job)
            }
        }
        .padding(.vertical, 4)
    }

    private func jobRow(_ job: DailyJobAssignment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: job.completed ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(job.completed ? Theme.accent : Theme.textTertiary)

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

            Button {
                toggle(job)
            } label: {
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
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(job.completed ? Theme.accent.opacity(0.06) : Theme.background)
        )
        .animation(.easeInOut(duration: 0.18), value: job.completed)
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
