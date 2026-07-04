import Foundation

/// Mirrors `Message` in src/types/index.ts (manager -> staff task messages).
struct Message: Identifiable, Equatable {
    let id: String
    var senderId: String
    var senderName: String?
    var recipientId: String
    var body: String
    var type: String?
    var sentAt: String     // ISO-8601
    var expiresAt: String  // ISO-8601
    var read: Bool

    init?(id: String, data: [String: Any]) {
        self.id = id
        self.senderId = FS.stringValue(data, "senderId")
        self.senderName = FS.string(data, "senderName")
        self.recipientId = FS.stringValue(data, "recipientId")
        self.body = FS.stringValue(data, "body")
        self.type = FS.string(data, "type")
        self.sentAt = FS.isoString(data, "sentAt") ?? ""
        self.expiresAt = FS.isoString(data, "expiresAt") ?? ""
        self.read = FS.bool(data, "read")
    }

    var sentDate: Date? { FS.isoDate(from: sentAt) }
    var expiresDate: Date? { FS.isoDate(from: expiresAt) }

    /// Non-expired messages are "active" (mirrors the Home notifications filter).
    func isActive(at now: Date = Date()) -> Bool {
        guard let expiresDate else { return true }
        return expiresDate > now
    }

    /// The message body split into bullet lines (matches the web notifications modal).
    var bodyLines: [String] {
        body
            .split(whereSeparator: { $0 == "\n" || $0 == "\u{2022}" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
