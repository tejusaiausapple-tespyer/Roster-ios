#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacAccountView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(MacToastCenter.self) private var toasts

    @AppStorage("preferredColorScheme") private var preferredColorSchemeSetting: String = "system"
    @State private var showingChangePassword = false
    @State private var showingSignOutConfirmation = false
    @State private var activeInfoPage: InfoPage?

    init() {}

    private var user: AppUser? {
        repo.currentUser
    }

    private enum InfoPage: String, Identifiable {
        case version
        case privacy
        case terms

        var id: String { rawValue }
    }

    var body: some View {
        if let activeInfoPage {
            infoPage(activeInfoPage)
        } else {
            accountSettingsPage
        }
    }

    private var accountSettingsPage: some View {
        MacScreen(
            title: "Account Settings",
            subtitle: "Manage your profile, security, and application preferences"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    // Profile Header Card
                    MacCard {
                        HStack(spacing: MacSpace.xl) {
                            ZStack {
                                Circle()
                                    .fill(MacColor.accent.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Text(initials)
                                    .font(MacType.sectionHeader)
                                    .foregroundStyle(MacColor.accent)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: MacSpace.sm) {
                                    Text(user?.name ?? "User")
                                        .font(MacType.pageTitle)
                                        .foregroundStyle(MacColor.textPrimary)

                                    MacStatusPill(
                                        text: (user?.role.rawValue ?? "staff").uppercased(),
                                        foreground: user?.role == .manager ? MacColor.accent : MacColor.textSecondary,
                                        background: (user?.role == .manager ? MacColor.accent : MacColor.textSecondary).opacity(0.12),
                                        border: (user?.role == .manager ? MacColor.accent : MacColor.textSecondary).opacity(0.3)
                                    )
                                }

                                Text(user?.email ?? "")
                                    .font(MacType.body)
                                    .foregroundStyle(MacColor.textSecondary)
                            }

                            Spacer()
                        }
                    }

                    // Appearance & Theme Card
                    MacCard(title: "Appearance & Display", icon: "circle.lefthalf.filled") {
                        VStack(alignment: .leading, spacing: MacSpace.md) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Theme Mode")
                                        .font(MacType.bodyStrong)
                                    Text("Select your preferred visual style on macOS.")
                                        .font(MacType.caption)
                                        .foregroundStyle(MacColor.textTertiary)
                                }
                                Spacer()
                                Picker("Theme", selection: $preferredColorSchemeSetting) {
                                    Text("System").tag("system")
                                    Text("Light").tag("light")
                                    Text("Dark").tag("dark")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 220)
                            }
                        }
                    }

                    // Security & Password Card
                    MacCard(title: "Security & Credentials", icon: "lock.shield.fill") {
                        VStack(spacing: MacSpace.md) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Password")
                                        .font(MacType.bodyStrong)
                                    Text("Keep your account secure by using a strong password.")
                                        .font(MacType.caption)
                                        .foregroundStyle(MacColor.textTertiary)
                                }
                                Spacer()
                                Button("Change Password...") {
                                    showingChangePassword = true
                                }
                                .macButton(.bordered, size: .small)
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Touch ID / Mac Unlock")
                                        .font(MacType.bodyStrong)
                                    Text("Require device biometric authentication when launching the app.")
                                        .font(MacType.caption)
                                        .foregroundStyle(MacColor.textTertiary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { auth.deviceAuthEnabled },
                                    set: { val in
                                        Task {
                                            if val {
                                                await auth.enableDeviceAuth()
                                            } else {
                                                auth.disableDeviceAuth()
                                            }
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }

                    // About & Legal
                    MacCard(title: "About & Legal", icon: "info.circle.fill") {
                        VStack(spacing: 0) {
                            infoRow(
                                title: "Version Information",
                                detail: ReleaseHistory.current.versionString,
                                icon: "info.circle"
                            ) {
                                activeInfoPage = .version
                            }

                            Divider()
                                .padding(.leading, 36)

                            infoRow(
                                title: "Privacy Policy",
                                detail: "Last updated \(PrivacyPolicyContent.lastUpdated)",
                                icon: "hand.raised"
                            ) {
                                activeInfoPage = .privacy
                            }

                            Divider()
                                .padding(.leading, 36)

                            infoRow(
                                title: "Terms of Service",
                                detail: "Effective \(TermsOfServiceContent.effectiveDate)",
                                icon: "doc.text"
                            ) {
                                activeInfoPage = .terms
                            }
                        }
                    }

                    // Version & release information
                    MacCard(title: "Rosterra for Mac", icon: "app.badge.fill") {
                        let release = ReleaseHistory.current
                        HStack(alignment: .top, spacing: MacSpace.xl) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .shadow(color: MacColor.accent.opacity(0.18), radius: 8, x: 0, y: 4)

                            VStack(alignment: .leading, spacing: MacSpace.md) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Version \(release.version)")
                                            .font(MacType.sectionHeader)
                                            .foregroundStyle(MacColor.textPrimary)
                                        Text("Build \(release.build) · \(release.formattedReleaseDate)")
                                            .font(MacType.caption)
                                            .foregroundStyle(MacColor.textTertiary)
                                    }

                                    Spacer()

                                    Text(release.updateType.label)
                                        .font(MacType.captionStrong)
                                        .foregroundStyle(MacColor.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(MacColor.accent.opacity(0.1), in: Capsule())
                                }

                                Text(release.summary)
                                    .font(MacType.body)
                                    .foregroundStyle(MacColor.textSecondary)

                                Divider()

                                VStack(alignment: .leading, spacing: MacSpace.sm) {
                                    Text("WHAT’S NEW")
                                        .font(MacType.badge)
                                        .tracking(0.7)
                                        .foregroundStyle(MacColor.textTertiary)

                                    ForEach(Array(release.features.prefix(4).enumerated()), id: \.offset) { _, item in
                                        Label {
                                            Text(item)
                                                .font(MacType.caption)
                                                .foregroundStyle(MacColor.textSecondary)
                                        } icon: {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(MacColor.success)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Sign Out Card
                    MacCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign Out of Rosterra")
                                    .font(MacType.bodyStrong)
                                    .foregroundStyle(MacColor.error)
                                Text("You will need your password or passkey to log back in.")
                                    .font(MacType.caption)
                                    .foregroundStyle(MacColor.textTertiary)
                            }
                            Spacer()
                            Button("Sign Out") {
                                showingSignOutConfirmation = true
                            }
                            .macButton(.destructive, size: .small)
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
        .sheet(isPresented: $showingChangePassword) {
            MacChangePasswordView(isForced: false)
                .macObserved(repo: repo, auth: auth)
        }
        .confirmationDialog(
            "Are you sure you want to sign out?",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func infoRow(
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MacSpace.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MacColor.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MacType.bodyStrong)
                        .foregroundStyle(MacColor.textPrimary)
                    Text(detail)
                        .font(MacType.caption)
                        .foregroundStyle(MacColor.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacColor.textTertiary)
            }
            .padding(.vertical, MacSpace.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoPage(_ page: InfoPage) -> some View {
        NavigationStack {
            Group {
                switch page {
                case .version:
                    AppVersionHistoryView()
                case .privacy:
                    PrivacyPolicyView()
                case .terms:
                    TermsOfServiceView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        activeInfoPage = nil
                    } label: {
                        Label("Account Settings", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Back to Account Settings")
                }
            }
        }
    }

    private var initials: String {
        guard let name = user?.name, !name.isEmpty else { return "U" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
#endif
