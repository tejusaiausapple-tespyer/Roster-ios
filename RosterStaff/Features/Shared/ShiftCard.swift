import SwiftUI

/// Actions a shift card can surface, wired by the parent screen.
struct ShiftCardActions {
    var onSubmit: (() -> Void)? = nil
    var onReportAbsence: (() -> Void)? = nil
    var onUndoAbsence: (() -> Void)? = nil
    var onAddToCalendar: (() -> Void)? = nil
}

/// The core shift presentation, shared by Home and Roster.
/// Variants tune the emphasis; Roster hides inline actions in favour of swipe
/// actions / context menus, while Home shows the primary action inline.
/// `.hero` is the one surface in the app that keeps a brand gradient — every
/// other variant is a flat card, so the "today" shift stays visually special.
struct ShiftCard: View {
    enum Variant { case hero, standard, compact }

    let shift: Shift
    let timesheet: Timesheet?
    var variant: Variant = .standard
    var showDate: Bool = true
    var showsInlineActions: Bool = true
    var actions = ShiftCardActions()

    private var now: Date { Date() }
    private var status: StaffShiftDisplayStatus {
        BusinessRules.displayStatus(for: shift, timesheet: timesheet, at: now)
    }
    private var canSubmit: Bool {
        actions.onSubmit != nil && BusinessRules.canSubmitHours(shift: shift, timesheet: timesheet, at: now)
    }
    private var canReportAbsence: Bool {
        actions.onReportAbsence != nil && BusinessRules.canReportAbsence(shift: shift, timesheet: timesheet, at: now)
    }
    private var canUndoAbsence: Bool {
        actions.onUndoAbsence != nil && (timesheet?.isStaffReportedAbsence ?? false)
    }
    private var isHero: Bool { variant == .hero }

    /// A pending timesheet stays editable until approval, so the button
    /// remains — but its label must reflect that hours were already
    /// submitted, otherwise a successful submission looks like it failed.
    private var submitLabel: String {
        guard let ts = timesheet else { return "Submit hours" }
        return ts.status == .rejected ? "Resubmit hours" : "Update hours"
    }

    var body: some View {
        Group {
            if isHero {
                HeroCard(accentColor: Theme.brand) { inner }
            } else {
                Card(padding: variant == .compact ? 14 : 16, accentColor: Theme.style(for: status).tint) { inner }
            }
        }
    }

    private var primaryTextColor: Color { Theme.textPrimary }
    private var secondaryTextColor: Color { Theme.textSecondary }
    private var tertiaryTextColor: Color { Theme.textTertiary }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    if showDate {
                        Text(RosterFormat.date(shift.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tertiaryTextColor)
                    }
                    Text("\(RosterFormat.time(shift.rosteredStart)) – \(RosterFormat.time(shift.rosteredEnd))")
                        .font(isHero ? .title2.weight(.bold) : .headline)
                        .foregroundStyle(primaryTextColor)
                }
                Spacer()
                StatusPill(status, compact: variant == .compact)
            }

            HStack(spacing: 14) {
                if let location = shift.location, !location.isEmpty {
                    metaItem(icon: "mappin.and.ellipse", text: location)
                }
                metaItem(icon: "clock", text: RosterFormat.hours(shift.scheduledHours))
                if shift.breakMinutes > 0 {
                    metaItem(icon: "cup.and.saucer", text: "\(shift.breakMinutes)m break")
                }
            }

            if let notes = shift.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(secondaryTextColor)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(isHero ? Color.white.opacity(0.12) : Theme.background.opacity(0.6)))
            }

            if let ts = timesheet {
                timesheetSummary(ts)
            }

            if showsInlineActions {
                actionRow
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        let showAny = canSubmit || canReportAbsence || canUndoAbsence
        if showAny {
            HStack(spacing: 8) {
                if canSubmit {
                    Button(submitLabel) { actions.onSubmit?() }
                        .buttonStyle(InlinePillButtonStyle(tint: Theme.brandStrong, filled: true))
                }
                if canReportAbsence {
                    Button("Didn't attend") { actions.onReportAbsence?() }
                        .buttonStyle(InlinePillButtonStyle(tint: Theme.warning))
                }
                if canUndoAbsence {
                    Button("Undo absence") { actions.onUndoAbsence?() }
                        .buttonStyle(InlinePillButtonStyle(tint: Theme.textSecondary))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func timesheetSummary(_ ts: Timesheet) -> some View {
        if ts.status == .approved || ts.status == .pending || ts.status == .rejected {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(tertiaryTextColor)
                Text("Worked \(RosterFormat.hours(ts.workedHours)) · \(RosterFormat.time(ts.actualStart))–\(RosterFormat.time(ts.actualEnd))")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }
            if ts.status == .rejected, let reason = ts.rejectedReason, !reason.isEmpty {
                Text("Rejected: \(reason)")
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }
        }
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(tertiaryTextColor)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(secondaryTextColor)
        }
    }
}
