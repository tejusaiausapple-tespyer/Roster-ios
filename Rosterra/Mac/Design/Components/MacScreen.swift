#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacSidebarToggleButton: View {
    @Environment(MacNavigationModel.self) private var nav

    var body: some View {
        Button {
            nav.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.leading")
        }
        .help(nav.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        .accessibilityLabel(nav.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
    }
}

private struct MacScreenTitlePill: View {
    let title: String
    let subtitle: String?

    var body: some View {
        Text(title)
            .font(MacType.bodyStrong)
            .foregroundStyle(MacColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, MacSpace.xl)
            .padding(.vertical, MacSpace.sm)
            .macGlassSurface(cornerRadius: MacRadius.pill)
            .onTapGesture(count: 2) {
                MacWindow.toggleZoom()
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
            .help("\(subtitle ?? title) — double-click to zoom window")
    }
}

struct MacScreen<Content: View, Actions: View>: View {
    private let title: String
    private let subtitle: String?
    private let isLoading: Bool
    private let errorMessage: String?
    private let onRetry: (() -> Void)?
    private let actions: () -> Actions
    private let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRetry = onRetry
        self.actions = actions
        self.content = content
    }

    var body: some View {
        Group {
            if isLoading {
                MacLoadingView(message: "Loading \(title)...")
            } else if let errorMessage {
                MacEmptyState(
                    title: "Unable to Load",
                    subtitle: errorMessage,
                    icon: "exclamationmark.triangle",
                    actionTitle: onRetry != nil ? "Try Again" : nil,
                    action: onRetry
                )
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacColor.windowBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MacScreenTitlePill(title: title, subtitle: subtitle)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                actions()
            }
        }
        .onAppear {
            MacWindow.setTitle(title)
        }
    }
}
#endif
