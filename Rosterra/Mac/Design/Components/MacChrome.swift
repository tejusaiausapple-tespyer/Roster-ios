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
}

@available(iOS 26.0, *)
private struct MacGlassButtonModifier: ViewModifier {
    let variant: MacButtonVariant
    let size: MacButtonSize

    func body(content: Content) -> some View {
        switch variant {
        case .prominent:
            content
                .buttonStyle(.glassProminent)
                .tint(MacColor.brandStrong)
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
