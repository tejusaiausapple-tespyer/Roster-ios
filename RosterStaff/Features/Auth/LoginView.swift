import SwiftUI

enum LoginField {
    case email
    case password
}

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberMe = true
    @State private var showForgotPassword = false
    @State private var biometricWorking = false
    @State private var shakeAttempts = 0
    @FocusState private var focus: LoginField?

    private let device = DeviceAuthService.shared

    private var showPasskey: Bool {
        PasskeyManager.shared.isSupported && PasskeyStore.isRegistered
    }
    private var showFaceID: Bool {
        !showPasskey && device.isSupported && BiometricCredentialStore.hasCredential
    }
    private var showQuickLogin: Bool { showPasskey || showFaceID }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            // The one decorative moment on this screen: a quiet brand wash
            // fading out of the top edge.
            LinearGradient(
                colors: [Theme.brand.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
            .ignoresSafeArea(edges: .top)

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 64)

                    VStack(spacing: 14) {
                        if let message = auth.forcedSignOutMessage ?? auth.errorMessage {
                            Banner(kind: .error, title: message)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        emailField
                        passwordField

                        rememberRow
                            .padding(.top, 2)

                        continueButton
                            .padding(.top, 10)

                        if showQuickLogin {
                            orDivider
                                .padding(.top, 6)
                            quickLoginButton
                        }
                    }
                    .padding(.top, 40)
                    .modifier(Shake(animatableData: CGFloat(shakeAttempts)))

                    Spacer(minLength: 32)

                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .frame(minHeight: UIScreen.main.bounds.height - 100)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if let saved = BiometricCredentialStore.savedEmail, email.isEmpty {
                email = saved
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(prefilledEmail: email)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)

            VStack(spacing: 6) {
                Text("Welcome back")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Sign in to your roster & shifts")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Fields

    private var emailField: some View {
        TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: .email)
            .submitLabel(.next)
            .onSubmit { focus = .password }
            .modifier(LoginFieldStyle(isFocused: focus == .email))
    }

    private var passwordField: some View {
        HStack(spacing: 12) {
            Group {
                if showPassword {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .textContentType(.password)
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit { Task { await submit() } }

            if !password.isEmpty {
                Button {
                    showPassword.toggle()
                    Haptics.light()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .modifier(LoginFieldStyle(isFocused: focus == .password))
    }

    // MARK: Remember me / forgot

    private var rememberRow: some View {
        HStack {
            Button {
                Haptics.selection()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    rememberMe.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: rememberMe ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(rememberMe ? Theme.brand : Theme.textTertiary)
                    Text("Remember me")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Forgot password?") {
                Haptics.light()
                showForgotPassword = true
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.brand)
        }
    }

    // MARK: Continue

    private var continueButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if auth.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Sign In")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(auth.isWorking || email.isEmpty || password.isEmpty)
    }

    // MARK: Quick login (passkey preferred, Face ID fallback)

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private var quickLoginButton: some View {
        Button {
            Task {
                if showPasskey {
                    await passkeySignIn()
                } else {
                    await biometricSignIn()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if biometricWorking {
                    ProgressView().tint(Theme.brand)
                } else {
                    Image(systemName: showPasskey ? "person.badge.key.fill" : device.biometrySymbol)
                        .font(.subheadline)
                    Text(showPasskey ? "Sign in with Passkey" : "Sign in with \(device.biometryLabel)")
                }
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(biometricWorking || auth.isWorking)
    }

    // MARK: Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var isManualLoginRequired: Bool {
        guard let lastManual = UserDefaults.standard.object(forKey: "roster_last_manual_login_date") as? Date else {
            return false
        }
        // Force manual login after 7 days (7 * 24 * 60 * 60 seconds)
        let maxDuration: TimeInterval = 7 * 24 * 60 * 60
        return Date().timeIntervalSince(lastManual) > maxDuration
    }

    private func submit() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        focus = nil
        let attemptedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let attemptedPassword = password
        await auth.login(email: attemptedEmail, password: attemptedPassword)
        if auth.errorMessage != nil {
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) {
                shakeAttempts += 1
            }
            return
        }

        // Manual login succeeded! Reset manual verification timestamp.
        UserDefaults.standard.set(Date(), forKey: "roster_last_manual_login_date")

        // Success. If the user opted out of "remember me", clear any saved
        // quick-login secrets and stop.
        if !rememberMe {
            BiometricCredentialStore.clear()
            PasskeyStore.clear()
        }
    }

    private func passkeySignIn() async {
        if isManualLoginRequired {
            auth.errorMessage = "For security, please enter your password."
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) {
                shakeAttempts += 1
            }
            return
        }
        guard let credentialID = PasskeyStore.credentialID,
              let savedEmail = PasskeyStore.email else { return }
        biometricWorking = true
        defer { biometricWorking = false }
        do {
            try await PasskeyManager.shared.signIn(credentialID: credentialID)
        } catch {
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) {
                shakeAttempts += 1
            }
            return // cancelled / failed passkey assertion
        }
        guard let savedPassword = await PasskeyStore.readPassword(reason: "Sign in to Sura Roster") else {
            PasskeyStore.clear()
            email = savedEmail
            return
        }
        await auth.login(email: savedEmail, password: savedPassword)
        if auth.errorMessage != nil {
            // Stored password is stale (changed elsewhere).
            PasskeyStore.clear()
            email = savedEmail
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) {
                shakeAttempts += 1
            }
        }
    }

    private func biometricSignIn() async {
        if isManualLoginRequired {
            auth.errorMessage = "For security, please enter your password."
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) {
                shakeAttempts += 1
            }
            return
        }
        guard let savedEmail = BiometricCredentialStore.savedEmail else { return }
        biometricWorking = true
        defer { biometricWorking = false }
        guard let savedPassword = await BiometricCredentialStore.readPassword(
            reason: "Sign in to Sura Roster"
        ) else {
            return // cancelled or failed biometric
        }
        await auth.login(email: savedEmail, password: savedPassword)
        if auth.errorMessage != nil {
            // Stored password is likely stale (changed on another device).
            BiometricCredentialStore.clear()
            email = savedEmail
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) {
                shakeAttempts += 1
            }
        }
    }
}

// MARK: - Field chrome

/// Flat card field with a hairline border that turns into a brand focus ring.
private struct LoginFieldStyle: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                    .strokeBorder(isFocused ? Theme.brand : Theme.separator,
                                  lineWidth: isFocused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Shake Animation

struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}

// MARK: - Forgot Password Sheet

struct ForgotPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    let prefilledEmail: String

    @State private var email: String
    @State private var isWorking = false
    @State private var sent = false
    @State private var errorMessage: String?
    @FocusState private var emailFocused: Bool

    init(prefilledEmail: String) {
        self.prefilledEmail = prefilledEmail
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if sent {
                            sentState
                                .padding(.horizontal, 22)
                                .padding(.vertical, 28)
                                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                                .padding(.top, 40)
                        } else {
                            formState
                                .padding(.horizontal, 22)
                                .padding(.vertical, 28)
                                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                                .padding(.top, 24)
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .onAppear { if !sent { emailFocused = true } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var formState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.brand.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                }
                Text("Forgot password?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Enter your work email and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            if let errorMessage {
                Banner(kind: .error, title: errorMessage)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Email")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.subheadline)
                        .foregroundStyle(emailFocused ? Theme.brand : Theme.textTertiary)
                        .frame(width: 20)
                        .scaleEffect(emailFocused ? 1.15 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: emailFocused)

                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                        .strokeBorder(emailFocused ? Theme.brand : Theme.separator, lineWidth: emailFocused ? 1.5 : 1)
                )
            }

            Button {
                Task { await send() }
            } label: {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    HStack {
                        Text("Send reset link")
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking || email.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var sentState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.14)).frame(width: 68, height: 68)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text("Check your email")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("If an account exists for \(email), a password reset link is on its way. Check your inbox.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
    }

    private func send() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        emailFocused = false
        isWorking = true
        defer { isWorking = false }
        do {
            try await AuthService.shared.sendPasswordReset(email: trimmed)
            Haptics.success()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { sent = true }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not send reset email. Try again."
            Haptics.error()
        }
    }
}
