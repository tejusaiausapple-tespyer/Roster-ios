import Foundation

/// Mirrors `Timesheet` in src/types/index.ts. Document id == shiftId (1:1).
struct Timesheet: Identifiable, Equatable {
    let id: String
    var shiftId: String
    var staffId: String
    var actualStart: String
    var actualEnd: String
    var actualBreakMinutes: Int
    var workedHours: Double
    var staffNotes: String?
    var status: TimesheetStatus
    var managerNotes: String?
    var approvedBy: String?
    var approvedAt: String?
    var rejectedReason: String?
    var submittedAt: Date?
    var updatedAt: String?

    init?(id: String, data: [String: Any]) {
        self.id = id
        self.shiftId = FS.stringValue(data, "shiftId")
        self.staffId = FS.stringValue(data, "staffId")
        self.actualStart = FS.stringValue(data, "actualStart")
        self.actualEnd = FS.stringValue(data, "actualEnd")
        self.actualBreakMinutes = FS.int(data, "actualBreakMinutes")
        self.workedHours = FS.double(data, "workedHours")
        self.staffNotes = FS.string(data, "staffNotes")
        self.status = TimesheetStatus(rawValue: FS.stringValue(data, "status", default: "pending")) ?? .pending
        self.managerNotes = FS.string(data, "managerNotes")
        self.approvedBy = FS.string(data, "approvedBy")
        self.approvedAt = FS.isoString(data, "approvedAt")
        self.rejectedReason = FS.string(data, "rejectedReason")
        self.submittedAt = FS.date(data, "submittedAt")
        self.updatedAt = FS.isoString(data, "updatedAt")
    }

    /// Mirrors `isStaffReportedAbsence`.
    var isStaffReportedAbsence: Bool { status == .absentReported }

    /// Whether staff may still edit / resubmit this record.
    /// Mirrors `isStaffEditableTimesheetStatus`.
    var isStaffEditable: Bool {
        switch status {
        case .draft, .pending, .rejected, .absentReported: return true
        case .approved, .absent: return false
        }
    }
}
