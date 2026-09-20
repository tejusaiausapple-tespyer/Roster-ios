#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacCard<Content: View, HeaderTrailing: View>: View {
    private let title: String?
    private let subtitle: String?
    private let icon: String?
    private let padding: CGFloat
    private let headerTrailing: () -> HeaderTrailing
    private let content: () -> Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        padding: CGFloat = MacSpace.lg,
        @ViewBuilder headerTrailing: @escaping () -> HeaderTrailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.padding = padding
        self.headerTrailing = headerTrailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || subtitle != nil || icon != nil {
                HStack(spacing: MacSpace.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MacColor.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(MacType.sectionHeader)
                                .foregroundStyle(MacColor.textPrimary)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(MacType.caption)
                                .foregroundStyle(MacColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    headerTrailing()
                }
                .padding(.horizontal, padding)
                .padding(.top, padding)
                .padding(.bottom, MacSpace.sm)
            }

            content()
                .padding(padding)
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
    }
}

extension MacCard where HeaderTrailing == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        padding: CGFloat = MacSpace.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            padding: padding,
            headerTrailing: { EmptyView() },
            content: content
        )
    }
}

struct MacStatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let tint: Color
    var valueTint: Color?
    var action: (() -> Void)?

    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        tint: Color = MacColor.accent,
        valueTint: Color? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.valueTint = valueTint
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { card }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: MacSpace.sm) {
                Text(title)
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(value)
                .font(MacType.kpiValue)
                .foregroundStyle(valueTint ?? MacColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(MacType.caption)
                    .foregroundStyle(MacColor.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
    }
}

struct MacAvatar: View {
    let name: String
    var size: CGFloat = 32

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.joined().isEmpty ? "?" : letters.joined()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(MacColor.accent)
            .frame(width: size, height: size)
            .background(MacColor.accent.opacity(0.12), in: Circle())
    }
}
#endif
