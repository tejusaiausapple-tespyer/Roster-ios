import SwiftUI

struct ManagerTimesheetDetailSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss
    
    let timesheet: Timesheet
    let shift: Shift?
    var isEmbedded: Bool = false

    @State private var managerNotes: String = ""
    @State private var showRejectionDialog = false
    @State private var rejectedReason: String = ""
    @State private var isSubmitting = false
    @State private var toast: ToastMessage?
    @State private var rejectError: String?

    init(timesheet: Timesheet, shift: Shift?, isEmbedded: Bool = false) {
        self.timesheet = timesheet
        self.shift = shift
        self.isEmbedded = isEmbedded
        _managerNotes = State(initialValue: timesheet.managerNotes ?? "")
    }
    
    private var staffMember: AppUser? {
        repo.allUsers.first(where: { $0.id == timesheet.staffId })
    }
    
    private var rosteredHours: Double {
        shift?.scheduledHours ?? 0.0
    }
    
    private var actualHours: Double {
        timesheet.workedHours
    }
    
    private var rate: Double {
        staffMember?.hourlyRate ?? 25.0
    }
    
    private var rosteredCost: Double {
        rosteredHours * rate
    }
    
    private var actualCost: Double {
        actualHours * rate
    }
    
    private var hoursMismatch: Bool {
        abs(rosteredHours - actualHours) > 0.01
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Staff Profile Card
                        staffHeaderCard
                        
                        // Comparison Dashboard Grid
                        comparisonCard
                        
                        // Financial Variance Widget
                        financialVarianceCard
                        
                        // Staff Notes Card
                        if let staffNotes = timesheet.staffNotes, !staffNotes.isEmpty {
                            notesCard(title: "Staff Notes", content: staffNotes, icon: "note.text")
                        }
                        
                        // Manager Notes Editor
                        managerNotesInput
                        
                        // If already approved/rejected, show status details
                        statusHistoryCard
                    }
                    .padding(Theme.screenPadding)
                }
                .safeAreaInset(edge: .bottom) {
                    if timesheet.status == .pending {
                        pinnedActionBar
                    }
                }
            }
            .navigationTitle("Timesheet Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showRejectionDialog) {
                rejectionDialogSheet
            }
            .toast($toast)
        }
    }
    
    // MARK: - Subviews
    
    private var staffHeaderCard: some View {
        HStack(spacing: 16) {
            Text(staffMember?.initials ?? "?")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.brand)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Theme.brand.opacity(0.12)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(staffMember?.fullName ?? "Staff Member")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                
                Text(staffMember?.employmentType?.rawValue.capitalized ?? "Casual")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            
            if let date = timesheet.submittedAt {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Submitted")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                    Text(date, style: .date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.separator, lineWidth: 1))
    }
    
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SHIFT COMPARISON")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            
            Divider().overlay(Theme.separator)
            
            HStack(spacing: 0) {
                // Rostered details
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rostered")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                    
                    if let shift = shift {
                        Text("\(shift.rosteredStart) - \(shift.rosteredEnd)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(shift.breakMinutes)m break")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("No rostered shift")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Divider line
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                
                // Actual details
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actual Worked")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(hoursMismatch ? Theme.warning : Theme.brand)
                    
                    Text("\(timesheet.actualStart) - \(timesheet.actualEnd)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(timesheet.actualBreakMinutes)m break")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.separator, lineWidth: 1))
    }
    
    private var financialVarianceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FINANCIAL ESTIMATES & VARIANCE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            
            Divider().overlay(Theme.separator)
            
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hours")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    
                    HStack(spacing: 8) {
                        Text(String(format: "%.1fh worked", actualHours))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(hoursMismatch ? Theme.warning : Theme.textPrimary)
                        
                        if hoursMismatch {
                            Text(String(format: "(Rostered: %.1fh)", rosteredHours))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Est. Wage cost")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    
                    Text("$\(String(format: "%.2f", actualCost))")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.separator, lineWidth: 1))
    }
    
    private func notesCard(title: String, content: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.textTertiary)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(content)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.separator, lineWidth: 1))
    }
    
    private var managerNotesInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGER COMMENTS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            
            TextEditor(text: $managerNotes)
                .frame(height: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium).strokeBorder(Theme.separator, lineWidth: 1))
                .disabled(timesheet.status != .pending || isSubmitting)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.separator, lineWidth: 1))
    }
    
    private var statusHistoryCard: some View {
        Group {
            if timesheet.status == .approved {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Approved")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        if let appAt = timesheet.approvedAt {
                            // approvedAt is an ISO-8601 string; render it as a
                            // readable date-time instead of the raw value.
                            Text("Approved on \(FS.isoFormatter.date(from: appAt).map { RosterFormat.dateTime($0) } ?? appAt)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.accent.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
            } else if timesheet.status == .rejected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(Theme.warning)
                        Text("Rejected")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    
                    if let reason = timesheet.rejectedReason, !reason.isEmpty {
                        Text("Reason: \(reason)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Theme.cornerLarge).fill(Theme.warning.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge).strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1))
            }
        }
    }
    
    // Pinned glass action bar so Approve / Reject are always visible without
    // scrolling. Content scrolls beneath the frosted material (a glass toolbar).
    private var pinnedActionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.separator)
            actionButtons
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                showRejectionDialog = true
            } label: {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Reject")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassSurface(
                    in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous),
                    tint: Theme.warning.opacity(0.14),
                    interactive: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)

            Button {
                approve()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle")
                        Text("Approve")
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassProminentSurface(
                    in: RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous),
                    tint: Theme.accent
                )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
    }
    
    private var rejectionDialogSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Specify a reason for rejecting this timesheet. The staff member will see this message and must resubmit their actual times.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                if let rejectError {
                    Banner(kind: .error, title: rejectError)
                }
                
                TextField("E.g. Hours worked don't match store clock-in sheet", text: $rejectedReason)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.background))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerMedium).strokeBorder(Theme.separator, lineWidth: 1))
                
                Spacer()
                
                Button {
                    reject()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Reject Timesheet")
                        }
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerMedium).fill(Theme.warning))
                }
                .disabled(rejectedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
            .padding(Theme.screenPadding)
            .navigationTitle("Reject Timesheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRejectionDialog = false }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func approve() {
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await repo.approveTimesheet(id: timesheet.id, managerNotes: managerNotes.isEmpty ? nil : managerNotes)
                Haptics.success()
                dismiss()
            } catch {
                // Keep the sheet open so nothing the manager typed is lost.
                toast = ToastMessage(kind: .error, text: "Approve failed. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    private func reject() {
        isSubmitting = true
        rejectError = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await repo.rejectTimesheet(
                    id: timesheet.id,
                    reason: rejectedReason,
                    managerNotes: managerNotes.isEmpty ? nil : managerNotes
                )
                Haptics.success()
                showRejectionDialog = false
                dismiss()
            } catch {
                // Shown inside the rejection sheet (a toast underneath would
                // be hidden by it); the typed reason is preserved.
                rejectError = "Reject failed. \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }
}
