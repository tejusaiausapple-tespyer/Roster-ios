import Foundation

/// Mirrors the `settings/app` document. `companyName` is shared with the PWA;
/// the business-detail fields are manager-editable (Account → Company details)
/// and surface on the dashboards today. NOTE (future): a staff-facing Payslip
/// feature is planned that will render these business details (name, address,
/// ABN/ACN, contact) on generated payslips — keep new fields on this document.
struct AppSettings: Equatable {
    var companyName: String
    /// Composed display address ("Street, Suburb STATE") — derived from the
    /// structured fields on save; kept for back-compat and one-line display.
    var businessAddress: String
    var businessStreet: String
    var businessSuburb: String
    var businessState: String
    var businessCity: String
    var contactPhone: String
    var contactEmail: String
    var abn: String
    var acn: String
    var businessNotes: String

    static let fallback = AppSettings(companyName: "Rosterra")

    init(companyName: String,
         businessAddress: String = "",
         businessStreet: String = "",
         businessSuburb: String = "",
         businessState: String = "",
         businessCity: String = "",
         contactPhone: String = "",
         contactEmail: String = "",
         abn: String = "",
         acn: String = "",
         businessNotes: String = "") {
        self.companyName = companyName
        self.businessAddress = businessAddress
        self.businessStreet = businessStreet
        self.businessSuburb = businessSuburb
        self.businessState = businessState
        self.businessCity = businessCity
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.abn = abn
        self.acn = acn
        self.businessNotes = businessNotes
    }

    init(data: [String: Any]) {
        let rawName = FS.stringValue(data, "companyName")
        self.companyName = rawName.isEmpty ? "Rosterra" : rawName
        self.businessAddress = FS.stringValue(data, "businessAddress")
        self.businessStreet = FS.stringValue(data, "businessStreet")
        self.businessSuburb = FS.stringValue(data, "businessSuburb")
        self.businessState = FS.stringValue(data, "businessState")
        self.businessCity = FS.stringValue(data, "businessCity")
        self.contactPhone = FS.stringValue(data, "contactPhone")
        self.contactEmail = FS.stringValue(data, "contactEmail")
        self.abn = FS.stringValue(data, "abn")
        self.acn = FS.stringValue(data, "acn")
        self.businessNotes = FS.stringValue(data, "businessNotes")
    }

    var asDictionary: [String: Any] {
        [
            "companyName": companyName,
            "businessAddress": businessAddress,
            "businessStreet": businessStreet,
            "businessSuburb": businessSuburb,
            "businessState": businessState,
            "businessCity": businessCity,
            "contactPhone": contactPhone,
            "contactEmail": contactEmail,
            "abn": abn,
            "acn": acn,
            "businessNotes": businessNotes,
        ]
    }

    /// "Street, Suburb STATE" from the structured parts (empty parts skipped).
    static func composedAddress(street: String, suburb: String, state: String) -> String {
        let locality = [suburb, state].filter { !$0.isEmpty }.joined(separator: " ")
        return [street, locality].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
