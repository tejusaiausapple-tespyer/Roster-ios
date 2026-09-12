#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacEmptyState: View {
    let title: String
    let subtitle: String?
    let icon: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        icon: String = "tray",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: MacSpace.md) {
            ZStack {
                Circle()
                    .fill(MacColor.sidebarIconWell)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(MacColor.textTertiary)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .macButton(.bordered, size: .medium)
                    .padding(.top, MacSpace.sm)
            }
        }
        .padding(MacSpace.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacLoadingView: View {
    let message: String

    init(message: String = "Loading...") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: MacSpace.md) {
            ProgressView()
                .controlSize(.regular)
                .tint(MacColor.accent)
            Text(message)
                .font(MacType.body)
                .foregroundStyle(MacColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
