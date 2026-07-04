import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChangeEmailView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    let onSuccess: (String) -> Void

    @State private var password = ""
    @State private var newEmail = ""
    @State private var confirmEmail = ""
    @State private var errors: [String] = []
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            formContent
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }

    private var canSubmit: Bool {
        !password.isEmpty && !newEmail.isEmpty && newEmail == confirmEmail &&
        isValidEmail(newEmail) && !isWorking
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Change email address")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("We will send a verification link to your new address. Click the link to complete the change.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                if !errors.isEmpty {
                    Banner(kind: .error, title: errors.first ?? "Please check your details.")
                }

                Card {
                    VStack(spacing: 14) {
                        SecureRow(title: "Current password", text: $password, contentType: .password)
                        Divider().overlay(Theme.separator)
                        EmailRow(title: "New email address", text: $newEmail)
                        Divider().overlay(Theme.separator)
                        EmailRow(title: "Confirm email address", text: $confirmEmail)
                    }
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isWorking { ProgressView().tint(.white) } else { Text("Send Verification Link") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Change Email")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        errors = []
        guard newEmail == confirmEmail else {
            errors = ["Emails do not match"]; Haptics.error(); return
        }
        guard isValidEmail(newEmail) else {
            errors = ["Invalid email format"]; Haptics.error(); return
        }
        guard let currentUser = Auth.auth().currentUser else {
            errors = ["Not signed in"]; return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            // 1. Reauthenticate
            let credential = EmailAuthProvider.credential(withEmail: currentUser.email ?? "", password: password)
            try await currentUser.reauthenticate(with: credential)
            
            // 2. Send email verification to new email (updates once user clicks link)
            try await currentUser.sendEmailVerification(beforeUpdatingEmail: newEmail)
            
            // 3. Sync the Firestore user document. Two separate writes on
            //    purpose: the deployed rules allow staff to self-update
            //    `email`, but `emailChangeRequired` is NOT in the self-update
            //    allowlist — combining them made the whole update fail with
            //    permission-denied for staff. The flag clear is best-effort
            //    (works for managers; for staff it needs the rules allowlist
            //    to include 'emailChangeRequired', otherwise the manager can
            //    clear it via "Cancel request").
            //    NOTE: the email write is optimistic — Auth only changes after
            //    the verification link is clicked. This mirrors how the web
            //    app keeps Firestore in sync and is the only sync mechanism
            //    for self-service changes.
            let db = Firestore.firestore()
            let isoFormatter = ISO8601DateFormatter()
            let updatedAt = isoFormatter.string(from: Date())
            try await db.collection("users").document(currentUser.uid).updateData([
                "email": newEmail,
                "updatedAt": updatedAt
            ])
            try? await db.collection("users").document(currentUser.uid).updateData([
                "emailChangeRequired": false,
                "updatedAt": updatedAt
            ])
            
            // 4. Clear biometric credentials to prevent logging in with stale credentials
            BiometricCredentialStore.clear()
            PasskeyStore.clear()
            auth.refreshDeviceAuthEnabled()
            
            Haptics.success()
            onSuccess("Verification email sent to \(newEmail)!")
            dismiss()
        } catch {
            errors = [(error as? LocalizedError)?.errorDescription ?? error.localizedDescription]
            Haptics.error()
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

/// A labelled text field row used inside cards for emails.
struct EmailRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: $text)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 4)
    }
}