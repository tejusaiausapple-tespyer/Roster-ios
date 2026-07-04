import SwiftUI

/// A transient message shown at the top of the screen (success/info/error).
struct ToastMessage: Equatable, Identifiable {
    enum Kind { case success, error, info }
    let id = UUID()
    let kind: Kind
    let text: String
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                toastView(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.4))
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.toast = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
    }

    private func toastView(_ toast: ToastMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(toast.kind))
                .foregroundStyle(tint(toast.kind))
            Text(toast.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
        .padding(.top, 8)
    }

    private func icon(_ kind: ToastMessage.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func tint(_ kind: ToastMessage.Kind) -> Color {
        switch kind {
        case .success: return Theme.accent
        case .error: return Theme.error
        case .info: return Theme.brand
        }
    }
}

extension View {
    func toast(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
