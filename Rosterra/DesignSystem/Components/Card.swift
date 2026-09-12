import SwiftUI

/// A flat grouped-style surface used for most content groupings. Supports an optional
/// left vertical accent stripe. No shadow — depth comes from the background/card color
/// contrast, matching native List(.insetGrouped) rows.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = Theme.cornerLarge
    var accentColor: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            if let accentColor {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 4)
                    .padding(.vertical, padding)
                    .padding(.leading, 12)
            }
            
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        )
    }
}

/// A card reserved for the single hero moment in the app (Home "today" card) and submission sheets.
/// Features a neutral background with a distinct left-side vertical brand accent stripe.
///
/// NOTE: this is a *solid* card (`Theme.card` fill), NOT Liquid Glass — despite the
/// legacy name. Renamed `GlassCard` → `HeroCard` so it isn't mistaken for a real
/// glass surface (glass belongs on the navigation layer only; see `Theme.glassSurface`).
struct HeroCard<Content: View>: View {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = Theme.cornerLarge
    var accentColor: Color = Theme.brand
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accentColor)
                .frame(width: 5)
                .padding(.vertical, padding)
                .padding(.leading, 12)
            
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        )
    }
}
