import SwiftUI

// MARK: - Metrics

private struct ScrollFadeMetrics: Equatable {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    var showsTopHint: Bool { offsetY < -8 }

    var showsBottomHint: Bool {
        let overflow = contentHeight - viewportHeight
        guard overflow > 8 else { return false }
        return offsetY > -(overflow - 8)
    }
}

// MARK: - Preference keys (scoped by coordinate-space name)

private struct ScrollFadeOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ScrollFadeContentHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Overlay

/// Faded chevron hints at the top and bottom of a scroll container.
struct ScrollFadeHintsOverlay: View {
    let showsTop: Bool
    let showsBottom: Bool
    var fadeColor: Color = Theme.background

    var body: some View {
        ZStack {
            if showsTop {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [fadeColor.opacity(0.92), fadeColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textTertiary.opacity(0.75))
                            .padding(.bottom, 2)
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }

            if showsBottom {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [fadeColor.opacity(0), fadeColor.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 34)
                    .overlay(alignment: .top) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textTertiary.opacity(0.75))
                            .padding(.top, 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: showsTop)
        .animation(.easeInOut(duration: 0.2), value: showsBottom)
    }
}

// MARK: - Modifier

private struct FadedScrollHintsModifier: ViewModifier {
    let coordinateSpace: String
    var fadeColor: Color = Theme.background
    @State private var offsetY: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var metrics: ScrollFadeMetrics {
        ScrollFadeMetrics(offsetY: offsetY, contentHeight: contentHeight, viewportHeight: viewportHeight)
    }

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: coordinateSpace)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, height in viewportHeight = height }
                }
            }
            .onPreferenceChange(ScrollFadeOffsetKey.self) { values in
                if let value = values[coordinateSpace] { offsetY = value }
            }
            .onPreferenceChange(ScrollFadeContentHeightKey.self) { values in
                if let value = values[coordinateSpace] { contentHeight = value }
            }
            .overlay {
                ScrollFadeHintsOverlay(
                    showsTop: metrics.showsTopHint,
                    showsBottom: metrics.showsBottomHint,
                    fadeColor: fadeColor
                )
            }
    }
}

extension View {
    /// Place on the root of scroll *content* to feed fade-hint metrics.
    func scrollFadeContentTracking(in coordinateSpace: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ScrollFadeOffsetKey.self,
                        value: [coordinateSpace: geo.frame(in: .named(coordinateSpace)).minY]
                    )
                    .preference(
                        key: ScrollFadeContentHeightKey.self,
                        value: [coordinateSpace: geo.size.height]
                    )
            }
        }
    }

    /// Overlay faded scroll hints on a `ScrollView` (or other scroll container).
    func fadedScrollHints(coordinateSpace: String, fadeColor: Color = Theme.background) -> some View {
        modifier(FadedScrollHintsModifier(coordinateSpace: coordinateSpace, fadeColor: fadeColor))
    }
}

// MARK: - Convenience wrapper

/// Vertical `ScrollView` with hidden system indicators and conditional fade hints.
struct FadedScrollView<Content: View>: View {
    let coordinateSpace: String
    var fadeColor: Color = Theme.background
    @ViewBuilder var content: () -> Content

    init(
        _ coordinateSpace: String,
        fadeColor: Color = Theme.background,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.coordinateSpace = coordinateSpace
        self.fadeColor = fadeColor
        self.content = content
    }

    var body: some View {
        ScrollView {
            content()
                .scrollFadeContentTracking(in: coordinateSpace)
        }
        .scrollIndicators(.hidden)
        .fadedScrollHints(coordinateSpace: coordinateSpace, fadeColor: fadeColor)
    }
}
