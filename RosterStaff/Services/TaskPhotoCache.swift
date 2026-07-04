import UIKit

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
}