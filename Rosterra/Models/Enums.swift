import Foundation

/// Mirrors `UserRole` in src/types/index.ts
enum UserRole: String, Codable {
    case manager
    case staff
}

/// Mirrors `UserStatus`
enum UserStatus: String, Codable {
    case active
    case inactive
    case locked
}

/// Mirrors `EmploymentType`
enum EmploymentType: String, Codable, CaseIterable {
    case fullTime = "full_time"
    case partTime = "part_time"
    case casual

    var label: String {
        switch self {
        case .fullTime: return "Full-time"
        case .partTime: return "Part-time"
        case .casual: return "Casual"
        }
    }
}

/// Mirrors `ShiftStatus`
enum ShiftStatus: String, Codable {
    case draft
    case published
    case completed
    case cancelled
}

/// Mirrors `TimesheetStatus`
enum TimesheetStatus: String, Codable {
    case draft
    case pending
    case approved
    case rejected
    case absentReported = "absent_reported"
    case absent
}

/// Manager-facing lifecycle status for a shift on the Dashboard.
/// Derived by `BusinessRules.managerShiftStatus` from the schedule + timesheet.
enum ManagerShiftStatus: Equatable {
    case scheduled          // shift has not started yet
    case inProgress         // now is within the scheduled window
    case pendingSubmission  // shift ended, staff has not submitted hours
    case awaitingApproval   // timesheet submitted, waiting on the manager
    case approved           // manager approved — shift complete
    case rejected           // manager rejected — staff must resubmit
    case absence            // staff reported (or manager confirmed) an absence

    var title: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .pendingSubmission: return "Pending"
        case .awaitingApproval: return "Awaiting Approval"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .absence: return "Absent"
        }
    }
}

/// Staff-facing display status for a shift card. Combines shift + timesheet state.
/// Mirrors `getStaffShiftDisplayStatus` in src/lib/utils.ts.
enum StaffShiftDisplayStatus: String {
    case scheduled
    case awaitingSubmission = "awaiting_submission"
    case draft
    case pending
    case approved
    case rejected
    case absentReported = "absent_reported"
    case absent

    var title: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .awaitingSubmission: return "Awaiting submission"
        case .draft: return "Draft"
        case .pending: return "Pending review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .absentReported: return "Absence reported"
        case .absent: return "Absent"
        }
    }
}
