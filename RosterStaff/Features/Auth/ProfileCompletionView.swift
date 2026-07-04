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
    @State private var isWorking = false
    @State private var errorMessage: String?
    @StateObject private var addressCompleter = AddressSearchCompleter()
    @FocusState private var addressFocused: Bool

    init(user: AppUser) {
        self.user = user
        _address = State(initialValue: user.address ?? "")
        _phone = State(initialValue: user.phone ?? "")
        if let dobString = user.dob, let parsed = RosterFormat.parseISODate(dobString) {
            _dob = State(initialValue: parsed)
            _hasDob = State(initialValue: true)
        } else {
            _dob = State(initialValue: Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date())
            _hasDob = State(initialValue: false)
        }
    }

    private var canSubmit: Bool {
        hasDob && !address.trimmingCharacters(in: .whitespaces).isEmpty &&
        !phone.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.profileUpdateRequired ? "Confirm your details" : "Complete your profile")
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
                                            Divider().overlay(Theme.separator)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }

                            Divider().overlay(Theme.separator)

                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("Phone")
                                TextField("Mobile number", text: $phone)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
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

    private func submit() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        let dobString = RosterCalendar.dayFormatter.string(from: dob)
        do {
            try await repo.updateProfile(
                dob: dobString,
                address: address.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces)
            )
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
