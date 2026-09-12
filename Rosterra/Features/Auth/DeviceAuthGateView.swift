import SwiftUI

/// The biometric unlock gate shown for a restored session when device auth is on.
struct DeviceAuthGateView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    private let device = DeviceAuthService.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                AppLogoMark(size: 80)
                VStack(spacing: 8) {
                    Text("Locked")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(errorMessage ?? "Unlock with \(device.biometryLabel) to continue.")
                        .font(.subheadline)
                        .foregroundStyle(errorMessage == nil ? Theme.textSecondary : Theme.warning)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    Task { await unlock() }
                } label: {
                    Label("Unlock", systemImage: device.biometrySymbol)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isAuthenticating)

                Button("Sign out") { auth.logout() }
                    .buttonStyle(.plain)
                    .pointerHover()
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(28)
        }
        .task {
            // Offer the prompt automatically on appear.
            await unlock()
        }
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = await auth.verifyDeviceAuth()
        isAuthenticating = false
    }
}
