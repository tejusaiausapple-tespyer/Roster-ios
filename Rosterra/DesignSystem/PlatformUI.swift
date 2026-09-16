import SwiftUI
import UIKit

/// Device and window helpers so layouts follow measured width on iPad Split View
/// and resized Mac Catalyst windows, instead of idiom or size class alone.
enum PlatformUI {
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// iPad and Mac Catalyst use a sidebar instead of a bottom tab bar.
    static var usesSidebarChrome: Bool { !isPhone }

    /// Compact breakpoint shared with the manager roster (agenda vs week grid).
    static let compactWidth: CGFloat = 720

    static func isCompactLayout(width: CGFloat) -> Bool {
        isPhone || width < compactWidth
    }
}

extension View {
    /// Center primary content so ultra-wide Mac windows don't stretch into sparse rows.
    func contentLane(maxWidth: CGFloat = Theme.maxContentWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Hide scrollbars on iPhone; keep them on Mac where the pointer expects them.
    @ViewBuilder
    func platformScrollIndicators() -> some View {
        #if targetEnvironment(macCatalyst)
        scrollIndicators(.automatic)
        #else
        scrollIndicators(.hidden)
        #endif
    }

    /// Pointer highlight for clickable cards and rows on Mac Catalyst.
    @ViewBuilder
    func pointerHover() -> some View {
        if PlatformUI.isMac {
            hoverEffect(.highlight)
        } else {
            self
        }
    }

    /// Compact sheet detents belong on iPhone. iPad and Mac get a full-size
    /// sheet so a `.medium` detent doesn't become a tiny floating card.
    @ViewBuilder
    func phoneSheetDetents(
        _ detents: Set<PresentationDetent>,
        dragIndicator: Visibility = .visible
    ) -> some View {
        if PlatformUI.isPhone {
            presentationDetents(detents)
                .presentationDragIndicator(dragIndicator)
        } else {
            presentationDragIndicator(dragIndicator)
        }
    }
}

extension Notification.Name {
    /// Posted by the Mac menu bar's View ▸ Refresh (⌘R). Screens opt in via
    /// `macRefreshable`.
    static let rosterraRefreshRequested = Notification.Name("RosterraRefreshRequested")
}

extension View {
    /// Pull-to-refresh, plus a pointer-reachable path on Mac.
    ///
    /// `.refreshable` needs an overscroll gesture, which a mouse cannot
    /// produce — on Catalyst that left every data screen with no way to force
    /// a sync at all. The same action is therefore also driven by ⌘R (see
    /// `RosterraApp`'s Refresh command), which posts
    /// `.rosterraRefreshRequested`. Only the visible detail screen is alive on
    /// Mac, so exactly one listener responds.
    @ViewBuilder
    func macRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View {
        #if targetEnvironment(macCatalyst)
        refreshable { await action() }
            .onReceive(NotificationCenter.default.publisher(for: .rosterraRefreshRequested)) { _ in
                Task { await action() }
            }
        #else
        refreshable { await action() }
        #endif
    }
}

extension View {
    /// Selectable text on Mac, where being unable to copy an email, an ABN or a
    /// pay figure reads as a broken app. Left off on touch, where selection
    /// competes with long-press context menus. Applied once at the app root —
    /// text selection propagates through the environment.
    @ViewBuilder
    func macTextSelection() -> some View {
        #if targetEnvironment(macCatalyst)
        textSelection(.enabled)
        #else
        self
        #endif
    }

    /// Search that sits in the toolbar on Mac and stays an always-visible
    /// drawer on iPhone. `.navigationBarDrawer` is a bar metric that has no
    /// meaning next to a pointer.
    @ViewBuilder
    func platformSearchable(text: Binding<String>, prompt: String) -> some View {
        #if targetEnvironment(macCatalyst)
        searchable(text: text, placement: .automatic, prompt: prompt)
        #else
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #endif
    }

    /// iOS 26+ Liquid Glass fade where scroll content meets the navigation bar
    /// and tab bar. No-op on Mac and older systems.
    @ViewBuilder
    func phoneScrollEdgeFade() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), PlatformUI.isPhone {
            scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Pins a custom header so iOS 26 applies the same scroll-edge fade the
    /// navigation bar already uses. Falls back to `safeAreaInset` elsewhere.
    @ViewBuilder
    func phoneHeaderBar<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), PlatformUI.isPhone {
            safeAreaBar(edge: .top, spacing: 0, content: header)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: header)
        }
        #else
        safeAreaInset(edge: .top, spacing: 0, content: header)
        #endif
    }

    /// Minimize the bottom tab bar as content scrolls. Tab-bar-only — headers
    /// use `phoneToolbarMinimizeOnScroll`.
    @ViewBuilder
    func phoneTabBarMinimizeOnScroll() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), PlatformUI.isPhone {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Minimize the navigation bar (title pill) as content scrolls.
    @ViewBuilder
    func phoneToolbarMinimizeOnScroll() -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), PlatformUI.isPhone {
            toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// iOS 27 can reclaim vertical space by minimizing the navigation bar as
    /// the staff Home dashboard scrolls. Older SDKs and operating systems keep
    /// the existing fixed bar.
    @ViewBuilder
    func phoneHomeToolbarBehavior() -> some View {
        phoneToolbarMinimizeOnScroll()
    }

    /// Coordinates swipe actions on custom ScrollView rows, introduced in the
    /// 2027 SwiftUI releases. Context menus remain the iOS 17–26 fallback.
    @ViewBuilder
    func phoneHomeSwipeActions() -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            swipeActionsContainer()
        } else {
            self
        }
        #else
        self
        #endif
    }
}
