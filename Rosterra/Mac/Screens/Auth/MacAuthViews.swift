#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Mac Login View

struct MacLoginView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(RosterRepository.self) private var repo

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingResetPassword = false
    @State private var resetEmail = ""
    @State private var resetSuccessMessage: String?

    init() {}

    var body: some View {
        ZStack {
            MacColor.windowBackground.ignoresSafeArea()

            VStack(spacing: MacSpace.xl) {
                // Branding
                VStack(spacing: MacSpace.sm) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)

                    Text("Rosterra")
                        .font(MacType.display)
                        .foregroundStyle(MacColor.textPrimary)

                    Text("Sign in to your workplace account")
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textSecondary)
                }

                // Login Card
                VStack(spacing: MacSpace.lg) {
                    if let errorMessage {
                        HStack(spacing: MacSpace.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MacColor.error)
                            Text(errorMessage)
                                .font(MacType.captionStrong)
                                .foregroundStyle(MacColor.error)
                            Spacer()
                        }
                        .padding(MacSpace.md)
                        .background(MacColor.error.opacity(0.1), in: RoundedRectangle(cornerRadius: MacRadius.small))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email Address")
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.textSecondary)

                        TextField("name@company.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .font(MacType.body)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Password")
                                .font(MacType.captionStrong)
                                .foregroundStyle(MacColor.textSecondary)
                            Spacer()
                            Button("Forgot password?") {
                                resetEmail = email
                                showingResetPassword = true
                            }
                            .font(MacType.caption)
                            .foregroundStyle(MacColor.accent)
                            .buttonStyle(.plain)
                        }

                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .font(MacType.body)
                    }

                    MacAsyncButton(
                        variant: .prominent,
                        size: .large,
                        fullWidth: true
                    ) {
                        await performSignIn()
                    } label: {
                        Text("Sign In")
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(MacSpace.xl)
                .frame(width: 400)
                .background(MacColor.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                        .strokeBorder(MacColor.cardBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
            }
            .padding(MacSpace.xxl)
        }
        .sheet(isPresented: $showingResetPassword) {
            resetPasswordSheet
                .macObserved(repo: repo, auth: auth)
        }
    }

    private func performSignIn() async {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email address."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Please enter your password."
            return
        }

        do {
            try await auth.signIn(email: trimmedEmail, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var resetPasswordSheet: some View {
        VStack(spacing: MacSpace.lg) {
            HStack {
                Text("Reset Password")
                    .font(MacType.sectionHeader)
                    .foregroundStyle(MacColor.textPrimary)
                Spacer()
                Button {
                    showingResetPassword = false
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(MacColor.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if let resetSuccessMessage {
                Text(resetSuccessMessage)
                    .font(MacType.body)
                    .foregroundStyle(MacColor.success)
                    .padding()
            } else {
                Text("Enter your email address and we'll send you instructions to reset your password.")
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textSecondary)

                TextField("Email address", text: $resetEmail)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") { showingResetPassword = false }
                        .macButton(.bordered)

                    MacAsyncButton(variant: .prominent) {
                        do {
                            try await auth.sendPasswordReset(email: resetEmail)
                            resetSuccessMessage = "Password reset email sent. Check your inbox."
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Text("Send Reset Link")
                    }
                }
            }
        }
        .padding(MacSpace.xl)
        .frame(width: 420)
    }
}

// MARK: - Mac Change Password View

struct MacChangePasswordView: View {
    @Environment(AuthViewModel.self) private var auth
    var isForced: Bool

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    init(isForced: Bool = false) {
        self.isForced = isForced
    }

    var body: some View {
        ZStack {
            MacColor.windowBackground.ignoresSafeArea()

            VStack(spacing: MacSpace.xl) {
                VStack(spacing: 4) {
                    Text(isForced ? "Password Update Required" : "Change Password")
                        .font(MacType.pageTitle)
                        .foregroundStyle(MacColor.textPrimary)

                    Text(isForced ? "Your account administrator requires you to update your password before continuing." : "Choose a strong password with at least 8 characters.")
                        .font(MacType.body)
                        .foregroundStyle(MacColor.textSecondary)
                }

                VStack(spacing: MacSpace.md) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(MacType.captionStrong)
                            .foregroundStyle(MacColor.error)
                    }

                    SecureField("Current Password", text: $currentPassword)
                        .textFieldStyle(.roundedBorder)

                    SecureField("New Password", text: $newPassword)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Confirm New Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)

                    MacAsyncButton(variant: .prominent, size: .large, fullWidth: true) {
                        guard newPassword == confirmPassword else {
                            errorMessage = "Passwords do not match."
                            return
                        }
                        do {
                            try await auth.updatePassword(currentPassword: currentPassword, newPassword: newPassword)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Text("Update Password")
                    }
                }
                .padding(MacSpace.xl)
                .frame(width: 400)
                .background(MacColor.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: MacRadius.large))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.large).strokeBorder(MacColor.cardBorder, lineWidth: 1))
            }
        }
    }
}

// MARK: - Mac Profile Completion View

struct MacProfileCompletionView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    var user: AppUser

    @State private var phone = ""
    @State private var emergencyName = ""
    @State private var emergencyPhone = ""
    @State private var tfn = ""
    @State private var superFund = ""
    @State private var superMemberNumber = ""
    @State private var errorMessage: String?

    init(user: AppUser) {
        self.user = user
    }

    var body: some View {
        ZStack {
            MacColor.windowBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    VStack(spacing: 4) {
                        Text("Complete Your Staff Profile")
                            .font(MacType.display)
                            .foregroundStyle(MacColor.textPrimary)
                        Text("Please provide your contact, emergency, and payroll details to complete onboarding.")
                            .font(MacType.body)
                            .foregroundStyle(MacColor.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: MacSpace.lg) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(MacType.captionStrong)
                                .foregroundStyle(MacColor.error)
                        }

                        MacCard(title: "Contact & Emergency Details", icon: "person.fill") {
                            VStack(spacing: MacSpace.md) {
                                TextField("Mobile Phone Number", text: $phone)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Emergency Contact Name", text: $emergencyName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Emergency Contact Phone", text: $emergencyPhone)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        MacCard(title: "Payroll & Tax Information", icon: "banknote.fill") {
                            VStack(spacing: MacSpace.md) {
                                TextField("Tax File Number (TFN)", text: $tfn)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Superannuation Fund Name", text: $superFund)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Super Member Number", text: $superMemberNumber)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        MacAsyncButton(variant: .prominent, size: .large, fullWidth: true) {
                            do {
                                var updated = user
                                updated.phone = phone
                                updated.emergencyContactName = emergencyName
                                updated.emergencyContactPhone = emergencyPhone
                                updated.tfn = tfn
                                updated.superFundName = superFund
                                updated.superMemberNumber = superMemberNumber
                                try await repo.updateUser(updated)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Text("Complete Setup & Access Roster")
                        }
                    }
                    .frame(maxWidth: 600)
                }
                .padding(MacSpace.xxl)
            }
        }
    }
}

// MARK: - Mac Device Auth Gate View

struct MacDeviceAuthGateView: View {
    @Environment(AuthViewModel.self) private var auth

    init() {}

    var body: some View {
        ZStack {
            MacColor.windowBackground.ignoresSafeArea()

            VStack(spacing: MacSpace.lg) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(MacColor.accent)

                Text("App Locked")
                    .font(MacType.windowTitle)
                    .foregroundStyle(MacColor.textPrimary)

                Text("Authenticate to unlock your Rosterra session.")
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textSecondary)

                Button("Unlock with Touch ID / Password") {
                    Task { await auth.authenticateDevice() }
                }
                .macButton(.prominent, size: .large)
            }
            .padding(MacSpace.xxl)
        }
    }
}

// MARK: - Mac Setup Required View

struct MacSetupRequiredView: View {
    init() {}

    var body: some View {
        ZStack {
            MacColor.windowBackground.ignoresSafeArea()

            VStack(spacing: MacSpace.lg) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(MacColor.warning)

                Text("Setup Required")
                    .font(MacType.windowTitle)
                    .foregroundStyle(MacColor.textPrimary)

                Text("GoogleService-Info.plist configuration file is missing from the application bundle.")
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .padding(MacSpace.xxl)
        }
    }
}
#endif
