import SwiftUI

/// Shown when the real GoogleService-Info.plist is missing. Gives the developer
/// clear, actionable setup instructions instead of crashing.
struct SetupRequiredView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Text("Firebase setup required")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add GoogleService-Info.plist for the iOS app (bundle id com.sura.roster.staff) to:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Text("RosterStaff/Resources/GoogleService-Info.plist")
                    .font(.footnote.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                Text("See README.md for full setup steps.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(28)
        }
    }
}
