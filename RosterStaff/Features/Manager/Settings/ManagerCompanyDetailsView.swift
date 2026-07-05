import SwiftUI

/// Account → Company details. Stored on settings/app (merged, so the PWA's
/// companyName stays in sync both ways). Shown on the Manager Dashboard
/// header and the Staff Home; a future staff Payslip feature will render
/// these details on generated payslips.
struct ManagerCompanyDetailsView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var companyName = ""
    @State private var businessAddress = ""
    @State private var contactPhone = ""
    @State private var contactEmail = ""
    @State private var abn = ""
    @State private var businessNotes = ""

    @State private var loadedFrom: AppSettings?
    @State private var isSaving = false
    @State private var toast: ToastMessage?

    private var isDirty: Bool {
        current != (loadedFrom ?? repo.appSettings)
    }

    private var current: AppSettings {
        AppSettings(
            companyName: companyName.trimmingCharacters(in: .whitespaces),
            businessAddress: businessAddress.trimmingCharacters(in: .whitespaces),
            contactPhone: contactPhone.trimmingCharacters(in: .whitespaces),
            contactEmail: contactEmail.trimmingCharacters(in: .whitespaces),
            abn: abn.trimmingCharacters(in: .whitespaces),
            businessNotes: businessNotes.trimmingCharacters(in: .whitespaces)
        )
    }

    var body: some View {
        Form {
            Section("Company") {
                LabeledContent("Name") {
                    TextField("Company name", text: $companyName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("ABN") {
                    TextField("Optional", text: $abn)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
            }

            Section("Address") {
                TextField("Business address", text: $businessAddress, axis: .vertical)
                    .lineLimit(2...4)
                    .textContentType(.fullStreetAddress)
            }

            Section("Contact") {
                LabeledContent("Phone") {
                    TextField("Optional", text: $contactPhone)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                LabeledContent("Email") {
                    TextField("Optional", text: $contactEmail)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section {
                TextField("Anything else (bank details, payroll notes…)", text: $businessNotes, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Other business information")
            } footer: {
                Text("These details appear on the dashboards and will be used on staff payslips in a future update.")
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else { Text("Save").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(isSaving || !isDirty || companyName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Company Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Company Details", icon: "building.2.fill")
            }
        }
        .toast($toast)
        .onAppear { loadIfNeeded() }
        .onChange(of: repo.appSettings) { _, _ in loadIfNeeded() }
    }

    private func loadIfNeeded() {
        // Seed once (or re-seed on remote change while the form is untouched).
        guard loadedFrom == nil || !isDirty else { return }
        let settings = repo.appSettings
        companyName = settings.companyName
        businessAddress = settings.businessAddress
        contactPhone = settings.contactPhone
        contactEmail = settings.contactEmail
        abn = settings.abn
        businessNotes = settings.businessNotes
        loadedFrom = settings
    }

    private func save() {
        isSaving = true
        let settings = current
        Task {
            defer { isSaving = false }
            do {
                try await repo.saveCompanyDetails(settings)
                loadedFrom = settings
                toast = ToastMessage(kind: .success, text: "Company details saved")
                Haptics.success()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}
