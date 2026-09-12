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
                            .keyboardShortcut(.cancelAction)
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
            
            // 2. Send verification to the new address. Auth.email (and therefore
            //    Firestore / Face ID / passkey stores) only change after the
            //    user clicks that link — do not write the new email or clear
            //    quick-login secrets here.
            try await currentUser.sendEmailVerification(beforeUpdatingEmail: newEmail)

            PendingEmailChange.store(uid: currentUser.uid, email: newEmail)

            // Best-effort: clear the manager-requested banner so staff aren't
            // stuck after they've started the change. Staff may lack write
            // permission for this field; that's fine.
            let updatedAt = ISO8601DateFormatter().string(from: Date())
            try? await Firestore.firestore().collection("users").document(currentUser.uid).updateData([
                "emailChangeRequired": false,
                "updatedAt": updatedAt
            ])
            
            Haptics.success()
            onSuccess("Verification email sent to \(newEmail). Tap the link to finish — your sign-in email updates after that.")
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

/// Tracks an in-flight Auth email change so Firestore + Face ID / passkey
/// stores update only after the user clicks the verification link.
enum PendingEmailChange {
    private static let emailKey = "roster_pending_email_change"
    private static let uidKey = "roster_pending_email_change_uid"

    static func store(uid: String, email: String) {
        UserDefaults.standard.set(uid, forKey: uidKey)
        UserDefaults.standard.set(email, forKey: emailKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: uidKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }

    /// If Auth.email now matches the pending address, sync Firestore + local
    /// quick-login emails. No-op until the verification link is clicked.
    @MainActor
    static func reconcileIfNeeded() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let pending = UserDefaults.standard.string(forKey: emailKey),
              UserDefaults.standard.string(forKey: uidKey) == uid else { return }

        try? await Auth.auth().currentUser?.reload()
        let current = Auth.auth().currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard current == pending.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return
        }

        let updatedAt = ISO8601DateFormatter().string(from: Date())
        try? await Firestore.firestore().collection("users").document(uid).updateData([
            "email": pending,
            "updatedAt": updatedAt
        ])
        BiometricCredentialStore.updateSavedEmail(pending)
        PasskeyStore.updateSavedEmail(pending)
        clear()
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