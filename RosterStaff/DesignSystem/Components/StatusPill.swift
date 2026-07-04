import SwiftUI

/// A compact status badge with a leading dot.
struct StatusPill: View {
    let status: StaffShiftDisplayStatus
    var compact: Bool = false

    init(_ status: StaffShiftDisplayStatus, compact: Bool = false) {
        self.status = status
        self.compact = compact
    }

    init(_ status: TimesheetStatus, compact: Bool = false) {
        self.status = StaffShiftDisplayStatus(rawValue: status.rawValue) ?? .pending
        self.compact = compact
    }

    private var style: Theme.StatusStyle { Theme.style(for: status) }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(style.tint)
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(style.tint)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(Capsule().fill(style.soft))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.title)")
    }
}
