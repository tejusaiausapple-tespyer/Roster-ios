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
    @State private var showsPassword = false

    private enum Field: Hashable {
        case email, password
    }

    @FocusState private var focusedField: Field?

    init() {}

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MacColor.windowBackground.ignoresSafeArea()

                if proxy.size.width >= 920 {
                    HStack(spacing: 0) {
                        brandPanel
                            .frame(width: max(430, proxy.size.width * 0.46))

                        formPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: MacSpace.xxl) {
                            compactBrand
                            loginForm
                                .frame(maxWidth: 440)
                        }
                        .padding(.horizontal, MacSpace.xxl)
                        .padding(.vertical, 52)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                }
            }
        }
        .sheet(isPresented: $showingResetPassword) {
            resetPasswordSheet
                .macObserved(repo: repo, auth: auth)
        }
        .onAppear { focusedField = .email }
    }

    private var brandPanel: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x312E81), Color(hex: 0x4F46E5), Color(hex: 0x6366F1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                .frame(width: 520, height: 520)
                .offset(x: -210, y: -250)
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 360, height: 360)
                .offset(x: 230, y: 300)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: MacSpace.md) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.2)))
                        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
                    Text("Rosterra")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("MANAGER WORKSPACE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.1), in: Capsule())

                Text("Run the week from one clear workspace.")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, MacSpace.xl)

                Text("Plan rosters, approve time, manage your team and finish payroll without jumping between systems.")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, MacSpace.md)

                VStack(alignment: .leading, spacing: MacSpace.md) {
                    loginFeature("calendar.badge.checkmark", "Build and publish weekly rosters")
                    loginFeature("clock.badge.checkmark", "Review timesheets and exceptions")
                    loginFeature("banknote.fill", "Prepare and publish Australian pay runs")
                }
                .padding(.top, MacSpace.xxxl)

                Spacer()

                Label("Secure manager access", systemImage: "lock.shield.fill")
                    .font(MacType.captionStrong)
                    .foregroundStyle(Color.white.opacity(0.68))
            }
            .padding(48)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.extraLarge, style: .continuous))
        .padding(.leading, MacSpace.xxl)
        .padding(.vertical, MacSpace.xxl)
    }

    private func loginFeature(_ icon: String, _ title: String) -> some View {
        HStack(spacing: MacSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    private var formPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: MacSpace.xxxl)
            loginForm
                .frame(maxWidth: 440)
                .padding(.horizontal, 52)
            Spacer(minLength: MacSpace.xxxl)

            Text("Rosterra Manager for macOS")
                .font(MacType.caption)
                .foregroundStyle(MacColor.textTertiary)
                .padding(.bottom, MacSpace.xxl)
        }
    }

    private var compactBrand: some View {
        VStack(spacing: MacSpace.md) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: 12, y: 4)
            Text("Rosterra")
                .font(MacType.display)
                .foregroundStyle(MacColor.textPrimary)
            Text("Manager workspace")
                .font(MacType.captionStrong)
                .foregroundStyle(MacColor.accent)
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: MacSpace.xl) {
            VStack(alignment: .leading, spacing: MacSpace.sm) {
                Text("Welcome back")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(MacColor.textPrimary)
                Text("Sign in with your manager account to continue.")
                    .font(MacType.body)
                    .foregroundStyle(MacColor.textSecondary)
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: MacSpace.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MacColor.error)
                    Text(errorMessage)
                        .font(MacType.captionStrong)
                        .foregroundStyle(MacColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(MacSpace.md)
                .background(MacColor.error.opacity(0.09), in: RoundedRectangle(cornerRadius: MacRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).strokeBorder(MacColor.error.opacity(0.2)))
            }

            VStack(alignment: .leading, spacing: MacSpace.md) {
                loginFieldLabel("Email address")
                HStack(spacing: MacSpace.sm) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(MacColor.textTertiary)
                    TextField("manager@company.com", text: $email)
                        .textFieldStyle(.plain)
                        .font(MacType.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                }
                .padding(.horizontal, MacSpace.md)
                .frame(height: 46)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).strokeBorder(
                    focusedField == .email ? MacColor.accent : MacColor.cardBorder,
                    lineWidth: focusedField == .email ? 1.5 : 1
                ))
            }

            VStack(alignment: .leading, spacing: MacSpace.md) {
                HStack {
                    loginFieldLabel("Password")
                    Spacer()
                    Button("Forgot password?") {
                        resetEmail = email
                        resetSuccessMessage = nil
                        showingResetPassword = true
                    }
                    .font(MacType.captionStrong)
                    .foregroundStyle(MacColor.accent)
                    .buttonStyle(.plain)
                }

                HStack(spacing: MacSpace.sm) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(MacColor.textTertiary)
                    Group {
                        if showsPassword {
                            TextField("Enter your password", text: $password)
                        } else {
                            SecureField("Enter your password", text: $password)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(MacType.body)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit { Task { await performSignIn() } }

                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(MacColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(showsPassword ? "Hide password" : "Show password")
                }
                .padding(.horizontal, MacSpace.md)
                .frame(height: 46)
                .background(MacColor.cardBackgroundSecondary, in: RoundedRectangle(cornerRadius: MacRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: MacRadius.medium).strokeBorder(
                    focusedField == .password ? MacColor.accent : MacColor.cardBorder,
                    lineWidth: focusedField == .password ? 1.5 : 1
                ))
            }

            MacAsyncButton(variant: .prominent, size: .large, fullWidth: true) {
                await performSignIn()
            } label: {
                HStack(spacing: MacSpace.sm) {
                    Text("Sign in to Manager Workspace")
                    Image(systemName: "arrow.right")
                }
            }
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Text("Staff members use Rosterra on iPhone.")
            }
            .font(MacType.caption)
            .foregroundStyle(MacColor.textTertiary)
            .frame(maxWidth: .infinity)
        }
        .padding(32)
        .background(MacColor.cardBackground, in: RoundedRectangle(cornerRadius: MacRadius.extraLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MacRadius.extraLarge).strokeBorder(MacColor.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 24, y: 10)
    }

    private func loginFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(MacType.captionStrong)
            .foregroundStyle(MacColor.textSecondary)
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
