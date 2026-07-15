import SwiftUI

/// Shown before generating draft payslips when one or more published,
/// already-ended shifts in the period don't have an approved timesheet.
/// Lets the manager see exactly who/what is holding up a complete payroll
/// run, then either generate anyway (for whoever IS ready) or go chase
/// the rest first.
struct PayrollGapsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let gaps: [PayrollGapItem]
    let weekLabel: String
    let onGenerateAnyway: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "\(gaps.count) shift\(gaps.count == 1 ? "" : "s") in \(weekLabel) will be left out of this payroll run until resolved.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.warning)
                    .listRowBackground(Color.clear)
                }

                Section("Needs action") {
                    ForEach(gaps) { gap in
                        gapRow(gap)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 76)
            }
            .overlay(alignment: .bottom) { generateAnywayButton }
            .navigationTitle("Incomplete Timesheets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var generateAnywayButton: some View {
        Button {
            dismiss()
            onGenerateAnyway()
        } label: {
            Text("Generate for the rest anyway")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .glassProminentSurface(in: Capsule(style: .continuous), tint: Theme.brand)
        .shadow(color: Theme.brand.opacity(0.35), radius: 14, x: 0, y: 6)
        .padding(.bottom, 20)
    }

    private func gapRow(_ gap: PayrollGapItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gap.staffName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(RosterFormat.date(gap.date)) · \(RosterFormat.time(gap.rosteredStart))–\(RosterFormat.time(gap.rosteredEnd))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Text(gap.reason.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(reasonTint(gap.reason))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(reasonTint(gap.reason).opacity(0.12)))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func reasonTint(_ reason: PayrollGapItem.Reason) -> Color {
        switch reason {
        case .notSubmitted, .draftNotSubmitted: return Theme.textTertiary
        case .pendingApproval: return Theme.brand
        case .rejected: return Theme.error
        case .absenceUnconfirmed: return Theme.warning
        }
    }
}
