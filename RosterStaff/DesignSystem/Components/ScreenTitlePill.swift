import SwiftUI

/// A fixed pill-shaped title badge shown at the top of each tab. Sits in the
/// navigation bar's `.principal` slot so it stays put while content scrolls
/// underneath, rather than using the standard large title.
struct ScreenTitlePill: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: icon == nil ? 0 : 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
                    .fixedSize()
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.brand)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule(style: .continuous).fill(Theme.card))
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
