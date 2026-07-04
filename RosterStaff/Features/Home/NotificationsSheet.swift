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

    var body: some View {
        NavigationStack {
            Group {
                if activeMessages.isEmpty {
                    EmptyStateView(icon: "bell.slash",
                                   title: "No notifications",
                                   message: "You're all caught up.")
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
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
