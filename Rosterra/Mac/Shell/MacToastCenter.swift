#if targetEnvironment(macCatalyst)
import SwiftUI
import Observation

struct MacToast: Identifiable, Equatable {
    enum Style {
        case info
        case success
        case warning
        case error

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return MacColor.info
            case .success: return MacColor.success
            case .warning: return MacColor.warning
            case .error: return MacColor.error
            }
        }
    }

    let id = UUID()
    let message: String
    let style: Style
    let duration: TimeInterval

    init(message: String, style: Style = .info, duration: TimeInterval = 3.5) {
        self.message = message
        self.style = style
        self.duration = duration
    }
}

@MainActor
@Observable
final class MacToastCenter {
    private(set) var toasts: [MacToast] = []

    init() {}

    func show(_ message: String, style: MacToast.Style = .info, duration: TimeInterval = 3.5) {
        let toast = MacToast(message: message, style: style, duration: duration)
        withAnimation(MacMotion.smooth) {
            toasts.append(toast)
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                withAnimation(MacMotion.normal) {
                    toasts.removeAll { $0.id == toast.id }
                }
            }
        }
    }

    func dismiss(_ id: UUID) {
        withAnimation(MacMotion.normal) {
            toasts.removeAll { $0.id == id }
        }
    }
}

struct MacToastHost: View {
    @Environment(MacToastCenter.self) private var center

    var body: some View {
        VStack(alignment: .trailing, spacing: MacSpace.sm) {
            Spacer()
            ForEach(center.toasts) { toast in
                HStack(spacing: MacSpace.md) {
                    Image(systemName: toast.style.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(toast.style.tint)

                    Text(toast.message)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                        .lineLimit(2)

                    Button {
                        center.dismiss(toast.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MacColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, MacSpace.lg)
                .padding(.vertical, MacSpace.md)
                .macGlassSurface(cornerRadius: MacRadius.medium)
                .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity.combined(with: .scale(scale: 0.95))))
            }
        }
        .padding(MacSpace.xl)
        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(true)
    }
}
#endif
