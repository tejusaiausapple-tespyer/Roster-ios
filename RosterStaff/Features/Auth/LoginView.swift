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
        ZStack {
            // Premium focus-reactive background
            AmbientOrbsBackground(focus: focus)

            ScrollView {
                VStack(spacing: 24) {
                    header
                        .padding(.top, 40)
                        .padding(.bottom, 8)

                    VStack(spacing: 20) {
                        formFields
                        rememberRow
                            .padding(.top, 4)

                        continueButton
                            .padding(.top, 8)

                        if showQuickLogin {
                            quickLoginSection
                                .padding(.top, 4)
                        }

                        forgotButton
                            .padding(.top, 4)
                    }
                    .glassCardStyle()
                    .modifier(Shake(animatableData: CGFloat(shakeAttempts)))

                    Spacer(minLength: 24)

                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: UIScreen.main.bounds.height - 80)
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
        VStack(spacing: 16) {
            // App Icon Image
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                .padding(.bottom, 4)
            
            VStack(spacing: 6) {
                Text("SURA")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(6)
                    .foregroundStyle(Theme.textSecondary)
                

                Text("Sign in to access your roster & shifts")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Fields

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let message = auth.forcedSignOutMessage ?? auth.errorMessage {
                Banner(kind: .error, title: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            fieldGroup(label: "Email") {
                fieldCard(icon: "envelope.fill", isFocused: focus == .email) {
                    TextField("your@email.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
            }

            fieldGroup(label: "Password") {
                fieldCard(icon: "lock.fill", isFocused: focus == .password) {
                    Group {
                        if showPassword {
                            TextField("••••••••", text: $password)
                        } else {
                            SecureField("••••••••", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }

                    Button {
                        showPassword.toggle()
                        Haptics.light()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textTertiary)
                            .scaleEffect(showPassword ? 1.05 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: showPassword)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    private func fieldCard<Content: View>(icon: String, isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isFocused ? Theme.brand : Theme.textTertiary)
                .frame(width: 20)
                .scaleEffect(isFocused ? 1.15 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isFocused)
            
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .fill(Theme.card.opacity(isFocused ? 0.95 : 0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .strokeBorder(isFocused ? Theme.brand : Theme.separator, lineWidth: isFocused ? 1.5 : 1)
        )
        .shadow(color: isFocused ? Theme.brand.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }

    // MARK: Remember me

    private var rememberRow: some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                rememberMe.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(rememberMe ? Theme.brand : Theme.textTertiary)
                    .scaleEffect(rememberMe ? 1.05 : 1.0)
                Text("Remember me")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Continue

    private var continueButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                if auth.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                    
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.trailing, 4)
                    }
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(auth.isWorking || email.isEmpty || password.isEmpty)
    }

    // MARK: Quick login (passkey preferred, Face ID fallback)

    private var quickLoginSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Rectangle().fill(Theme.separator).frame(height: 1)
                Text("OR QUICK SIGN IN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
            .padding(.horizontal, 4)

            if showPasskey {
                Button {
                    Task { await passkeySignIn() }
                } label: {
                    HStack(spacing: 8) {
                        if biometricWorking {
                            ProgressView().tint(Theme.brand)
                        } else {
                            Image(systemName: "person.badge.key.fill")
                                .font(.system(size: 16))
                            Text("Sign in with Passkey")
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(biometricWorking || auth.isWorking)
            } else {
                Button {
                    Task { await biometricSignIn() }
                } label: {
                    HStack(spacing: 8) {
                        if biometricWorking {
                            ProgressView().tint(Theme.brand)
                        } else {
                            Image(systemName: device.biometrySymbol)
                                .font(.system(size: 16))
                            Text("Sign in with \(device.biometryLabel)")
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(biometricWorking || auth.isWorking)
            }
        }
    }

    // MARK: Forgot

    private var forgotButton: some View {
        Button("Forgot password?") {
            Haptics.light()
            showForgotPassword = true
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.brand)
        .frame(maxWidth: .infinity)
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

// MARK: - Ambient Background View

struct AmbientOrbsBackground: View {
    var focus: LoginField? = nil
    @State private var animate = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            // Orb 1 (Brand/Indigo)
            Circle()
                .fill(Theme.brand.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(
                    x: (animate ? -90 : 90) + (focus == .email ? -45 : (focus == .password ? 45 : 0)),
                    y: (animate ? -130 : 130) + (focus == .email ? -35 : (focus == .password ? 35 : 0))
                )
            
            // Orb 2 (Accent/Emerald)
            Circle()
                .fill(Theme.accent.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(
                    x: (animate ? 110 : -110) + (focus == .email ? 45 : (focus == .password ? -45 : 0)),
                    y: (animate ? 90 : -90) + (focus == .email ? 35 : (focus == .password ? -35 : 0))
                )
            
            // Orb 3 (Warning/Orange-ish)
            Circle()
                .fill(Theme.warning.opacity(0.06))
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(
                    x: (animate ? -40 : 40) + (focus == .email ? 25 : (focus == .password ? -25 : 0)),
                    y: (animate ? 120 : -120) + (focus == .email ? -25 : (focus == .password ? 25 : 0))
                )
        }
        .animation(.spring(response: 0.65, dampingFraction: 0.8), value: focus)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 8.0)
                .repeatForever(autoreverses: true)
            ) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Glassmorphic Card ViewModifier

struct GlassCardModifier: ViewModifier {
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.card.opacity(0.7))
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 10)
            .overlay(
                // Static faint border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.4), lineWidth: 1.5)
            )
            .overlay(
                // Rotating light sweep border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                Theme.brand,
                                Theme.brand.opacity(0.3),
                                .clear,
                                .clear
                            ]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 2
                    )
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 4.0)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}

extension View {
    func glassCardStyle() -> some View {
        self.modifier(GlassCardModifier())
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
