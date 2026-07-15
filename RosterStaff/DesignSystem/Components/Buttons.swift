import SwiftUI

/// Primary filled button style — solid brand fill, no gradient, springy press.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    var tint: Color = Theme.brandStrong
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.75))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .fill(tint.opacity(isEnabled ? 1 : 0.48))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary (tinted, translucent) button style.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    var tint: Color = Theme.brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Navigation-bar Save pill (top-right). Subdued while there are no unsaved
/// changes; fills with the brand color the moment the page becomes dirty;
/// returns to subdued after a successful save. Use on edit-and-save screens —
/// one-shot submit flows keep their prominent bottom CTA.
struct ToolbarSaveButton: View {
    var title: String = "Save"
    var isEnabled: Bool
    var isWorking: Bool = false
    var action: () -> Void

    var body: some View {
        // System .borderedProminent + capsule shape: renders as ONE solid
        // pill everywhere, including inside iOS 26 toolbars (a hand-rolled
        // capsule background there fought the toolbar's own glass grouping
        // and looked like two half-pills).
        Button(action: action) {
            if isWorking {
                ProgressView().tint(.white)
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.brandStrong)
        .disabled(!isEnabled || isWorking)
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
        .accessibilityLabel(isEnabled ? "\(title) changes" : "\(title), no changes to save")
    }
}

/// A compact pill button used inline on cards (e.g. "Submit hours").
struct InlinePillButtonStyle: ButtonStyle {
    var tint: Color = Theme.brandStrong
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Color.white : tint)
            .padding(.horizontal, 14)
            .frame(minHeight: 44) // Apple's 44x44pt minimum tappable area — these are frequently-tapped primary actions (Submit hours, Didn't attend).
            .background(
                Capsule().fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
