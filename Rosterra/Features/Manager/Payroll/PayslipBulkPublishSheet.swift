import SwiftUI

/// Bulk-publish sheet — lets a manager publish any number of a pay period's
/// payslips in one action instead of opening and submitting each one
/// individually. `slips` is whatever the caller decides belongs in "this
/// pay run" (see `ManagerPayrollView.publishSheetSlips`, which excludes
/// archived payslips before this view ever sees them).
struct PayslipBulkPublishSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    let slips: [Payslip]
    let weekMonday: Date
    /// Called after a successful publish (with the count published), once
    /// this sheet has already dismissed itself — the presenting view surfaces
    /// its own toast rather than this sheet doing it mid-dismiss.
    var onPublished: (Int) -> Void

    @State private var selectedIds: Set<String> = []
    @State private var isPublishing = false
    @State private var errorMessage: String?

    private var rows: [Payslip] { slips.sorted { $0.staffName < $1.staffName } }
    /// Already-submitted rows are shown locked — only these can actually be published.
    private var toggleable: [Payslip] { rows.filter { $0.status != .submitted } }
    private var allSelected: Bool { !toggleable.isEmpty && selectedIds.count == toggleable.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedIds = allSelected ? [] : Set(toggleable.map(\.id))
                        }
                        Haptics.selection()
                    } label: {
                        HStack {
                            Text(allSelected ? "Deselect All" : "Select All")
                                .foregroundStyle(Theme.brand)
                            Spacer()
                            if !selectedIds.isEmpty {
                                Text("\(selectedIds.count) selected")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .disabled(toggleable.isEmpty)
                } header: {
                    Text(RosterFormat.weekRange(monday: weekMonday))
                }

                Section {
                    ForEach(rows) { slip in row(slip) }
                } footer: {
                    Text("Published payslips are locked here — use “Issue corrected copy” on the individual payslip to change one after publishing.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Publish Payslips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .safeAreaInset(edge: .bottom) { publishBar }
            .onAppear {
                guard selectedIds.isEmpty else { return }
                // Rows with no resolved hourly rate default to unselected —
                // a manager can still opt them in explicitly (or via Select
                // All), but a bulk publish shouldn't silently ship a $0
                // payslip because nobody happened to notice one row's badge.
                selectedIds = Set(toggleable.filter { $0.baseHourlyRate > 0 }.map(\.id))
            }
        }
    }

    private func row(_ slip: Payslip) -> some View {
        let employeeId = repo.displayEmployeeId(for: slip)
        let isPublished = slip.status == .submitted
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(slip.staffName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !employeeId.isEmpty {
                    Text("#\(employeeId)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                statusBadge(isPublished: isPublished)
                if slip.baseHourlyRate <= 0, !isPublished {
                    Label("No rate — review before including", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isPublished || selectedIds.contains(slip.id) },
                set: { on in
                    if on { selectedIds.insert(slip.id) } else { selectedIds.remove(slip.id) }
                }
            ))
            .labelsHidden()
            .tint(Theme.brand)
            .disabled(isPublished)
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(isPublished: Bool) -> some View {
        let tint = isPublished ? Theme.accent : Theme.warning
        return Text(isPublished ? "Published" : "Draft")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                publish()
            } label: {
                if isPublishing {
                    ProgressView().tint(.white)
                } else {
                    Text(selectedIds.isEmpty
                         ? "Publish Selected Payslips"
                         : "Publish Selected Payslips (\(selectedIds.count))")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedIds.isEmpty || isPublishing)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    private func publish() {
        guard !selectedIds.isEmpty, !isPublishing, let manager = repo.currentUser else { return }
        isPublishing = true
        errorMessage = nil
        let selected = rows.filter { selectedIds.contains($0.id) }
        Task {
            do {
                let count = try await repo.publishPayslips(selected, by: manager)
                isPublishing = false
                Haptics.success()
                dismiss()
                onPublished(count)
            } catch {
                isPublishing = false
                errorMessage = error.localizedDescription
                Haptics.error()
            }
        }
    }
}
