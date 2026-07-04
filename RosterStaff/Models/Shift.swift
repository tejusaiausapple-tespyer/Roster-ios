import Foundation

/// Mirrors `Shift` in src/types/index.ts (staff-relevant fields).
struct Shift: Identifiable, Equatable {
    let id: String
    var staffId: String
    var date: String            // YYYY-MM-DD
    var rosteredStart: String   // HH:mm
    var rosteredEnd: String     // HH:mm
    var breakMinutes: Int
    var scheduledHours: Double
    var location: String?
    var department: String?
    var notes: String?
    var status: ShiftStatus
    var submittableAfter: Date?
    var shiftStartAt: Date?

    init?(id: String, data: [String: Any]) {
        self.id = id
        self.staffId = FS.stringValue(data, "staffId")
        self.date = FS.stringValue(data, "date")
        self.rosteredStart = FS.stringValue(data, "rosteredStart")
        self.rosteredEnd = FS.stringValue(data, "rosteredEnd")
        self.breakMinutes = FS.int(data, "breakMinutes")
        self.scheduledHours = FS.double(data, "scheduledHours")
        self.location = FS.string(data, "location")
        self.department = FS.string(data, "department")
        self.notes = FS.string(data, "notes")
        self.status = ShiftStatus(rawValue: FS.stringValue(data, "status", default: "draft")) ?? .draft
        self.submittableAfter = FS.date(data, "submittableAfter")
        self.shiftStartAt = FS.date(data, "shiftStartAt")
    }

    /// Absolute start instant in the business timezone (mirrors getShiftStartDateTime).
    var startDateTime: Date {
        shiftStartAt ?? BusinessRules.shiftStartDateTime(date: date, time: rosteredStart)
    }

    /// Absolute end instant, accounting for shifts crossing midnight.
    var endDateTime: Date {
        BusinessRules.shiftEndDateTime(date: date, start: rosteredStart, end: rosteredEnd)
    }

    /// Instant after which the shift can be submitted/absence-reported.
    var submittableAfterDate: Date {
        submittableAfter ?? endDateTime
    }

    /// Mirrors `isShiftSubmittable`.
    func isSubmittable(at now: Date = Date()) -> Bool {
        now >= submittableAfterDate
    }
}
