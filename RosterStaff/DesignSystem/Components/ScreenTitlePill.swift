import SwiftUI

/// A fixed pill-shaped title badge shown at the top of each tab. Sits in the
/// navigation bar's `.principal` slot so it stays put while content scrolls
/// underneath, rather than using the standard large title.
struct ScreenTitlePill: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.brand)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule(style: .continuous).fill(Theme.card))
    }
}
