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
}

struct TaskCompletion: Identifiable, Codable {
    var id: String // "{taskId}_{date}"
    let taskId: String
    let date: String // yyyy-MM-dd
    let completed: Bool
    let completedAt: Date?
    let completedBy: String?
    let staffPhotoUrl: String?
}