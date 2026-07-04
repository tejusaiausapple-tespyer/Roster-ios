import SwiftUI
import UserNotifications
import FirebaseAuth
import PhotosUI

struct ManagerAccountView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferredColorScheme") private var preferredColorSchemeSetting: String = "system"

    @State private var showChangePassword = false
    @State private var showChangeEmail = false
    @State private var isEmailVerified = false
    @State private var showSignOutConfirm = false
    @State private var deviceAuthOn = false
    @State private var deviceAuthWorking = false
    @State private var pushEnabled = false
    @State private var toastMessage: ToastMessage?
    @State private var showPasswordPrompt = false
    @State private var showImagePicker = false
    @State private var profileImage: UIImage? = nil

    private let device = DeviceAuthService.shared
    private var user: AppUser? { repo.currentUser }

    var body: some View {
        NavigationStack {
            List {
                photoSection
                detailsSection
                if UIDevice.current.userInterfaceIdiom == .phone {
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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ScreenTitlePill(title: "Account", icon: "person.crop.circle.fill")
                }
            }
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView(isForced: false)
            }
            .sheet(isPresented: $showChangeEmail) {
                ChangeEmailView { message in
                    toastMessage = ToastMessage(kind: .success, text: message)
                }
            }
            .sheet(isPresented: $showPasswordPrompt) {
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
            .sheet(isPresented: $showImagePicker) {
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
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                Button {
                    showImagePicker = true
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
                        showChangeEmail = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.footnote)
                            .foregroundStyle(Theme.brand)
                    }
                    .buttonStyle(.plain)
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
                
                if let user {
                    Divider().overlay(Theme.separator)
                    
                    HStack(spacing: 8) {
                        tag("Manager", tint: Theme.brand)
                        tag(user.status.rawValue.capitalized,
                            tint: user.status == .active ? Theme.accent : Theme.error)
                    }
                    .padding(.top, 2)
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
        Section("Appearance") {
            Toggle(isOn: Binding(
                get: {
                    if preferredColorSchemeSetting == "system" {
                        return colorScheme == .dark
                    }
                    return preferredColorSchemeSetting == "dark"
                },
                set: { newValue in
                    preferredColorSchemeSetting = newValue ? "dark" : "light"
                }
            )) {
                Label("Dark Mode", systemImage: "moon.fill")
            }
            .tint(Theme.brand)
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
            Button {
                showChangePassword = true
            } label: {
                Label("Change password", systemImage: "key")
            }
        } header: {
            Text("Security")
        } footer: {
            if device.isSupported {
                Text("Require \(device.biometryLabel) each time you open the app.")
            }
        }
    }

    private var infoSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(appVersion).foregroundStyle(Theme.textSecondary)
            }
        }
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

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshStatuses() async {
        try? await Auth.auth().currentUser?.reload()
        isEmailVerified = Auth.auth().currentUser?.isEmailVerified == true
        
        if let uid = auth.uid {
            deviceAuthOn = device.isEnabled(uid: uid)
        }
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
                    showPasswordPrompt = true
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