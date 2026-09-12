import SwiftUI

/// Dismissable nudge shown when a newer build exists but the installed one
/// still clears `ios_minimum_supported_version`. Presented via `.sheet` from
/// `RootView`; swiping down counts as "Later".
struct UpdateAvailableSheet: View {
    let latestVersion: String
    let onLater: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)

            AppLogoMark(size: 64)

            VStack(spacing: 8) {
                Text("Update Available")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Version \(latestVersion) of Rosterra is available with the latest improvements and fixes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            VStack(spacing: 12) {
                Button {
                    openURL(AppConfig.appStoreURL)
                } label: {
                    Label("Update", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint("Opens the \(AppConfig.appStoreName) to update Rosterra")

                Button("Later") {
                    onLater()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .background(Theme.background.ignoresSafeArea())
        .phoneSheetDetents([.medium], dragIndicator: .hidden)
    }
}

#Preview {
    UpdateAvailableSheet(latestVersion: "1.3.0", onLater: {})
}
