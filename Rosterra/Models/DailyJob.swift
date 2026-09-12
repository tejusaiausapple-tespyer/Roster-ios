import Foundation
import FirebaseFirestore

/// Daily Jobs are separate from Tasks: managers keep a permanent library of
/// reusable job templates and assign a selection to a specific staff member's
/// specific shift. Staff see assignments for the full shift date; templates never do.
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
    /// Manager-arranged position within the shift — the order staff should
    /// work through the jobs in. `nil` on assignments written before this
    /// field existed; those sort after any explicitly-ordered ones.
    let order: Int?

    static func docId(shiftId: String, templateId: String) -> String {
        "\(shiftId)_\(templateId)"
    }

    /// Staff see an assignment for the full shift date (Adelaide calendar day),
    /// not just until rostered end time. Manager history keeps it forever.
    func isVisibleToStaff(now: Date = Date()) -> Bool {
        date == RosterCalendar.todayKey(now)
    }
}

/// One staff member's "keep repeating these jobs" preference. Doc ID is the
/// staffId (one rule per staff member). When `enabled`, every new shift
/// created for this staff member auto-gets `templateIds` assigned — the
/// manager no longer has to re-pick jobs each day. Disabling keeps
/// `templateIds` around so re-enabling doesn't lose the previous selection;
/// it only stops new shifts from being auto-populated.
struct DailyJobRepeatRule: Identifiable, Codable {
    @DocumentID var id: String?
    let templateIds: [String]
    let enabled: Bool
    let updatedAt: Date?
    let updatedBy: String?
}
