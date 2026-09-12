import SwiftUI

/// Lightweight "who's pending?" popup opened from the Dashboard's Pending
/// Timesheets metric card. Deliberately not the full ManagerTimesheetsView
/// (week nav, filters, bulk approve) — just the list this card's count is
/// summarizing, with a tap-through to the existing detail sheet to actually
/// act on one. Mirrors the same `status == .pending` set the card counts,
/// so the number on the card and the rows shown here never disagree.
struct PendingTimesheetsSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTimesheet: Timesheet? = nil

    private var pending: [Timesheet] {
        repo.timesheets
            .filter { $0.status == .pending }
            .sorted { ($0.submittedAt ?? .distantPast) > ($1.submittedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pending.isEmpty {
                    emptyState
                } else {
                    List(pending) { ts in
                        Button {
                            selectedTimesheet = ts
                        } label: {
                            row(for: ts)
                        }
                        .buttonStyle(.plain)
                        .pointerHover()
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pending Timesheets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedTimesheet) { ts in
                let shift = repo.shifts.first(where: { $0.id == ts.shiftId })
                ManagerTimesheetDetailSheet(timesheet: ts, shift: shift)
            }
        }
    }

    private func row(for ts: Timesheet) -> some View {
        let staff = repo.user(id: ts.staffId)
        let shift = repo.shifts.first(where: { $0.id == ts.shiftId })

        return HStack(spacing: 12) {
            Text(staff?.initials ?? "?")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.warning)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.warning.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(staff?.fullName ?? "Staff Member")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let shift {
                    Text("\(RosterFormat.date(shift.date)) · \(shift.rosteredStart)–\(shift.rosteredEnd)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            Text(String(format: "%.1fh", ts.workedHours))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Nothing pending")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            Text("Every submitted timesheet has been reviewed.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PendingTimesheetsSheet()
        .environment(RosterRepository())
}
