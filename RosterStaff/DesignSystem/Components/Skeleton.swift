import SwiftUI

/// A shimmering placeholder block used for loading states.
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.textTertiary.opacity(0.18))
            .frame(height: height)
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: width * 0.5)
                    .offset(x: phase * width)
                }
                .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

/// A skeleton card approximating a shift/timesheet row while data loads.
struct SkeletonCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SkeletonBlock(height: 18).frame(width: 120)
                    Spacer()
                    SkeletonBlock(height: 18, cornerRadius: 9).frame(width: 70)
                }
                SkeletonBlock(height: 14).frame(maxWidth: .infinity)
                SkeletonBlock(height: 14).frame(width: 180)
            }
        }
    }
}
