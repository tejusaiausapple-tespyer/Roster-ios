import Foundation
import FirebaseFirestore

/// Daily Jobs are separate from Tasks: managers keep a permanent library of
/// reusable job templates and assign a selection to a specific staff member's
/// specific shift. Assignments expire with the shift; templates never do.
/// See docs/daily-jobs-feature.md.
struct DailyJobTemplate: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let active: Bool
    let createdAt: Date?
    let createdBy: String?
}

/// One job assigned to one shift. Doc ID is "{shiftId}_{templateId}" so
/// re-assigning the same job to the same shift is idempotent.
struct DailyJobAssignment: Identifiable, Codable {
    var id: String
    let shiftId: String
    let staffId: String
    let templateId: String
    let title: String        // snapshot — template edits don't rewrite history
    let date: String         // shift date (yyyy-MM-dd), for windowed queries
    let assignedAt: Date?
    let assignedBy: String?
    let completed: Bool
    let completedAt: Date?
    let completedBy: String?

    static func docId(shiftId: String, templateId: String) -> String {
        "\(shiftId)_\(templateId)"
    }

    /// Staff see an assignment from the moment it lands until the shift ends
    /// (manager history keeps it forever).
    func isVisibleToStaff(shiftEnd: Date?, now: Date = Date()) -> Bool {
        guard let shiftEnd else { return date == RosterCalendar.todayKey(now) }
        return now < shiftEnd
    }
}
