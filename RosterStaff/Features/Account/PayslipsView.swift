import SwiftUI

/// Staff → Account → Payslips: submitted payslips only, grouped by pay
/// period. Visibility is enforced by the payslips Firestore rules (staff can
/// only ever read their own submitted/archived documents) — the repository
/// listener already queries exactly that.
struct PayslipsView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var selected: Payslip?

    private var slips: [Payslip] {
        repo.payslips.sorted { $0.periodStart > $1.periodStart }
    }

    var body: some View {
        List {
            if slips.isEmpty {
                EmptyStateView(
                    icon: "banknote",
                    title: "No payslips yet",
                    message: "Payslips appear here once your manager finalises and submits them."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(groupedByMonth, id: \.0) { month, monthSlips in
                    Section(month) {
                        ForEach(monthSlips) { slip in
                            Button {
                                selected = slip
                            } label: {
                                row(slip)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Payslips")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { slip in
            PayslipPDFSheet(slip: slip, isManager: false)
        }
    }

    /// (Month label, payslips) newest first.
    private var groupedByMonth: [(String, [Payslip])] {
        let groups = Dictionary(grouping: slips) { slip -> String in
            guard let date = RosterCalendar.dateFromKey(slip.periodStart) else { return "Earlier" }
            return RosterFormat.monthYear(date)
        }
        // Order months by the newest payslip they contain.
        return groups.sorted { lhs, rhs in
            (lhs.value.first?.periodStart ?? "") > (rhs.value.first?.periodStart ?? "")
        }
    }

    private func row(_ slip: Payslip) -> some View {
        let totals = slip.totals
        return HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.brand.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(RosterFormat.weekRange(monday: RosterCalendar.dateFromKey(slip.periodStart) ?? Date()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Paid \(RosterFormat.date(slip.payDate))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    Text("Gross \(RosterFormat.money(totals.gross))")
                    Text("Net \(RosterFormat.money(totals.net))")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(RosterFormat.money(totals.net))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
                PayslipStatusPill(status: slip.status)
            }
        }
        .padding(.vertical, 2)
    }
}
