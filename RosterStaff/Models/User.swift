import Foundation

/// Mirrors `User` in src/types/index.ts (staff-relevant fields).
struct AppUser: Identifiable, Equatable {
    let id: String
    var fullName: String
    var email: String
    var phone: String?
    var role: UserRole
    var employmentType: EmploymentType?
    var mustChangePassword: Bool
    var status: UserStatus
    var startDate: String?
    var dob: String?
    var address: String?
    var emergencyContact: String?
    var notes: String?
    var defaultLocation: String?
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
        self.role = UserRole(rawValue: FS.stringValue(data, "role", default: "staff")) ?? .staff
        self.employmentType = FS.string(data, "employmentType").flatMap { EmploymentType(rawValue: $0) }
        self.mustChangePassword = FS.bool(data, "mustChangePassword")
        self.status = UserStatus(rawValue: FS.stringValue(data, "status", default: "active")) ?? .active
        self.startDate = FS.string(data, "startDate")
        self.dob = FS.string(data, "dob")
        self.address = FS.string(data, "address")
        self.emergencyContact = FS.string(data, "emergencyContact")
        self.notes = FS.string(data, "notes")
        self.defaultLocation = FS.string(data, "defaultLocation")
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
        self.emailChangeRequired = FS.bool(data, "emailChangeRequired")
    }

    /// Whether staff must complete their profile before dashboard access.
    /// Mirrors `needsStaffProfileCompletion` / `isProfileComplete`.
    var needsProfileCompletion: Bool {
        guard role == .staff else { return false }
        let complete = !(dob?.isEmpty ?? true) && !(address?.isEmpty ?? true) && !(phone?.isEmpty ?? true)
        return !complete || profileUpdateRequired
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
