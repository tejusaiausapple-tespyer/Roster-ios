import SwiftUI
import UserNotifications
import FirebaseAuth
import PhotosUI

struct AccountView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @AppStorage("preferredColorScheme") private var preferredColorSchemeSetting: String = "system"

    @State private var activeSheet: AccountSheet?
    @State private var isEmailVerified = false
    @State private var showSignOutConfirm = false
    @State private var deviceAuthOn = false
    @State private var deviceAuthWorking = false
    @State private var pushEnabled = false
    @State private var pendingReminderCount = 0
    @State private var nextReminderSummary: String?
    @State private var toastMessage: ToastMessage?
    @State private var profileImage: UIImage? = nil
    @State private var showDeleteRequestConfirm = false
    @State private var showNotificationExplainer = false

    private enum AccountSheet: Identifiable {
        case changePassword, changeEmail, verifyPassword, imagePicker
        var id: String { String(describing: self) }
    }

    private let device = DeviceAuthService.shared

    private var user: AppUser? { repo.currentUser }
    private var metrics: HoursMetrics {
        HoursMetrics.compute(timesheets: repo.timesheets, shifts: repo.shifts)
    }

    var body: some View {
        NavigationStack {
            List {
                TitlePillCollapseReporter()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                photoSection
                if user?.emailChangeRequired == true {
                    emailRequestSection
                }
                detailsSection
                statsSection
                payslipsSection
                notificationsSection
                appearanceSection
                securitySection
                infoSection
                deleteAccountSection
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
                Text("You'll need to sign in again to access your roster.")
            }
            .alert("Request account deletion?", isPresented: $showDeleteRequestConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Send request to manager", role: .destructive) {
                    Task { await submitDeletionRequest() }
                }
            } message: {
                Text("Your manager will review the request. If approved, your account is locked immediately and sign-in is permanently removed after 30 days. Name, DOB, address, TFN, timesheets and payslips are kept for Australian tax records.")
            }
            .toast($toastMessage)
            .task {
                await refreshStatuses()
                loadLocalProfileImage()
            }
        }
    }

    // MARK: Profile

    private var emailRequestSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Update your email", systemImage: "envelope.badge")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.warning)
                Text("Your manager asked you to update your email address. Tap below to change it — we'll send a verification link to your new address to confirm.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    activeSheet = .changeEmail
                } label: {
                    Text("Change email").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.vertical, 4)
        }
    }

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                Button {
                    activeSheet = .imagePicker
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                        } else {
                            ZStack {
                                Circle().fill(Theme.brand.opacity(0.12)).frame(width: 96, height: 96)
                                Text(user?.initials ?? "?")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        
                        ZStack {
                            Circle().fill(Theme.brand).frame(width: 26, height: 26)
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 2, y: 2)
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

                if let user {
                    HStack(spacing: 8) {
                        tag(user.role == .staff ? "Staff" : "Manager", tint: Theme.brand)
                        tag(user.status.rawValue.capitalized,
                            tint: user.status == .active ? Theme.accent : Theme.error)
                        if let type = user.employmentType {
                            tag(type.label, tint: Theme.textSecondary)
                        }
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
                }
                
                if let employeeId = user?.employeeId, !employeeId.isEmpty {
                    Divider().overlay(Theme.separator)

                    // Employee ID (manager-assigned)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Employee ID")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                        Text(employeeId)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
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

    // MARK: Stats

    private var statsSection: some View {
        Section {
            HStack(spacing: 12) {
                miniStat(RosterFormat.decimalHours(metrics.all), "Approved hrs")
                miniStat("\(repo.timesheets.count)", "Timesheets")
                miniStat("\(metrics.pendingCount)", "Pending")
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card))
    }

    // MARK: Payslips

    private var payslipsSection: some View {
        Section("Pay") {
            NavigationLink {
                PayslipsView()
            } label: {
                // No count badge: payslips load one month at a time on demand,
                // so the full history is deliberately never fetched here.
                Label("Payslips", systemImage: "banknote")
            }
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            HStack {
                Label("Alerts allowed", systemImage: "bell.badge")
                Spacer()
                Text(pushEnabled ? "On" : "Off")
                    .font(.subheadline)
                    .foregroundStyle(pushEnabled ? Theme.accent : Theme.textTertiary)
            }
            if pushEnabled {
                HStack {
                    Label("Shift reminders armed", systemImage: "clock.badge")
                    Spacer()
                    Text(pendingReminderCount > 0 ? "\(pendingReminderCount) pending" : "None yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let nextReminderSummary {
                    Text(nextReminderSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Button {
                    showNotificationExplainer = true
                } label: {
                    Label("Enable shift & hours reminders", systemImage: "bell")
                }
            }
            Button {
                openSystemSettings()
            } label: {
                Label("System notification settings", systemImage: "gear")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Shift start and hours reminders are scheduled on this device from your last roster sync. They can still alert you after you close the app — Rosterra does not keep running in the background. Server push covers roster changes when your phone is online.")
        }
        .alert("Enable shift reminders?", isPresented: $showNotificationExplainer) {
            Button("Not now", role: .cancel) {}
            Button("Continue") {
                NotificationService.shared.requestAuthorizationAndRegister()
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await refreshStatuses()
                }
            }
        } message: {
            Text("Rosterra can alert you before a shift starts and when hours need submitting. Alerts use on-device reminders and optional push — the app does not stay open in the background.")
        }
    }

    // MARK: Appearance

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

    // MARK: Security

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
                activeSheet = .changePassword
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

    // MARK: Info

    private var infoSection: some View {
        Section("About") {
            if let location = user?.defaultLocation, !location.isEmpty {
                HStack {
                    Label("Default location", systemImage: "mappin.and.ellipse")
                    Spacer()
                    Text(location).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(ReleaseHistory.current.versionString)
                    .foregroundStyle(Theme.textSecondary)
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

    private var deleteAccountSection: some View {
        Section {
            if let deletion = user?.deletion {
                deletionStatusRows(deletion)
            } else {
                Button(role: .destructive) {
                    showDeleteRequestConfirm = true
                } label: {
                    Label("Request account deletion", systemImage: "trash")
                }
            }
        } header: {
            Text("Delete account")
        } footer: {
            Text("Employer-managed accounts. After approval you are locked for 30 days (cancellable by your manager), then login is removed. Payroll/ATO records are retained.")
        }
    }

    @ViewBuilder
    private func deletionStatusRows(_ deletion: AccountDeletionState) -> some View {
        switch deletion.status {
        case .requested:
            Label("Deletion requested — waiting for manager", systemImage: "clock.badge")
                .foregroundStyle(Theme.warning)
        case .approved:
            VStack(alignment: .leading, spacing: 6) {
                Label("Account locked — deletion scheduled", systemImage: "lock.fill")
                    .foregroundStyle(Theme.error)
                if let deadline = deletion.cancelDeadlineAt,
                   let date = FS.isoDate(from: deadline) {
                    Text("Sign-in removed after \(RosterFormat.dateFull(date)). Ask your manager to cancel if this was a mistake.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        case .authPurged:
            Label("Account closed — records retained for tax/payroll", systemImage: "checkmark.shield")
                .foregroundStyle(Theme.textSecondary)
        case .cancelled:
            EmptyView()
        }
    }

    private func submitDeletionRequest() async {
        do {
            try await repo.requestOwnAccountDeletion()
            Haptics.success()
            toastMessage = ToastMessage(kind: .success, text: "Deletion request sent to your manager.")
        } catch {
            toastMessage = ToastMessage(kind: .error, text: error.localizedDescription)
            Haptics.error()
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

    // MARK: Helpers

    private func refreshStatuses() async {
        try? await Auth.auth().currentUser?.reload()
        isEmailVerified = Auth.auth().currentUser?.isEmailVerified == true
        
        if let uid = auth.uid {
            deviceAuthOn = device.isEnabled(uid: uid)
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let pending = await ShiftReminderScheduler.pendingStatus()
        pendingReminderCount = pending.count
        if let date = pending.nextFireDate, let title = pending.nextTitle {
            nextReminderSummary = "Next: \(title) · \(RosterFormat.dateTime(date))"
        } else {
            nextReminderSummary = nil
        }
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
                        auth.temporaryPassword = nil // Clear plaintext password from memory
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
                    // Password not in memory, show verification sheet
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

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func loadLocalProfileImage() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo.jpg")
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            self.profileImage = img
        }
    }

    private func saveProfileImage(_ img: UIImage) {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo.jpg")
        if let data = img.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }

    private func removeProfileImage() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo.jpg")
        try? FileManager.default.removeItem(at: fileURL)
        self.profileImage = nil
    }
}

// MARK: - Verify Password Sheet

struct VerifyPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth
    
    let email: String
    let onVerifySuccess: (String) -> Void
    
    @State private var password = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.brand.opacity(0.12)).frame(width: 64, height: 64)
                            Image(systemName: "faceid")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.brand)
                        }
                        Text("Enable Face ID Sign-In")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Confirm your password to securely store your credentials on this device.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    
                    if let errorMessage {
                        Banner(kind: .error, title: errorMessage)
                    }
                    
                    SecureField("Password", text: $password)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous).fill(Theme.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                                .strokeBorder(isFocused ? Theme.brand : Theme.separator, lineWidth: isFocused ? 1.5 : 1)
                        )
                        .submitLabel(.go)
                        .onSubmit { Task { await verify() } }
                    
                    Button {
                        Task { await verify() }
                    } label: {
                        if isVerifying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Verify & Enable")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isVerifying || password.isEmpty)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                .padding(.horizontal, 20)
            }
            .navigationTitle("Enable Biometrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private func verify() async {
        guard !password.isEmpty else { return }
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await Auth.auth().currentUser?.reauthenticate(with: credential)
            // Manual verification succeeded! Reset manual verification timestamp.
            UserDefaults.standard.set(Date(), forKey: "roster_last_manual_login_date")
            onVerifySuccess(password)
            dismiss()
        } catch {
            errorMessage = "Incorrect password. Try again."
            Haptics.error()
        }
    }
}

// MARK: - Native Image Cropping Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true // Enforces native square cropping grid overlay!
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
