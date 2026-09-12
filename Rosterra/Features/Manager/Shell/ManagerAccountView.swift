import SwiftUI
import UserNotifications
import FirebaseAuth
import PhotosUI

struct ManagerAccountView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.openURL) private var openURL
    @AppStorage("preferredColorScheme") private var preferredColorSchemeSetting: String = "system"

    @State private var activeSheet: AccountSheet?
    @State private var isEmailVerified = false
    @State private var showSignOutConfirm = false
    @State private var deviceAuthOn = false
    @State private var deviceAuthWorking = false
    @State private var passkeyOn = false
    @State private var passkeyWorking = false
    @State private var pushEnabled = false
    @State private var toastMessage: ToastMessage?
    @State private var profileImage: UIImage? = nil

    private enum AccountSheet: Identifiable {
        case changePassword, changeEmail, verifyPassword, verifyPasskey, imagePicker
        var id: String { String(describing: self) }
    }

    private let device = DeviceAuthService.shared
    private var user: AppUser? { repo.currentUser }

    var body: some View {
        NavigationStack {
            List {
                // Zero-footprint scroll probe: own section with no spacing —
                // a loose row would form an implicit section (44pt min row
                // height + section spacing) and push the first card ~100pt down.
                Section {
                    TitlePillCollapseReporter()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listSectionSpacing(0)
                photoSection
                detailsSection
                businessSection
                if PlatformUI.isPhone {
                    managementSection
                }
                notificationsSection
                appearanceSection
                securitySection
                infoSection
                signOutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .screenTitlePill("Account", icon: "person.crop.circle.fill", fraction: 0)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .changePassword:
                    ChangePasswordView(isForced: false)
                case .changeEmail:
                    ChangeEmailView { message in
                        toastMessage = ToastMessage(kind: .success, text: message)
                    }
                case .verifyPassword:
                    if let email = user?.email {
                        VerifyPasswordSheet(email: email) { verifiedPassword in
                            Task {
                                guard let uid = auth.uid else { return }
                                do {
                                    try await device.enable(uid: uid)
                                    BiometricCredentialStore.save(email: email, password: verifiedPassword)
                                    auth.temporaryPassword = verifiedPassword
                                    deviceAuthOn = true
                                    auth.refreshDeviceAuthEnabled()
                                    Haptics.success()
                                    toastMessage = ToastMessage(kind: .success, text: "\(device.biometryLabel) enabled")
                                } catch {
                                    toastMessage = ToastMessage(kind: .error, text: "Could not enable \(device.biometryLabel)")
                                }
                            }
                        }
                    }
                case .verifyPasskey:
                    if let email = user?.email {
                        VerifyPasswordSheet(
                            email: email,
                            heading: "Enable Passkey Sign-In",
                            detail: "Confirm your password, then create a passkey for this device.",
                            navigationTitle: "Enable Passkey",
                            symbolName: "person.badge.key.fill"
                        ) { verifiedPassword in
                            Task { await enablePasskey(email: email, password: verifiedPassword) }
                        }
                    }
                case .imagePicker:
                    ImagePicker(image: Binding(
                        get: { profileImage },
                        set: { newImg in
                            if let newImg {
                                saveProfileImage(newImg)
                                profileImage = newImg
                            }
                        }
                    ))
                }
            }
            .alert("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Sign out", role: .destructive) { auth.logout() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You'll need to sign in again to access the manager dashboard.")
            }
            .toast($toastMessage)
            .task {
                await refreshStatuses()
                loadLocalProfileImage()
            }
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                Button {
                    activeSheet = .imagePicker
                } label: {
                    ZStack {
                        if let profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 90, height: 90)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Theme.brand.opacity(0.14))
                                .frame(width: 90, height: 90)
                                .overlay(
                                    Text(String((user?.fullName ?? "U").prefix(2)).uppercased())
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(Theme.brand)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
                .pointerHover()
                .contextMenu {
                    if profileImage != nil {
                        Button(role: .destructive) {
                            removeProfileImage()
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                    }
                }
                
                Text(user?.fullName ?? "—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                if let user {
                    HStack(spacing: 8) {
                        tag("Manager", tint: Theme.brand)
                        tag(user.status.rawValue.capitalized,
                            tint: user.status == .active ? Theme.accent : Theme.error)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 8)
        }
    }

    private var detailsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                // Email
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Email")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.textTertiary)
                                .textCase(.uppercase)
                            
                            // Email Verification Badge
                            Text(isEmailVerified ? "Verified" : "Pending")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isEmailVerified ? Theme.accent : .orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((isEmailVerified ? Theme.accent : .orange).opacity(0.12)))
                        }
                        Text(user?.email ?? "")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        activeSheet = .changeEmail
                    } label: {
                        Image(systemName: "pencil")
                            .font(.footnote)
                            .foregroundStyle(Theme.brand)
                    }
                    .buttonStyle(.plain)
                    .pointerHover()
                }
                
                if let member = user?.memberSince {
                    Divider().overlay(Theme.separator)
                    
                    // Member Since
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Member Since")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                        Text(member)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                
            }
            .padding(.vertical, 4)
        }
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private var businessSection: some View {
        Section("Business") {
            NavigationLink {
                ManagerCompanyDetailsView()
            } label: {
                Label("Company details", systemImage: "building.2")
            }
            NavigationLink {
                ManagerLocationsView()
            } label: {
                Label("Locations", systemImage: "mappin.and.ellipse")
            }
        }
    }

    private var managementSection: some View {
        Section("Management") {
            NavigationLink {
                ManagerStaffView(embedInNavigationStack: false)
            } label: {
                Label("Staff", systemImage: "person.2")
            }
            NavigationLink {
                ManagerAvailabilityView(embedInNavigationStack: false)
            } label: {
                Label("Availability", systemImage: "calendar.badge.clock")
            }
            NavigationLink {
                ManagerReportsView(embedInNavigationStack: false)
            } label: {
                Label("Reports", systemImage: "chart.bar")
            }
            NavigationLink {
                ManagerTenureView(embedInNavigationStack: false)
            } label: {
                Label("Tenure & Hours", systemImage: "rosette")
            }
            NavigationLink {
                ManagerWageView(embedInNavigationStack: false)
            } label: {
                Label("Wage", systemImage: "dollarsign.circle")
            }
            NavigationLink {
                ManagerPayrollView(embedInNavigationStack: false)
            } label: {
                Label("Payroll", systemImage: "banknote")
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            HStack {
                Label("Push notifications", systemImage: "bell.badge")
                Spacer()
                Text(pushEnabled ? "On" : "Off")
                    .font(.subheadline)
                    .foregroundStyle(pushEnabled ? Theme.accent : Theme.textTertiary)
            }
            Button {
                openSystemSettings()
            } label: {
                Label("Notification settings", systemImage: "gear")
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferredColorSchemeSetting == "dark" },
                set: { preferredColorSchemeSetting = $0 ? "dark" : "system" }
            )) {
                Label("Dark Mode", systemImage: "moon.fill")
            }
            .tint(Theme.brand)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Off follows your device Light/Dark setting.")
        }
        .onAppear {
            // Old toggle wrote "light" on off; that value is no longer offered.
            if preferredColorSchemeSetting == "light" {
                preferredColorSchemeSetting = "system"
            }
        }
    }

    private var securitySection: some View {
        Section {
            if device.isSupported {
                Toggle(isOn: Binding(get: { deviceAuthOn }, set: { toggleDeviceAuth($0) })) {
                    Label("\(device.biometryLabel) unlock", systemImage: device.biometrySymbol)
                }
                .tint(Theme.brand)
                .disabled(deviceAuthWorking)
            }
            if PasskeyManager.shared.isSupported {
                Toggle(isOn: Binding(get: { passkeyOn }, set: { togglePasskey($0) })) {
                    Label("Sign in with Passkey", systemImage: "person.badge.key.fill")
                }
                .tint(Theme.brand)
                .disabled(passkeyWorking)
            }
            Button {
                activeSheet = .changePassword
            } label: {
                Label("Change password", systemImage: "key")
            }
        } header: {
            Text("Security")
        } footer: {
            Text(securityFooter)
        }
    }

    private var securityFooter: String {
        var parts: [String] = []
        if device.isSupported {
            parts.append("Require \(device.biometryLabel) each time you open the app.")
        }
        if PasskeyManager.shared.isSupported {
            parts.append("A passkey lets you sign in on this device without typing your password.")
        }
        return parts.joined(separator: " ")
    }

    private var infoSection: some View {
        Section("About") {
            NavigationLink {
                AppVersionHistoryView()
            } label: {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(ReleaseHistory.current.versionString)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            NavigationLink {
                TermsOfServiceView()
            } label: {
                Label("Terms of Service", systemImage: "doc.text")
            }
            Button {
                openSupportEmail()
            } label: {
                Label("Contact Support", systemImage: "envelope")
            }
        }
    }

    private func openSupportEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppConfig.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Rosterra support")]
        if let url = components.url { openURL(url) }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func refreshStatuses() async {
        try? await Auth.auth().currentUser?.reload()
        await PendingEmailChange.reconcileIfNeeded()
        isEmailVerified = Auth.auth().currentUser?.isEmailVerified == true
        
        if let uid = auth.uid {
            deviceAuthOn = device.isEnabled(uid: uid)
        }
        passkeyOn = PasskeyStore.isRegistered
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private func toggleDeviceAuth(_ enable: Bool) {
        guard let uid = auth.uid, !deviceAuthWorking else { return }
        deviceAuthWorking = true
        Task {
            defer { deviceAuthWorking = false }
            if enable {
                if let password = auth.temporaryPassword, let email = user?.email {
                    do {
                        try await device.enable(uid: uid)
                        BiometricCredentialStore.save(email: email, password: password)
                        auth.temporaryPassword = nil
                        deviceAuthOn = true
                        auth.refreshDeviceAuthEnabled()
                        Haptics.success()
                        toastMessage = ToastMessage(kind: .success, text: "\(device.biometryLabel) enabled")
                    } catch {
                        deviceAuthOn = false
                        Haptics.error()
                        toastMessage = ToastMessage(kind: .error, text: "Could not enable \(device.biometryLabel)")
                    }
                } else {
                    deviceAuthOn = false
                    auth.refreshDeviceAuthEnabled()
                    activeSheet = .verifyPassword
                }
            } else {
                device.disable(uid: uid)
                BiometricCredentialStore.clear()
                deviceAuthOn = false
                auth.refreshDeviceAuthEnabled()
                Haptics.light()
            }
        }
    }

    private func togglePasskey(_ enable: Bool) {
        guard !passkeyWorking else { return }
        guard let email = user?.email else { return }
        if enable {
            if let password = auth.temporaryPassword {
                Task { await enablePasskey(email: email, password: password) }
            } else {
                passkeyOn = false
                activeSheet = .verifyPasskey
            }
        } else {
            PasskeyStore.clear()
            passkeyOn = false
            Haptics.light()
        }
    }

    private func enablePasskey(email: String, password: String) async {
        guard let uid = auth.uid else { return }
        passkeyWorking = true
        defer { passkeyWorking = false }
        do {
            try await PasskeyManager.shared.registerAndStore(email: email, userID: uid, password: password)
            auth.temporaryPassword = nil
            passkeyOn = true
            Haptics.success()
            toastMessage = ToastMessage(kind: .success, text: "Passkey enabled")
        } catch let error as PasskeyManager.PasskeyError {
            passkeyOn = false
            if case .cancelled = error { return }
            Haptics.error()
            toastMessage = ToastMessage(kind: .error, text: error.localizedDescription)
        } catch {
            passkeyOn = false
            Haptics.error()
            toastMessage = ToastMessage(kind: .error, text: "Could not enable passkey")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func loadLocalProfileImage() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo_manager.jpg")
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            self.profileImage = img
        }
    }

    private func saveProfileImage(_ img: UIImage) {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo_manager.jpg")
        if let data = img.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }

    private func removeProfileImage() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo_manager.jpg")
        try? FileManager.default.removeItem(at: fileURL)
        self.profileImage = nil
    }
}
