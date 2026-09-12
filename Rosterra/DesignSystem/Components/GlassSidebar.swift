import SwiftUI

/// Window canvas behind the floating sidebar card. Matches the detail
/// background so the white panel reads as inset, not a full-height column.
struct SidebarCanvas: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

/// Inset rounded panel: the sidebar floats inside the split column instead
/// of stretching edge-to-edge from the title bar to the bottom of the window.
struct FloatingSidebarPanel<Content: View>: View {
    @ViewBuilder var content: Content

    private let corner: CGFloat = 18
    private let inset: CGFloat = 12

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.sidebar)
                    .shadow(color: Color.black.opacity(0.10), radius: 18, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SidebarCanvas())
    }
}

extension View {
    /// Fills the NavigationSplitView column with the window canvas (not the
    /// white card). `.navigation` placement is iOS 18+; iOS 17 uses `SidebarCanvas`.
    @ViewBuilder
    func sidebarColumnFill() -> some View {
        if #available(iOS 18.0, *) {
            self.containerBackground(Theme.background, for: .navigation)
        } else {
            self
        }
    }
}

/// App mark + company name pinned at the top of the sidebar column.
struct SidebarBrandHeader: View {
    var companyName: String
    var roleLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(companyName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(roleLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Quiet uppercase section label used between groups of source-list rows.
struct SidebarSectionLabel: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A single source-list destination. Selected rows use a solid brand fill
/// (not glass). Unselected rows stay flat until the pointer hovers.
///
/// These rows deliberately bind no key equivalents: the `Go` menu in
/// `RosterraApp` already owns ⌘1–⌘0 and ⌘,. Binding them here too registered
/// each key twice, and the row copies stopped existing whenever the user hid
/// the sidebar — so the same keystroke behaved differently depending on chrome.
struct SidebarItemRow: View {
    var title: String
    var icon: String
    var isSelected: Bool
    var badge: Int = 0
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                iconWell
                Text(title)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.brandStrong : Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white : Theme.brandStrong, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.14) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            guard PlatformUI.isMac else { return }
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(badge > 0 ? "\(title), \(badge)" : title)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
    }

    private var iconWell: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .symbolVariant(isSelected ? .fill : .none)
            .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Theme.sidebarIconWell)
            )
    }

    private var rowFill: Color {
        if isSelected { return Theme.sidebarSelection }
        if isHovered { return Theme.sidebarRowHover }
        return .clear
    }
}

/// Identity row pinned to the bottom of the sidebar. Opens Account.
struct SidebarProfileFooter: View {
    var name: String
    var email: String
    var initials: String
    var isSelected: Bool
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.horizontal, 12)

            Button(action: action) {
                HStack(spacing: 10) {
                    Text(initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : Theme.brandStrong)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(isSelected ? Color.white.opacity(0.2) : Theme.brandStrong.opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                            .lineLimit(1)
                        Text(email)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Theme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(footerFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .onHover { hovering in
                guard PlatformUI.isMac else { return }
                isHovered = hovering
            }
            .accessibilityLabel("Account settings")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .background(Theme.sidebar)
    }

    private var footerFill: Color {
        if isSelected { return Theme.sidebarSelection }
        if isHovered { return Theme.sidebarRowHover }
        return .clear
    }
}

#Preview {
    FloatingSidebarPanel {
        VStack(spacing: 0) {
            SidebarBrandHeader(companyName: "Rosterra", roleLabel: "Manager")
            SidebarSectionLabel(title: "Operations")
            SidebarItemRow(title: "Roster", icon: "calendar", isSelected: true, badge: 0) {}
            SidebarItemRow(title: "Timesheets", icon: "clipboard", isSelected: false, badge: 3) {}
            Spacer()
            SidebarProfileFooter(name: "Alex Manager", email: "alex@example.com", initials: "AM", isSelected: false) {}
        }
    }
    .frame(width: 280, height: 640)
}
