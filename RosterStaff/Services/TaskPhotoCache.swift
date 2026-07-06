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
    
    /// Index 0 keeps the legacy un-suffixed filename so pre-multi-photo
    /// caches keep working; extra photos are "_p1", "_p2", ...
    private static func fileURL(taskId: String, date: String, index: Int) -> URL {
        let suffix = index == 0 ? "" : "_p\(index)"
        return folderURL.appendingPathComponent("\(taskId)_\(date)\(suffix).jpg")
    }

    static func save(image: UIImage, taskId: String, date: String, index: Int = 0) {
        createFolderIfNeeded()
        if let data = image.jpegData(compressionQuality: 0.5) {
            try? data.write(to: fileURL(taskId: taskId, date: date, index: index))
        }
    }

    static func load(taskId: String, date: String) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(taskId: taskId, date: date, index: 0)) else { return nil }
        return UIImage(data: data)
    }

    /// All cached photos for a completion, in capture order.
    static func loadAll(taskId: String, date: String) -> [UIImage] {
        var images: [UIImage] = []
        var index = 0
        while let data = try? Data(contentsOf: fileURL(taskId: taskId, date: date, index: index)),
              let image = UIImage(data: data) {
            images.append(image)
            index += 1
        }
        return images
    }

    static func delete(taskId: String, date: String) {
        var index = 0
        while FileManager.default.fileExists(atPath: fileURL(taskId: taskId, date: date, index: index).path) {
            try? FileManager.default.removeItem(at: fileURL(taskId: taskId, date: date, index: index))
            index += 1
        }
    }

    // MARK: - Retention sweeps

    /// Filenames are "{taskId}_{yyyy-MM-dd}.jpg" or "{taskId}_{yyyy-MM-dd}_pN.jpg"
    /// — scan the underscore-separated components for the date.
    private static func dateKey(fromFilename name: String) -> String? {
        let stem = (name as NSString).deletingPathExtension
        for part in stem.split(separator: "_").reversed() where part.count == 10 {
            let key = String(part)
            if RosterCalendar.dateFromKey(key) != nil { return key }
        }
        return nil
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