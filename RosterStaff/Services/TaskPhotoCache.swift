import UIKit

/// Private on-device store for task verification photos. Photos live only in
/// the app sandbox (never the phone gallery) so the manager can review them
/// without re-downloading from Firebase Storage, and staff keep a temporary
/// local copy until their week ends.
struct TaskPhotoCache {
    private static var folderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("task_photos", isDirectory: true)
    }
    
    static func createFolderIfNeeded() {
        let url = folderURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    static func save(image: UIImage, taskId: String, date: String) {
        createFolderIfNeeded()
        let fileURL = folderURL.appendingPathComponent("\(taskId)_\(date).jpg")
        if let data = image.jpegData(compressionQuality: 0.5) {
            try? data.write(to: fileURL)
        }
    }
    
    static func load(taskId: String, date: String) -> UIImage? {
        let fileURL = folderURL.appendingPathComponent("\(taskId)_\(date).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    static func delete(taskId: String, date: String) {
        let fileURL = folderURL.appendingPathComponent("\(taskId)_\(date).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Retention sweeps

    /// Filenames are "{taskId}_{yyyy-MM-dd}.jpg" — the date is the last
    /// 10 characters of the stem.
    private static func dateKey(fromFilename name: String) -> String? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.count >= 10 else { return nil }
        let key = String(stem.suffix(10))
        return RosterCalendar.dateFromKey(key) != nil ? key : nil
    }

    /// Staff retention: photos are viewable only until the end of the week
    /// they were taken. Removes every cached photo dated before the current
    /// week's Monday. Runs on app launch for staff users.
    static func removePhotosBeforeCurrentWeek(now: Date = Date()) {
        removePhotos(datedBefore: RosterCalendar.weekStartKey(now))
    }

    /// Manager retention: keep the local review history for `days` then clean
    /// up. Runs on app launch for manager users.
    static func removePhotosOlderThan(days: Int, now: Date = Date()) {
        let cutoff = RosterCalendar.addDays(-days, to: now)
        removePhotos(datedBefore: RosterCalendar.todayKey(cutoff))
    }

    private static func removePhotos(datedBefore cutoffKey: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil) else { return }
        for file in files {
            guard let key = dateKey(fromFilename: file.lastPathComponent) else { continue }
            if key < cutoffKey {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}