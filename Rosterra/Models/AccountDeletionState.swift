import Foundation

enum AccountDeletionStatus: String, Equatable {
    case requested
    case approved
    case cancelled
    case authPurged = "auth_purged"
}

struct AccountDeletionIdentitySnapshot: Equatable {
    var fullName: String?
    var dob: String?
    var address: String?
    var tfn: String?
    var employeeId: String?
    var email: String?
    var phone: String?
    var startDate: String?
    var employmentType: String?

    init(dict: [String: Any]) {
        fullName = FS.string(dict, "fullName")
        dob = FS.string(dict, "dob")
        address = FS.string(dict, "address")
        tfn = FS.string(dict, "tfn")
        employeeId = FS.string(dict, "employeeId")
        email = FS.string(dict, "email")
        phone = FS.string(dict, "phone")
        startDate = FS.string(dict, "startDate")
        employmentType = FS.string(dict, "employmentType")
    }
}

struct AccountDeletionState: Equatable {
    var status: AccountDeletionStatus
    var requestedAt: String?
    var requestedByUid: String?
    var requestedVia: String?
    var approvedAt: String?
    var approvedByUid: String?
    var cancelDeadlineAt: String?
    var authPurgedAt: String?
    var retainedNote: String?
    var identitySnapshot: AccountDeletionIdentitySnapshot?

    init(dict: [String: Any]) {
        status = AccountDeletionStatus(rawValue: FS.stringValue(dict, "status")) ?? .requested
        requestedAt = FS.string(dict, "requestedAt")
        requestedByUid = FS.string(dict, "requestedByUid")
        requestedVia = FS.string(dict, "requestedVia")
        approvedAt = FS.string(dict, "approvedAt")
        approvedByUid = FS.string(dict, "approvedByUid")
        cancelDeadlineAt = FS.string(dict, "cancelDeadlineAt")
        authPurgedAt = FS.string(dict, "authPurgedAt")
        retainedNote = FS.string(dict, "retainedNote")
        if let snap = dict["identitySnapshot"] as? [String: Any] {
            identitySnapshot = AccountDeletionIdentitySnapshot(dict: snap)
        }
    }

    /// Adelaide-calendar cancel deadline as a Date, if parseable.
    var cancelDeadlineDate: Date? {
        guard let cancelDeadlineAt else { return nil }
        return FS.isoDate(from: cancelDeadlineAt)
    }
}
