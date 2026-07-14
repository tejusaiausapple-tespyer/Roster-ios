import Foundation
@testable import RosterStaff

/// Shared builders for domain objects, constructed through the same
/// `init?(id:data:)` paths production uses (so parsing is exercised too).
enum TestSupport {

    /// An absolute instant for a wall-clock time in the business timezone
    /// (Australia/Adelaide), e.g. `instant("2026-06-01", "12:00")`.
    /// Uses `BusinessRules.shiftStartDateTime`, which is itself verified
    /// independently in `BusinessRulesTests.testShiftStartDateTimeComponents`.
    static func instant(_ dayKey: String, _ time: String) -> Date {
        BusinessRules.shiftStartDateTime(date: dayKey, time: time)
    }

    static func shift(
        id: String = "shift-1",
        staffId: String = "staff-1",
        date: String,
        start: String = "09:00",
        end: String = "17:00",
        breakMinutes: Int = 30,
        scheduledHours: Double = 7.5,
        status: String = "published"
    ) -> Shift {
        Shift(id: id, data: [
            "staffId": staffId,
            "date": date,
            "rosteredStart": start,
            "rosteredEnd": end,
            "breakMinutes": breakMinutes,
            "scheduledHours": scheduledHours,
            "status": status,
        ])!
    }

    static func timesheet(
        id: String = "shift-1",
        shiftId: String = "shift-1",
        staffId: String = "staff-1",
        status: String = "pending",
        workedHours: Double = 7.5,
        actualStart: String = "09:00",
        actualEnd: String = "17:00",
        submittedAt: Date? = nil,
        rejectedReason: String? = nil
    ) -> Timesheet {
        var data: [String: Any] = [
            "shiftId": shiftId,
            "staffId": staffId,
            "status": status,
            "workedHours": workedHours,
            "actualStart": actualStart,
            "actualEnd": actualEnd,
            "actualBreakMinutes": 30,
        ]
        if let submittedAt { data["submittedAt"] = submittedAt }
        if let rejectedReason { data["rejectedReason"] = rejectedReason }
        return Timesheet(id: id, data: data)!
    }

    static func user(
        id: String = "staff-1",
        fullName: String = "Test Person",
        role: String = "staff",
        extra: [String: Any] = [:]
    ) -> AppUser {
        var data: [String: Any] = [
            "fullName": fullName,
            "email": "test@example.com",
            "role": role,
        ]
        data.merge(extra) { _, new in new }
        return AppUser(id: id, data: data)!
    }
}
