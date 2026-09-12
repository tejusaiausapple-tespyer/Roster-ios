#if targetEnvironment(macCatalyst)
import SwiftUI

enum MacButtonVariant {
    case prominent
    case success
    case secondary
    case bordered
    case ghost
    case destructive
}

enum MacButtonSize {
    case small
    case medium
    case large

    var verticalPadding: CGFloat {
        switch self {
        case .small: return 5
        case .medium: return 8
        case .large: return 11
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 14
        case .large: return 18
        }
    }

    var font: Font {
        switch self {
        case .small: return MacType.captionStrong
        case .medium: return MacType.bodyStrong
        case .large: return MacType.sectionHeader
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 14
        case .large: return 16
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .small: return .small
        case .medium: return .regular
        case .large: return .large
        }
    }
}

struct MacButtonStyle: ButtonStyle {
    var variant: MacButtonVariant
    var size: MacButtonSize
    var fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    init(variant: MacButtonVariant = .bordered, size: MacButtonSize = .medium, fullWidth: Bool = false) {
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
    }

    func makeBody(configuration: Configuration) -> some View {
        MacButtonBody(
            configuration: configuration,
            variant: variant,
            size: size,
            fullWidth: fullWidth,
            isEnabled: isEnabled
        )
    }

    private struct MacButtonBody: View {
        let configuration: Configuration
        let variant: MacButtonVariant
        let size: MacButtonSize
        let fullWidth: Bool
        let isEnabled: Bool

        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(size.font)
                .foregroundStyle(foregroundColor)
                .padding(.vertical, size.verticalPadding)
                .padding(.horizontal, size.horizontalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: MacRadius.medium, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : (isHovered ? 1.01 : 1.0))
                .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.45)
                .onHover { hovering in
                    withAnimation(MacMotion.fast) {
                        isHovered = hovering
                    }
                }
        }

        private var foregroundColor: Color {
            guard isEnabled else { return MacColor.textTertiary }
            switch variant {
            case .prominent, .success:
                return Color.white
            case .secondary, .bordered:
                return MacColor.textPrimary
            case .ghost:
                return isHovered ? MacColor.accent : MacColor.textSecondary
            case .destructive:
                return isHovered ? Color.white : MacColor.error
            }
        }

        private var backgroundColor: Color {
            guard isEnabled else { return MacColor.cardBorder.opacity(0.3) }
            switch variant {
            case .prominent:
                return isHovered ? MacColor.brandStrong.opacity(0.9) : MacColor.brandStrong
            case .success:
                return isHovered ? MacColor.success.opacity(0.9) : MacColor.success
            case .secondary:
                return isHovered ? MacColor.sidebarHover : MacColor.cardBackgroundSecondary
            case .bordered:
                return isHovered ? MacColor.sidebarHover : MacColor.cardBackground
            case .ghost:
                return isHovered ? MacColor.sidebarHover : Color.clear
            case .destructive:
                return isHovered ? MacColor.error : MacColor.error.opacity(0.12)
            }
        }

        private var borderColor: Color {
            guard isEnabled else { return Color.clear }
            switch variant {
            case .prominent, .success:
                return Color.white.opacity(0.18)
            case .secondary:
                return isHovered ? MacColor.accent.opacity(0.4) : MacColor.cardBorder
            case .bordered:
                return isHovered ? MacColor.accent.opacity(0.4) : MacColor.cardBorder
            case .ghost:
                return Color.clear
            case .destructive:
                return isHovered ? Color.white.opacity(0.2) : MacColor.error.opacity(0.3)
            }
        }
    }
}

extension View {
    func macLegacyButton(
        _ variant: MacButtonVariant = .bordered,
        size: MacButtonSize = .medium,
        fullWidth: Bool = false
    ) -> some View {
        buttonStyle(MacButtonStyle(variant: variant, size: size, fullWidth: fullWidth))
    }
}

/// A desktop button with asynchronous action execution, automatic loading spinner, and double-click protection.
struct MacAsyncButton<Label: View>: View {
    private let variant: MacButtonVariant
    private let size: MacButtonSize
    private let fullWidth: Bool
    private let action: () async -> Void
    private let label: () -> Label

    @State private var isLoading = false

    init(
        variant: MacButtonVariant = .bordered,
        size: MacButtonSize = .medium,
        fullWidth: Bool = false,
        action: @escaping () async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            isLoading = true
            Task {
                await action()
                await MainActor.run {
                    withAnimation(MacMotion.fast) {
                        isLoading = false
                    }
                }
            }
        } label: {
            HStack(spacing: MacSpace.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(size == .small ? .mini : .small)
                        .tint((variant == .prominent || variant == .success) ? Color.white : MacColor.accent)
                }
                label()
                    .opacity(isLoading ? 0.7 : 1.0)
            }
        }
        .macButton(variant, size: size, fullWidth: fullWidth)
        .disabled(isLoading)
    }
}
#endif
