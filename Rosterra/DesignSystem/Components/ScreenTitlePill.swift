import SwiftUI

/// A fixed pill-shaped title badge shown at the top of each tab. Sits in the
/// navigation bar's `.principal` slot so it stays put while content scrolls
/// underneath, rather than using the standard large title.
struct ScreenTitlePill: View {
    let title: String
    var icon: String? = nil

    /// Scroll-driven collapse (0 = expanded, 1 = collapsed). Passed in by
    /// `screenTitlePill(_:icon:)`, which owns the toolbar and observes scroll —
    /// toolbar `.principal` content only updates when its owning view re-renders.
    var fraction: CGFloat = 0

    // The nav bar hosts `.principal` content and ignores render transforms
    // (`scaleEffect`/`opacity`), so the shrink is driven by real geometry —
    // interpolated font size and padding — which the bar re-measures.
    private var f: CGFloat { min(1, max(0, fraction)) }
    private var fontSize: CGFloat { 15 - 3 * f }          // 15 → 12
    private var hPad: CGFloat { 18 - 7 * f }              // 18 → 11
    private var vPad: CGFloat { 10 - 4 * f }              // 10 → 6
    private var tint: Color { Theme.brand.opacity(1 - 0.35 * f) }

    var body: some View {
        HStack(spacing: icon == nil ? 0 : 7 - 2 * f) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(tint)
                    .fixedSize()
            }
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(Capsule(style: .continuous).fill(Theme.card.opacity(1 - 0.15 * Double(f))))
        // iOS 26 toolbar slots crush flexible labels to 0pt — keep the capsule
        // sized to its content so the pill silhouette always shows.
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Staff Home company name — `.topBarLeading` on iOS 26 crushes flexible labels
/// to 0pt; an explicit text width keeps the title visible on the bell's row.
struct ToolbarLeadingTitlePill: View {
    let title: String

    private var labelWidth: CGFloat {
        min(240, UIScreen.main.bounds.width - 96)
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.brand)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: labelWidth, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule(style: .continuous).fill(Theme.card))
            .fixedSize(horizontal: true, vertical: false)
    }
}
