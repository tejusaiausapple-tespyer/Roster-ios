#if targetEnvironment(macCatalyst)
import SwiftUI

extension View {
    /// iOS 26 / macOS 26 navigation subtitle in the unified titlebar.
    @ViewBuilder
    func macNavigationSubtitle(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            if #available(iOS 26.0, *) {
                self.navigationSubtitle(text)
            } else {
                self
            }
        } else {
            self
        }
    }

    /// Liquid Glass surface for floating chrome (toasts, overlays). Content stays opaque.
    @ViewBuilder
    func macGlassSurface(
        cornerRadius: CGFloat = MacRadius.medium
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(MacColor.cardBorder, lineWidth: 1))
        }
    }

    @ViewBuilder
    func macChromeBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(.bar)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.35)
                }
        } else {
            self
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(MacColor.separator)
                        .frame(height: 1)
                }
        }
    }

    @ViewBuilder
    func macBackgroundExtension() -> some View {
        if #available(iOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }

    @ViewBuilder
    func macButton(
        _ variant: MacButtonVariant = .bordered,
        size: MacButtonSize = .medium,
        fullWidth: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *), !fullWidth {
            self.modifier(MacGlassButtonModifier(variant: variant, size: size))
        } else {
            self.buttonStyle(MacButtonStyle(variant: variant, size: size, fullWidth: fullWidth))
        }
    }

    /// A quiet system control for routine Mac actions. The system supplies
    /// the control geometry and interaction states; only its neutral palette
    /// is specified so it stays white with dark text instead of inheriting
    /// the app's indigo accent.
    func macNeutralPill(size: MacButtonSize = .medium) -> some View {
        self
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .controlSize(size.controlSize)
    }

    /// Accent-tinted Liquid Glass for a primary action inside a Mac detail
    /// workspace. Kept separate from `.prominent`, whose neutral white style
    /// is used by existing toolbar and form actions throughout the app.
    @ViewBuilder
    func macAccentGlassPill(size: MacButtonSize = .medium) -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .tint(MacColor.accent)
                .controlSize(size.controlSize)
        } else {
            self.macButton(.prominent, size: size)
        }
    }

    /// A glass capsule that keeps a visible outline and fill against white
    /// detail headers, including while disabled.
    func macVisibleGlassPill(
        primary: Bool = false,
        size: MacButtonSize = .medium
    ) -> some View {
        self.buttonStyle(MacVisibleGlassPillStyle(primary: primary, size: size))
    }
}

private struct MacVisibleGlassPillStyle: ButtonStyle {
    let primary: Bool
    let size: MacButtonSize

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(primary ? MacColor.accent : MacColor.textPrimary)
            .padding(.horizontal, size.horizontalPadding + 2)
            .padding(.vertical, size.verticalPadding)
            .background(
                primary
                    ? MacColor.accent.opacity(isEnabled ? 0.14 : 0.07)
                    : MacColor.cardBackground.opacity(0.72),
                in: Capsule()
            )
            .macGlassSurface(cornerRadius: MacRadius.pill)
            .overlay(
                Capsule().strokeBorder(
                    primary
                        ? MacColor.accent.opacity(isEnabled ? 0.42 : 0.2)
                        : MacColor.cardBorder,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.72)
    }
}

@available(iOS 26.0, *)
private struct MacGlassButtonModifier: ViewModifier {
    let variant: MacButtonVariant
    let size: MacButtonSize

    func body(content: Content) -> some View {
        switch variant {
        case .prominent:
            content
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .controlSize(size.controlSize)
        case .success:
            content
                .buttonStyle(.glassProminent)
                .tint(MacColor.success)
                .controlSize(size.controlSize)
        case .destructive:
            content
                .buttonStyle(.glass)
                .tint(MacColor.error)
                .controlSize(size.controlSize)
        case .ghost:
            content
                .buttonStyle(.plain)
                .controlSize(size.controlSize)
        case .secondary, .bordered:
            content
                .buttonStyle(.glass)
                .controlSize(size.controlSize)
        }
    }
}
#endif
