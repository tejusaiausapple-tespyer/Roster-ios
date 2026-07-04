import SwiftUI

/// Managers are not supported in the native staff app — direct them to the web app.
struct ManagerBlockedView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                Text("This app is for staff")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("You're signed in with a manager account. Please use the Sura Roster web app to manage your team.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Link(destination: AppConfig.webAppURL) {
                    Label("Open the web app", systemImage: "safari.fill")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .padding(.top, 4)

                Button("Sign out") { auth.logout() }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: false))
            }
            .padding(28)
        }
    }
}
