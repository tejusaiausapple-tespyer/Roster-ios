import Foundation
import PhoneNumberKit

enum ContactValidation {
    private static let phoneUtility = PhoneNumberUtility()

    /// Australian national numbers are the default. A leading international
    /// country code switches parsing to that country's numbering plan.
    static func isValidPhone(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return (try? phoneUtility.parse(value, withRegion: "AU")) != nil
    }

    static func normalizedPhone(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = try? phoneUtility.parse(value, withRegion: "AU") else { return nil }
        return phoneUtility.format(number, toType: .e164)
    }

    static func phoneError(_ raw: String, required: Bool = true) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return required ? "Enter a phone number." : nil }
        guard isValidPhone(value) else {
            return "Enter a valid phone number for the selected country. Australian numbers use +61 by default."
        }
        return nil
    }

    static func isValidEmail(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(
            of: "^[A-Z0-9._%+-]+@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)+$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func emailError(_ raw: String, required: Bool = true) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return required ? "Enter an email address." : nil }
        return isValidEmail(value)
            ? nil
            : "Enter a complete email address, for example name@gmail.com or name@outlook.com."
    }
}

/// Mirrors `User` in src/types/index.ts (staff-relevant fields).
struct AppUser: Identifiable, Equatable {
    let id: String
    var fullName: String
    var email: String
    var phone: String?
    /// Manager-assigned employee ID (letters + numbers, e.g. "EMP001").
    /// Shown on the staff profile and snapshotted onto payslips.
    var employeeId: String?
    var role: UserRole
    var employmentType: EmploymentType?
    var mustChangePassword: Bool
    var status: UserStatus
    var startDate: String?
    var dob: String?
    var address: String?
    /// Australian Tax File Number (9 digits). Manager-only; retained after Auth purge.
    var tfn: String?
    /// Account deletion lifecycle (Worker-managed). See `AccountDeletionState`.
    var deletion: AccountDeletionState?
    /// Legacy single-field emergency contact (kept in sync with name for PWA compat).
    var emergencyContact: String?
    var emergencyContactName: String?
    var emergencyContactPhone: String?
    var emergencyContactAddress: String?
    var emergencyContactEmail: String?
    var notes: String?
    var defaultLocation: String?
    /// Manager-set job title / role (e.g. "Console Operator"), shown on the
    /// staff directory and used to default the Role field when the manager
    /// creates a new shift for this staff member — set once, no need to
    /// re-pick it every time. One of `ManagerShiftEditorSheet.roleOptions`,
    /// or nil if never set.
    var defaultDepartment: String?
    var needsSetup: Bool
    var createdAt: String?
    var updatedAt: String?
    var lastLoginAt: String?
    var theme: String?
    var availability: UserAvailability?
    var weeklyAvailability: [String: UserAvailability]
    var hourlyRate: Double?
    /// Superannuation percentage for this employee (e.g. 12.0), manager-set.
    /// Used by upcoming payroll calculations.
    var superRate: Double?
    var profileUpdateRequired: Bool
    /// Manager-requested gate: staff must provide emergency contact details
    /// before the iPhone app will open the main workspace.
    var emergencyDetailsRequired: Bool
    /// Set when a manager changes the staff member's role. Staff must review
    /// and acknowledge the new role before continuing in the iPhone app.
    var roleReviewRequired: Bool
    /// Set by a manager to prompt the staff member to change their own sign-in
    /// email (staff completes the change via Firebase's verified flow).
    var emailChangeRequired: Bool

    var firstName: String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.joined().isEmpty ? "?" : letters.joined()
    }

    init?(id: String, data: [String: Any]) {
        self.id = id
        self.fullName = FS.stringValue(data, "fullName")
        self.email = FS.stringValue(data, "email")
        self.phone = FS.string(data, "phone")
        self.employeeId = FS.string(data, "employeeId")
        self.role = UserRole(rawValue: FS.stringValue(data, "role", default: "staff")) ?? .staff
        self.employmentType = FS.string(data, "employmentType").flatMap { EmploymentType(rawValue: $0) }
        self.mustChangePassword = FS.bool(data, "mustChangePassword")
        self.status = UserStatus(rawValue: FS.stringValue(data, "status", default: "active")) ?? .active
        self.startDate = FS.string(data, "startDate")
        self.dob = FS.string(data, "dob")
        self.address = FS.string(data, "address")
        // TFN is manager-facing; staff clients still receive the field on their
        // own doc (Firestore cannot redact fields) but we never surface it in staff UI.
        self.tfn = FS.string(data, "tfn")
        if let deletionMap = data["deletion"] as? [String: Any] {
            self.deletion = AccountDeletionState(dict: deletionMap)
        } else {
            self.deletion = nil
        }
        self.emergencyContact = FS.string(data, "emergencyContact")
        self.emergencyContactName = FS.string(data, "emergencyContactName")
        self.emergencyContactPhone = FS.string(data, "emergencyContactPhone")
        self.emergencyContactAddress = FS.string(data, "emergencyContactAddress")
        self.emergencyContactEmail = FS.string(data, "emergencyContactEmail")
        if self.emergencyContactName?.isEmpty != false,
           let legacy = self.emergencyContact, !legacy.isEmpty {
            self.emergencyContactName = legacy
        }
        self.notes = FS.string(data, "notes")
        self.defaultLocation = FS.string(data, "defaultLocation")
        self.defaultDepartment = FS.string(data, "defaultDepartment")
        self.needsSetup = FS.bool(data, "needsSetup")
        self.createdAt = FS.isoString(data, "createdAt")
        self.updatedAt = FS.isoString(data, "updatedAt")
        self.lastLoginAt = FS.isoString(data, "lastLoginAt")
        self.theme = FS.string(data, "theme")
        if let avail = FS.stringMap(data, "availability") {
            self.availability = UserAvailability(dict: avail)
        } else {
            self.availability = nil
        }
        var weekly: [String: UserAvailability] = [:]
        if let weeklyDict = FS.stringMap(data, "weeklyAvailability") {
            for (key, value) in weeklyDict {
                if let dayDict = value as? [String: Any] {
                    weekly[key] = UserAvailability(dict: dayDict)
                }
            }
        }
        self.weeklyAvailability = weekly
        self.hourlyRate = (data["hourlyRate"] as? NSNumber)?.doubleValue
        self.superRate = (data["superRate"] as? NSNumber)?.doubleValue
        self.profileUpdateRequired = FS.bool(data, "profileUpdateRequired")
        self.emergencyDetailsRequired = FS.bool(data, "emergencyDetailsRequired")
        self.roleReviewRequired = FS.bool(data, "roleReviewRequired")
        self.emailChangeRequired = FS.bool(data, "emailChangeRequired")
    }

    /// Whether staff must complete their profile before dashboard access.
    /// Mirrors `needsStaffProfileCompletion` / `isProfileComplete`.
    var needsProfileCompletion: Bool {
        guard role == .staff else { return false }
        let complete = !(dob?.isEmpty ?? true) && !(address?.isEmpty ?? true) && !(phone?.isEmpty ?? true)
        return !complete || profileUpdateRequired || emergencyDetailsRequired || roleReviewRequired
    }

    var memberSince: String? {
        guard let startDate, !startDate.isEmpty else {
            return createdAt.flatMap { FS.isoDate(from: $0) }.map { RosterFormat.monthYear($0) }
        }
        if let d = RosterFormat.parseISODate(startDate) {
            return RosterFormat.monthYear(d)
        }
        return startDate
    }
}
