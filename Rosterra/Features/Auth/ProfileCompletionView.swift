import SwiftUI

/// Staff must confirm date of birth, address and phone before dashboard access.
/// Mirrors ProfileCompletionGate.
struct ProfileCompletionView: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(AuthViewModel.self) private var auth

    let user: AppUser

    @State private var dob: Date
    @State private var hasDob: Bool
    @State private var address: String
    @State private var phone: String
    @State private var emergencyName: String
    @State private var emergencyPhone: String
    @State private var emergencyEmail: String
    @State private var emergencyAddress: String
    @State private var roleConfirmed: Bool
    @State private var isWorking = false
    @State private var errorMessage: String?
    @StateObject private var addressCompleter = AddressSearchCompleter()
    @FocusState private var addressFocused: Bool

    init(user: AppUser) {
        self.user = user
        _address = State(initialValue: user.address ?? "")
        _phone = State(initialValue: user.phone ?? "")
        _emergencyName = State(initialValue: user.emergencyContactName ?? user.emergencyContact ?? "")
        _emergencyPhone = State(initialValue: user.emergencyContactPhone ?? "")
        _emergencyEmail = State(initialValue: user.emergencyContactEmail ?? "")
        _emergencyAddress = State(initialValue: user.emergencyContactAddress ?? "")
        _roleConfirmed = State(initialValue: !user.roleReviewRequired)
        if let dobString = user.dob, let parsed = RosterFormat.parseISODate(dobString) {
            _dob = State(initialValue: parsed)
            _hasDob = State(initialValue: true)
        } else {
            _dob = State(initialValue: RosterCalendar.calendar.date(byAdding: .year, value: -25, to: Date()) ?? Date())
            _hasDob = State(initialValue: false)
        }
    }

    private var canSubmit: Bool {
        let coreComplete = hasDob && !address.trimmingCharacters(in: .whitespaces).isEmpty
            && ContactValidation.phoneError(phone) == nil
        let emergencyComplete = !user.emergencyDetailsRequired
            || (!emergencyName.trimmingCharacters(in: .whitespaces).isEmpty
                && ContactValidation.phoneError(emergencyPhone) == nil
                && ContactValidation.emailError(emergencyEmail) == nil
                && !emergencyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return coreComplete && emergencyComplete && roleConfirmed && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(requiredTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("We need a few details before you can access your roster.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let errorMessage {
                        Banner(kind: .error, title: errorMessage)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("Date of birth")
                                DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .onChange(of: dob) { _, _ in hasDob = true }
                                if !hasDob {
                                    Text("Tap to select your date of birth")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }

                            Divider().overlay(Theme.separator)

                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("Address")
                                TextField("Start typing your address", text: $address)
                                    .textContentType(.fullStreetAddress)
                                    .focused($addressFocused)
                                    .onChange(of: address) { _, newValue in
                                        addressCompleter.update(query: newValue)
                                    }
                                if addressFocused && !addressCompleter.suggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(addressCompleter.suggestions, id: \.self) { suggestion in
                                            Button {
                                                address = suggestion
                                                addressCompleter.clear()
                                                addressFocused = false
                                            } label: {
                                                Text(suggestion)
                                                    .font(.subheadline)
                                                    .foregroundStyle(Theme.textSecondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.vertical, 8)
                                            }
                                            .buttonStyle(.plain)
                                            .pointerHover()
                                            Divider().overlay(Theme.separator)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }

                            Divider().overlay(Theme.separator)

                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("Phone")
                                InternationalPhoneField(text: $phone)
                                    .frame(minHeight: 32)
                                if let error = ContactValidation.phoneError(phone), shouldShowPhoneError(phone) {
                                    validationMessage(error)
                                }
                            }
                        }
                    }

                    if user.roleReviewRequired {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Your role has been updated", systemImage: "briefcase.fill")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                HStack {
                                    Text("New role")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(user.defaultDepartment?.isEmpty == false ? user.defaultDepartment! : "Team member")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                Toggle("I have reviewed my updated role", isOn: $roleConfirmed)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }

                    if user.emergencyDetailsRequired {
                        Card {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Emergency contact required", systemImage: "cross.case.fill")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                VStack(alignment: .leading, spacing: 6) {
                                    fieldLabel("Contact name")
                                    TextField("Full name", text: $emergencyName)
                                        .textContentType(.name)
                                }
                                Divider().overlay(Theme.separator)
                                VStack(alignment: .leading, spacing: 6) {
                                    fieldLabel("Contact phone")
                                    InternationalPhoneField(text: $emergencyPhone)
                                        .frame(minHeight: 32)
                                    if let error = ContactValidation.phoneError(emergencyPhone), shouldShowPhoneError(emergencyPhone) {
                                        validationMessage(error)
                                    }
                                }
                                Divider().overlay(Theme.separator)
                                VStack(alignment: .leading, spacing: 6) {
                                    fieldLabel("Contact email")
                                    TextField("Email address", text: $emergencyEmail)
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                    if let error = ContactValidation.emailError(emergencyEmail), !emergencyEmail.isEmpty {
                                        validationMessage(error)
                                    }
                                }
                                Divider().overlay(Theme.separator)
                                VStack(alignment: .leading, spacing: 6) {
                                    fieldLabel("Contact address")
                                    TextField("Address", text: $emergencyAddress)
                                        .textContentType(.fullStreetAddress)
                                }
                            }
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking { ProgressView().tint(.white) } else { Text("Save and continue") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit)

                    Button("Sign out") { auth.logout() }
                        .buttonStyle(.plain)
                        .pointerHover()
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
    }

    private func validationMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.error)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shouldShowPhoneError(_ value: String) -> Bool {
        value.filter(\.isNumber).count > 2
    }

    private var requiredTitle: String {
        if user.emergencyDetailsRequired || user.roleReviewRequired { return "Action required" }
        return user.profileUpdateRequired ? "Confirm your details" : "Complete your profile"
    }

    private func submit() async {
        errorMessage = nil
        if let error = ContactValidation.phoneError(phone) {
            errorMessage = error
            Haptics.error()
            return
        }
        if user.emergencyDetailsRequired {
            guard !emergencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Enter an emergency contact name."
                Haptics.error()
                return
            }
            if let error = ContactValidation.phoneError(emergencyPhone) {
                errorMessage = error
                Haptics.error()
                return
            }
            if let error = ContactValidation.emailError(emergencyEmail) {
                errorMessage = error
                Haptics.error()
                return
            }
            guard !emergencyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Enter an emergency contact address."
                Haptics.error()
                return
            }
        }
        isWorking = true
        defer { isWorking = false }
        let dobString = RosterCalendar.dayFormatter.string(from: dob)
        do {
            try await repo.updateProfile(
                dob: dobString,
                address: address.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                emergencyName: emergencyName.trimmingCharacters(in: .whitespaces),
                emergencyPhone: emergencyPhone.trimmingCharacters(in: .whitespaces),
                emergencyEmail: emergencyEmail.trimmingCharacters(in: .whitespaces),
                emergencyAddress: emergencyAddress.trimmingCharacters(in: .whitespaces)
            )
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
