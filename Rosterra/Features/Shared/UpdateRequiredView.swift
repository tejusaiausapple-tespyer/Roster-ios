import SwiftUI

/// Full-screen, non-dismissable gate shown when the installed build is below
/// the supported floor or a force-update targets the public App Store version.
/// Presented via `.fullScreenCover` from `RootView` — there is no "Later" here
/// on purpose.
struct UpdateRequiredView: View {
    let minimumVersion: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                AppLogoMark(size: 80)
                VStack(spacing: 8) {
                    Text("Update Required")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("This version of Rosterra can no longer be used. Update to version \(minimumVersion) or later from the \(AppConfig.appStoreName) to continue.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                Spacer()
                Button {
                    openURL(AppConfig.appStoreURL)
                } label: {
                    Label("Update Now", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint("Opens the \(AppConfig.appStoreName) to update Rosterra")
            }
            .padding(28)
        }
        .accessibilityAddTraits(.isModal)
        .interactiveDismissDisabled()
    }
}

#Preview {
    UpdateRequiredView(minimumVersion: "1.2.0")
}

/// Shown when no previously activated minimum-version policy exists and the
/// first network check cannot establish one. No repository is started behind
/// this view; users can retry after reconnecting.
struct VersionPolicyUnavailableView: View {
    let retry: () async -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                AppLogoMark(size: 80)
                Text("Version Check Unavailable")
                    .font(.title2.weight(.bold))
                Text("Connect to the internet and retry. If this continues, contact your manager.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    Task { await retry() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(28)
        }
    }
}
