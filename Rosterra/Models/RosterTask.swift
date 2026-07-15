import Foundation
import FirebaseFirestore

struct RosterTask: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let description: String?
    let managerPhotoUrl: String?
    let frequency: String // "once", "daily", "weekly"
    let date: String?     // yyyy-MM-dd (if once)
    let dayOfWeek: [Int]? // [1, 3, 5] (if weekly, 1=Monday...7=Sunday)
    let active: Bool
    let createdAt: Date?
    let createdBy: String?
    // Assignment & scheduling (nil on legacy docs)
    let assignedTo: [String]?   // staff UIDs; nil/empty = all staff
    let dueTime: String?        // "HH:mm" — due by this time on active days
    let priority: String?       // "low" | "normal" | "high"
    let requiresPhoto: Bool?    // nil = true (legacy behavior)
    let endDate: String?        // yyyy-MM-dd — recurring tasks stop after this

    var photoRequired: Bool { requiresPhoto ?? true }
    var priorityLevel: TaskPriority { TaskPriority(rawValue: priority ?? "") ?? .normal }

    /// Whether the task is assigned to the given user (nil/empty = everyone).
    func isAssigned(to userId: String?) -> Bool {
        guard let assignedTo, !assignedTo.isEmpty else { return true }
        guard let userId else { return false }
        return assignedTo.contains(userId)
    }

    /// Whether the task is scheduled on the given day.
    /// `weekday` uses 1=Monday...7=Sunday (RosterCalendar convention).
    func isActive(onDayKey dayKey: String, weekday: Int) -> Bool {
        guard active else { return false }
        if let endDate, dayKey > endDate { return false }
        switch frequency {
        case "once":   return date == dayKey
        case "weekly": return dayOfWeek?.contains(weekday) ?? false
        default:       return true // "daily"
        }
    }
}

enum TaskPriority: String, CaseIterable, Codable {
    case low, normal, high

    var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    /// Sort weight: high first.
    var weight: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

struct TaskCompletion: Identifiable, Codable {
    var id: String // "{taskId}_{date}"
    let taskId: String
    let date: String // yyyy-MM-dd
    let completed: Bool
    let completedAt: Date?
    let completedBy: String?
    let staffPhotoUrl: String?      // legacy single photo (PWA-shared field; first photo mirrored here)
    let staffPhotoUrls: [String]?   // all proof photos (gs:// references)
    // Review workflow (nil on legacy docs)
    let note: String?                // staff note on completion
    let status: String?              // "completed" | "redo"
    let redoReason: String?          // manager's reason when requesting a redo
    let reviewedBy: String?
    let reviewedAt: Date?
    /// Stamped the first time a manager device downloads the photo; drives
    /// the 14-day cloud cleanup sweep.
    let managerDownloadedAt: Date?

    var isRedoRequested: Bool { status == "redo" }

    /// All proof-photo references, tolerating legacy single-photo docs.
    var photoUrls: [String] {
        if let staffPhotoUrls, !staffPhotoUrls.isEmpty { return staffPhotoUrls }
        if let staffPhotoUrl, !staffPhotoUrl.isEmpty { return [staffPhotoUrl] }
        return []
    }
}
