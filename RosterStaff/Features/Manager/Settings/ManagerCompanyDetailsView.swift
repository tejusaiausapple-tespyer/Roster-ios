import SwiftUI

/// Account → Company details. Stored on settings/app (merged, so the PWA's
/// companyName stays in sync both ways). Shown on the Manager Dashboard
/// header and the Staff Home; a future staff Payslip feature will render
/// these details on generated payslips.
///
/// Input conveniences: ABN/ACN self-format with spaces as you type (the
/// number pad has no space bar), phone is fixed to +61 with local digits
/// only, and the address is structured (street / suburb / state dropdown /
/// auto capital city) with a composed one-line `businessAddress` saved
/// alongside for display and back-compat.
struct ManagerCompanyDetailsView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var companyName = ""
    @State private var abn = ""
    @State private var acn = ""
    @State private var street = ""
    @State private var suburb = ""
    @State private var state = "SA"
    @State private var city = RosterLocation.capital(for: "SA")
    @State private var phoneLocal = ""
    @State private var contactEmail = ""
    @State private var businessNotes = ""

    @State private var loadedFrom: AppSettings?
    @State private var isSaving = false
    @State private var toast: ToastMessage?

    private var isDirty: Bool {
        current != (loadedFrom ?? repo.appSettings)
    }

    private var current: AppSettings {
        let trimmedStreet = street.trimmingCharacters(in: .whitespaces)
        let trimmedSuburb = suburb.trimmingCharacters(in: .whitespaces)
        let localDigits = phoneLocal.filter(\.isNumber)
        return AppSettings(
            companyName: companyName.trimmingCharacters(in: .whitespaces),
            businessAddress: AppSettings.composedAddress(street: trimmedStreet,
                                                         suburb: trimmedSuburb,
                                                         state: state),
            businessStreet: trimmedStreet,
            businessSuburb: trimmedSuburb,
            businessState: state,
            businessCity: city.trimmingCharacters(in: .whitespaces),
            contactPhone: localDigits.isEmpty ? "" : "+61 \(RosterFormat.auPhoneLocal(localDigits))",
            contactEmail: contactEmail.trimmingCharacters(in: .whitespaces),
            abn: abn,
            acn: acn,
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
                    TextField("XX XXX XXX XXX", text: $abn)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: abn) { _, newValue in
                            let formatted = RosterFormat.abn(newValue)
                            if formatted != newValue { abn = formatted }
                        }
                }
                LabeledContent("ACN") {
                    TextField("XXX XXX XXX", text: $acn)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .onChange(of: acn) { _, newValue in
                            let formatted = RosterFormat.acn(newValue)
                            if formatted != newValue { acn = formatted }
                        }
                }
            }

            Section("Business Address") {
                LabeledContent("Street") {
                    TextField("Street address", text: $street)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.streetAddressLine1)
                        .textInputAutocapitalization(.words)
                }
                LabeledContent("Suburb") {
                    TextField("Suburb", text: $suburb)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
                Picker("State", selection: $state) {
                    ForEach(RosterLocation.states, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: state) { _, newValue in
                    city = RosterLocation.capital(for: newValue)
                }
                LabeledContent("City") {
                    TextField("City", text: $city)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }
            }

            Section("Contact") {
                LabeledContent("Phone") {
                    HStack(spacing: 6) {
                        Text("+61")
                            .foregroundStyle(Theme.textSecondary)
                        TextField("412 345 678", text: $phoneLocal)
                            .keyboardType(.numberPad)
                            .textContentType(.telephoneNumber)
                            .onChange(of: phoneLocal) { _, newValue in
                                let formatted = RosterFormat.auPhoneLocal(newValue)
                                if formatted != newValue { phoneLocal = formatted }
                            }
                    }
                    .frame(maxWidth: 200, alignment: .trailing)
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
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Company Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Company Details", icon: "building.2.fill")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarSaveButton(
                    isEnabled: isDirty && !companyName.trimmingCharacters(in: .whitespaces).isEmpty,
                    isWorking: isSaving
                ) {
                    save()
                }
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
        abn = RosterFormat.abn(settings.abn)
        acn = RosterFormat.acn(settings.acn)
        street = settings.businessStreet.isEmpty && settings.businessSuburb.isEmpty
            ? settings.businessAddress   // legacy single-line address
            : settings.businessStreet
        suburb = settings.businessSuburb
        if !settings.businessState.isEmpty { state = settings.businessState }
        city = settings.businessCity.isEmpty ? RosterLocation.capital(for: state) : settings.businessCity
        phoneLocal = RosterFormat.auPhoneLocal(
            settings.contactPhone.replacingOccurrences(of: "+61", with: ""))
        contactEmail = settings.contactEmail
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
