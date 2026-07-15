import SwiftUI

// Manager quick-add for a new staff member. Mirrors the web app's Add Staff
// flow: the Worker creates the Firebase Auth account with a temporary
// password, we write the users/{uid} profile doc, and the new member signs in
// once with the temporary password, is forced to set their own, then completes
// their profile (DOB / address / phone) themselves. Wage assignment stays on
// the web app until the Wage tab ships.
struct ManagerAddStaffSheet: View {
    @Environment(RosterRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var employmentType: EmploymentType = .casual
    @State private var phone = ""
    @State private var includeStartDate = false
    @State private var startDate = Date()
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        BusinessRules.isValidEmail(email) &&
        BusinessRules.passwordErrors(password).isEmpty &&
        !isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Full name", text: $fullName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone (optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                Section {
                    SecureRow(title: "Temporary password", text: $password, contentType: .newPassword)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(BusinessRules.passwordRules(password)) { rule in
                            HStack(spacing: 8) {
                                Image(systemName: rule.isMet ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(rule.isMet ? Theme.accent : Theme.textTertiary)
                                    .font(.subheadline)
                                Text(rule.label)
                                    .font(.footnote)
                                    .foregroundStyle(rule.isMet ? Theme.textSecondary : Theme.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } footer: {
                    Text("They'll sign in with this once, then be required to set their own password.")
                }

                Section {
                    Picker("Employment type", selection: $employmentType) {
                        ForEach(EmploymentType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    Toggle("Set start date", isOn: $includeStartDate.animation())
                        .tint(Theme.brand)
                    if includeStartDate {
                        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Employment")
                } footer: {
                    Text("Date of birth, address and phone are completed by the staff member on first login.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("New Staff Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") { create() }
                            .disabled(!canCreate)
                    }
                }
            }
            .disabled(isCreating)
        }
    }

    private func create() {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if repo.allUsers.contains(where: { $0.email.compare(trimmedEmail, options: .caseInsensitive) == .orderedSame }) {
            errorMessage = "Email already in use."
            Haptics.error()
            return
        }
        isCreating = true
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                _ = try await repo.createStaff(
                    fullName: fullName.trimmingCharacters(in: .whitespaces),
                    email: trimmedEmail,
                    password: password,
                    employmentType: employmentType,
                    phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                    startDate: includeStartDate ? startDate : nil
                )
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.error()
                isCreating = false
            }
        }
    }
}
