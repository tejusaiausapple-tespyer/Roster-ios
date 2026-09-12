#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacStatusPill: View {
    private let text: String
    private let foreground: Color
    private let background: Color
    private let border: Color
    private let icon: String?

    init(
        text: String,
        foreground: Color,
        background: Color,
        border: Color,
        icon: String? = nil
    ) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.border = border
        self.icon = icon
    }

    init(style: MacStatusStyle, icon: String? = nil) {
        self.text = style.label
        self.foreground = style.foreground
        self.background = style.background
        self.border = style.border
        self.icon = icon
    }

    init(shiftStatus: StaffShiftDisplayStatus) {
        self.init(style: MacStatusStyle.forShift(shiftStatus))
    }

    init(timesheetStatus: TimesheetStatus) {
        self.init(style: MacStatusStyle.forTimesheet(timesheetStatus))
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(text)
                .font(MacType.badge)
                .tracking(0.2)
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }
}

struct MacCountBadge: View {
    let count: Int
    var prominent: Bool = false

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(MacType.badge)
                .foregroundStyle(prominent ? Color.white : MacColor.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    prominent ? MacColor.brandStrong : MacColor.accent.opacity(0.16),
                    in: Capsule()
                )
        }
    }
}
#endif
