import SwiftUI

/// Shared, scroll-driven collapse state for the screen title pill.
///
/// A single instance is injected at the app root so both the scrolling content
/// (which *writes* the fraction) and the navigation-bar `ScreenTitlePill`
/// (which *reads* it) observe the same value — the pill lives in the toolbar's
/// `.principal` slot, detached from the scroll view, so it can't track scroll
/// directly. Mirrors the `AppRouter` environment pattern.
@MainActor
@Observable
final class TitlePillCollapse {
    /// 0 = fully expanded (scrolled to top), 1 = fully collapsed (scrolled down).
    var fraction: CGFloat = 0
}

// MARK: - Toolbar installer

/// Installs the collapsing `ScreenTitlePill` in the nav bar's `.principal` slot.
///
/// Toolbar `.principal` content only refreshes when the view that *declares*
/// `.toolbar` re-renders — it ignores `@Observable`/environment changes made
/// elsewhere. This modifier observes `TitlePillCollapse` itself, so a scroll
/// update re-runs `body(content:)`, rebuilds the toolbar, and passes the fresh
/// fraction to the pill.
private struct ScreenTitlePillToolbar: ViewModifier {
    let title: String
    let icon: String?
    let fraction: CGFloat

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: title, icon: icon, fraction: fraction)
            }
        }
    }
}

extension View {
    /// Adds the collapsing screen title pill to the navigation bar. Replaces a
    /// manual `.toolbar { ToolbarItem(placement: .principal) { ScreenTitlePill } }`.
    ///
    /// IMPORTANT: pass `fraction` from a `@Environment(TitlePillCollapse.self)`
    /// read *in the screen's own `View` body* (as this argument). Toolbar
    /// `.principal` content is only rebuilt when the view that declares the
    /// toolbar re-renders; reading the fraction as this argument establishes the
    /// observation dependency that drives that re-render.
    func screenTitlePill(_ title: String, icon: String? = nil, fraction: CGFloat) -> some View {
        modifier(ScreenTitlePillToolbar(title: title, icon: icon, fraction: fraction))
    }
}

// MARK: - Reporter

private struct TitlePillOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Zero-height probe placed at the top of a scroll container's content. It reads
/// its own offset in the enclosing scroll view (`.scrollView` coordinate space,
/// iOS 17+) and maps the first `travel` points of downward scroll onto 0…1.
/// Uses a preference key (same proven pattern as `ScrollFadeHints`) so updates
/// fire reliably during scroll.
///
/// Works inside a `ScrollView`/`TabScroll` (`VStack`) or as the first row of a
/// `List` — anywhere that moves with the scroll.
struct TitlePillCollapseReporter: View {
    /// Points of scroll over which the pill fully collapses.
    var travel: CGFloat = 60

    @Environment(TitlePillCollapse.self) private var model

    var body: some View {
        Color.clear
            .frame(height: 0)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TitlePillOffsetKey.self,
                        value: geo.frame(in: .scrollView).minY
                    )
                }
            )
            .onPreferenceChange(TitlePillOffsetKey.self) { minY in
                model.fraction = min(1, max(0, -minY / travel))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Drop at the top of scroll content to drive the title pill's collapse.
    /// Equivalent to placing a `TitlePillCollapseReporter` as the first element.
    func tracksTitlePillCollapse(travel: CGFloat = 60) -> some View {
        overlay(alignment: .top) {
            TitlePillCollapseReporter(travel: travel)
        }
    }
}
