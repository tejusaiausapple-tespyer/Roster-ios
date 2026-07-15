import SwiftUI

/// Native bottom sheet for reporting an absence. Mirrors ReportAbsenceModal.
struct ReportAbsenceSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    let shift: Shift
    let existing: Timesheet?

    @State private var reason = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let absenceTint = Theme.warning

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Card {
                        HStack(spacing: 14) {
                            Image(systemName: "person.fill.xmark")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(absenceTint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Report absence")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(RosterFormat.date(shift.date)) · \(RosterFormat.time(shift.rosteredStart))–\(RosterFormat.time(shift.rosteredEnd))")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REASON (OPTIONAL)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                            TextField("Let your manager know why", text: $reason, axis: .vertical)
                                .lineLimit(3...5)
                        }
                    }

                    Text("This tells your manager you didn't attend this shift. You can undo it until they confirm.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let errorMessage {
                        Banner(kind: .error, title: errorMessage)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking { ProgressView().tint(.white) } else { Text("Report absence") }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: absenceTint))
                    .disabled(isWorking)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Absence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func submit() async {
        errorMessage = nil
        guard let user = repo.currentUser else { errorMessage = "Not signed in."; return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repo.reportAbsence(shiftId: shift.id, staffId: user.id, reason: reason)
            Haptics.warning()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
