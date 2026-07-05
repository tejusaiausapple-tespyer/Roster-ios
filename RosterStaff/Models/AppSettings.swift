import Foundation

/// Mirrors the `settings/app` document. `companyName` is shared with the PWA;
/// the business-detail fields are manager-editable (Account → Company details)
/// and surface on the dashboards today. NOTE (future): a staff-facing Payslip
/// feature is planned that will render these business details (name, address,
/// ABN, contact) on generated payslips — keep new fields on this document.
struct AppSettings: Equatable {
    var companyName: String
    var businessAddress: String
    var contactPhone: String
    var contactEmail: String
    var abn: String
    var businessNotes: String

    static let fallback = AppSettings(companyName: "Sura Roster")

    init(companyName: String,
         businessAddress: String = "",
         contactPhone: String = "",
         contactEmail: String = "",
         abn: String = "",
         businessNotes: String = "") {
        self.companyName = companyName
        self.businessAddress = businessAddress
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.abn = abn
        self.businessNotes = businessNotes
    }

    init(data: [String: Any]) {
        self.companyName = FS.string(data, "companyName") ?? "Sura Roster"
        self.businessAddress = FS.stringValue(data, "businessAddress")
        self.contactPhone = FS.stringValue(data, "contactPhone")
        self.contactEmail = FS.stringValue(data, "contactEmail")
        self.abn = FS.stringValue(data, "abn")
        self.businessNotes = FS.stringValue(data, "businessNotes")
    }

    var asDictionary: [String: Any] {
        [
            "companyName": companyName,
            "businessAddress": businessAddress,
            "contactPhone": contactPhone,
            "contactEmail": contactEmail,
            "abn": abn,
            "businessNotes": businessNotes,
        ]
    }
}
