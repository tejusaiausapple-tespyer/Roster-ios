import SwiftUI

/// Change password screen. Used as a forced full-screen gate (first login) and
/// as a sheet from the Account tab.
struct ChangePasswordView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    var isForced: Bool = false

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var errors: [String] = []
    @State private var isWorking = false

    var body: some View {
        if isForced {
            NavigationStack { formContent }
        } else {
            NavigationStack {
                formContent
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            }
        }
    }

    private var passwordRules: [BusinessRules.PasswordRule] {
        BusinessRules.passwordRules(newPassword)
    }

    private var canSubmit: Bool {
        !current.isEmpty && !newPassword.isEmpty && newPassword == confirm &&
        BusinessRules.passwordErrors(newPassword).isEmpty && !isWorking
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isForced {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set a new password")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("For your security, please choose a new password before continuing.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if !errors.isEmpty {
                    Banner(kind: .error, title: errors.first ?? "Please check your details.")
                }

                Card {
                    VStack(spacing: 14) {
                        SecureRow(title: "Current password", text: $current, contentType: .password)
                        Divider().overlay(Theme.separator)
                        SecureRow(title: "New password", text: $newPassword, contentType: .newPassword)
                        Divider().overlay(Theme.separator)
                        SecureRow(title: "Confirm new password", text: $confirm, contentType: .newPassword)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(passwordRules) { rule in
                        HStack(spacing: 8) {
                            Image(systemName: rule.isMet ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rule.isMet ? Theme.accent : Theme.textTertiary)
                                .font(.subheadline)
                            Text(rule.label)
                                .font(.footnote)
                                .foregroundStyle(rule.isMet ? Theme.textSecondary : Theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 4)

                Button {
                    Task { await submit() }
                } label: {
                    if isWorking { ProgressView().tint(.white) } else { Text("Update password") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)

                if isForced {
                    Button("Sign out") { auth.logout() }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(isForced ? "" : "Change Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        errors = []
        guard newPassword == confirm else {
            errors = ["Passwords do not match"]; Haptics.error(); return
        }
        let ruleErrors = BusinessRules.passwordErrors(newPassword)
        guard ruleErrors.isEmpty else { errors = ruleErrors; Haptics.error(); return }
        guard let email = repo.currentUser?.email ?? AuthService.shared.currentEmail else {
            errors = ["Not signed in"]; return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await AuthService.shared.changePassword(current: current, new: newPassword, email: email)
            // Clear the first-login flag server-side when required.
            if repo.currentUser?.mustChangePassword == true {
                try? await WorkerAPIClient.shared.completePasswordChange()
            }
            
            // Update cached credentials to prevent Face ID / Passkey desync
            auth.temporaryPassword = newPassword
            if BiometricCredentialStore.hasCredential {
                BiometricCredentialStore.save(email: email, password: newPassword)
            }
            if PasskeyStore.isRegistered {
                PasskeyStore.save(email: email, credentialID: PasskeyStore.credentialID ?? "", password: newPassword)
            }
            
            Haptics.success()
            if !isForced { dismiss() }
        } catch {
            errors = [(error as? LocalizedError)?.errorDescription ?? error.localizedDescription]
            Haptics.error()
        }
    }
}

/// A labelled secure field row used inside cards.
struct SecureRow: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            HStack {
                Group {
                    if reveal { TextField("", text: $text) }
                    else { SecureField("", text: $text) }
                }
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
