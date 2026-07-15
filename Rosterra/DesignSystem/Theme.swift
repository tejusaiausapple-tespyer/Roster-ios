import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }

    /// A color that resolves differently in light vs dark mode.
    static func dynamic(light: UInt, dark: UInt) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 08) & 0xff) / 255,
                blue: CGFloat((hex >> 00) & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

/// The app-wide design tokens. This is a calm, native, content-first system:
/// one brand accent used sparingly, flat grouped surfaces instead of floating
/// glass/shadow, and Dynamic Type text styles rather than fixed point sizes.
/// The single exception is the Home "today" hero, which keeps a gradient so
/// it reads as the one genuinely special moment on screen.
enum Theme {
    // MARK: Brand
    static let brand = Color.dynamic(light: 0x4F46E5, dark: 0x818CF8)          // indigo 600 / 400
    static let brandStrong = Color(hex: 0x4F46E5)
    static let accent = Color.dynamic(light: 0x059669, dark: 0x34D399)         // emerald
    /// Warnings — pending / awaiting submission / absence.
    static let warning = Color.dynamic(light: 0xB45309, dark: 0xF59E0B)
    /// Errors / destructive.
    static let error = Color.dynamic(light: 0xDC2626, dark: 0xEF4444)

    /// Reserved for the single hero surface (Home "today" card). Avoid elsewhere.
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x4338CA)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Surfaces
    /// Screen background (below grouped content).
    static let background = Color.dynamic(light: 0xF2F3F7, dark: 0x000000)
    /// Card / row surface.
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let separator = Color.dynamic(light: 0xE5E7EB, dark: 0x2C2C2E)

    // MARK: Text
    static let textPrimary = Color.dynamic(light: 0x0F172A, dark: 0xF3F4F6)
    static let textSecondary = Color.dynamic(light: 0x5B6472, dark: 0x9CA7B8)
    static let textTertiary = Color.dynamic(light: 0x94A3B8, dark: 0x6B7688)

    // MARK: Semantic status palettes (fill/text used by StatusPill)
    struct StatusStyle {
        let tint: Color
        let soft: Color
    }

    static func style(for status: StaffShiftDisplayStatus) -> StatusStyle {
        switch status {
        case .scheduled:          return StatusStyle(tint: Color(hex: 0x3B82F6), soft: Color(hex: 0x3B82F6, alpha: 0.14))
        case .awaitingSubmission: return StatusStyle(tint: Color(hex: 0xB45309), soft: Color(hex: 0xB45309, alpha: 0.14))
        case .draft:              return StatusStyle(tint: Color(hex: 0x6B7280), soft: Color(hex: 0x6B7280, alpha: 0.14))
        case .pending:            return StatusStyle(tint: Color(hex: 0xB45309), soft: Color(hex: 0xB45309, alpha: 0.14))
        case .approved:           return StatusStyle(tint: Color(hex: 0x059669), soft: Color(hex: 0x059669, alpha: 0.14))
        case .rejected:           return StatusStyle(tint: Color(hex: 0xDC2626), soft: Color(hex: 0xDC2626, alpha: 0.14))
        case .absentReported:     return StatusStyle(tint: Color(hex: 0xC2410C), soft: Color(hex: 0xC2410C, alpha: 0.14))
        case .absent:             return StatusStyle(tint: Color(hex: 0xDC2626), soft: Color(hex: 0xDC2626, alpha: 0.14))
        }
    }

    static func style(for status: TimesheetStatus) -> StatusStyle {
        style(for: StaffShiftDisplayStatus(rawValue: status.rawValue) ?? .pending)
    }

    // MARK: Metrics
    static let cornerLarge: CGFloat = 20
    static let cornerMedium: CGFloat = 14
    static let cornerSmall: CGFloat = 10
    static let screenPadding: CGFloat = 16

    /// Widest the primary content lane grows on large iPad / Mac windows before
    /// it is centered, so wide displays don't stretch layouts into sparse boxes.
    static let maxContentWidth: CGFloat = 1400
    /// Comfortable minimum width for a single day column in the week scheduler.
    /// Below this the grid scrolls horizontally instead of squishing columns.
    static let minColumnWidth: CGFloat = 168
}

/// Dynamic-Type-friendly text style helpers, used in place of fixed
/// `.system(size:)` calls so every label scales with the user's preferred
/// text size and respects bold-text / accessibility settings.
extension Text {
    /// Large section/screen title (maps to `.title2`, bold).
    func styleTitle() -> Text { self.font(.title2.weight(.bold)) }

    /// Card/list primary value (maps to `.headline`).
    func styleHeadline() -> Text { self.font(.headline) }

    /// Standard body copy.
    func styleBody() -> Text { self.font(.body) }

    /// Secondary/supporting copy.
    func styleSubheadline() -> Text { self.font(.subheadline) }

    /// Small metadata (labels, timestamps, captions).
    func styleCaption() -> Text { self.font(.caption) }

    /// Emphasised small metadata (section headers, pill text).
    func styleCaptionStrong() -> Text { self.font(.caption.weight(.semibold)) }
}

// MARK: - Liquid Glass support (iOS/iPadOS/macOS 26+) with iOS 17–25 fallback
//
// The 2026 design language ("Liquid Glass") is reserved for the *navigation
// layer* that floats above content — bars, control clusters, and floating
// buttons — never for the content layer (lists, cards, the schedule grid).
//
// These helpers apply the real `glassEffect` APIs when built with the iOS 26
// SDK (Xcode 26 / Swift 6.2+) and running on iOS 26+, and otherwise fall back
// to an `.ultraThinMaterial` surface. The `#if compiler(>=6.2)` guard keeps the
// project compiling on older Xcode toolchains that lack the glass symbols.
extension View {
    /// A translucent navigation-layer surface. Liquid Glass on iOS 26+,
    /// `.ultraThinMaterial` (with a hairline border) on earlier versions.
    /// Use for bars, control clusters, and floating chips — not content cards.
    ///
    /// `.contentShape(shape)` is applied on every branch: unlike a solid
    /// `background(fill)`, a `glassEffect` does NOT make the surface
    /// hit-testable, so glass buttons without it only respond on their
    /// glyph/text pixels (the "Add Shift + is unresponsive" bug).
    @ViewBuilder
    func glassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Build the Glass value inside a closure so the @ViewBuilder branch
            // contains a single view expression (imperative statements are not
            // allowed directly in a ViewBuilder context).
            self.contentShape(shape)
                .glassEffect(
                    {
                        var glass: Glass = .regular
                        if let tint { glass = glass.tint(tint) }
                        if interactive { glass = glass.interactive() }
                        return glass
                    }(),
                    in: shape
                )
        } else {
            self
                .contentShape(shape)
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(Theme.separator, lineWidth: 1))
        }
        #else
        self
            .contentShape(shape)
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.stroke(Theme.separator, lineWidth: 1))
        #endif
    }

    /// Capsule convenience for the common pill-shaped control case.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassSurface(in: Capsule(style: .continuous), tint: tint, interactive: interactive)
    }

    /// A prominent (call-to-action) glass surface — tinted Liquid Glass on
    /// iOS 26+, a solid tinted fill on earlier versions. For primary buttons.
    /// `.contentShape(shape)` for the same hit-testing reason as glassSurface.
    @ViewBuilder
    func glassProminentSurface<S: Shape>(in shape: S, tint: Color) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.contentShape(shape)
                .glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.contentShape(shape)
                .background(shape.fill(tint))
        }
        #else
        self.contentShape(shape)
            .background(shape.fill(tint))
        #endif
    }
}
