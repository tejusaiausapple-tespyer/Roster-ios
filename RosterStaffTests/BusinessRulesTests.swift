import XCTest
@testable import RosterStaff

/// Locks in the behavior of the pure business logic that both role UIs depend
/// on. All `now` values are injected; wall-clock times are Australia/Adelaide.
final class BusinessRulesTests: XCTestCase {

    // MARK: - Shift instants

    func testShiftStartDateTimeComponents() {
        let date = BusinessRules.shiftStartDateTime(date: "2026-03-10", time: "09:30")
        let comps = RosterCalendar.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 10)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 30)
    }

    func testShiftEndSameDay() {
        let end = BusinessRules.shiftEndDateTime(date: "2026-03-10", start: "09:00", end: "17:00")
        let comps = RosterCalendar.calendar.dateComponents([.day, .hour], from: end)
        XCTAssertEqual(comps.day, 10)
        XCTAssertEqual(comps.hour, 17)
    }

    func testShiftEndCrossesMidnight() {
        // end <= start means the shift finishes the next day
        let end = BusinessRules.shiftEndDateTime(date: "2026-03-10", start: "22:00", end: "06:00")
        let comps = RosterCalendar.calendar.dateComponents([.day, .hour], from: end)
        XCTAssertEqual(comps.day, 11)
        XCTAssertEqual(comps.hour, 6)
    }

    func testShiftInstantsAcrossDSTStart() {
        // Adelaide DST ends 2026-04-05 03:00 (clocks back). An 8h wall-clock
        // shift on that day is 9h of absolute time — verify the instants are
        // wall-clock anchored, not offset-anchored.
        let start = BusinessRules.shiftStartDateTime(date: "2026-04-05", time: "00:30")
        let end = BusinessRules.shiftEndDateTime(date: "2026-04-05", start: "00:30", end: "08:30")
        let hours = end.timeIntervalSince(start) / 3600
        XCTAssertEqual(hours, 9.0, accuracy: 0.01,
                       "wall-clock 00:30–08:30 spans the repeated DST hour")
    }

    // MARK: - Worked hours

    func testCalcWorkedHoursStandard() {
        XCTAssertEqual(BusinessRules.calcWorkedHours(start: "09:00", end: "17:00", breakMinutes: 30), 7.5)
    }

    func testCalcWorkedHoursCrossesMidnight() {
        XCTAssertEqual(BusinessRules.calcWorkedHours(start: "22:00", end: "06:00", breakMinutes: 0), 8.0)
    }

    func testCalcWorkedHoursRounding() {
        // 20 minutes = 0.3333h -> rounded to 2dp = 0.33
        XCTAssertEqual(BusinessRules.calcWorkedHours(start: "09:00", end: "09:20", breakMinutes: 0), 0.33)
    }

    func testCalcWorkedHoursBreakExceedsSpan() {
        XCTAssertEqual(BusinessRules.calcWorkedHours(start: "09:00", end: "09:15", breakMinutes: 30), 0)
    }

    func testCalcWorkedHoursInvalidInput() {
        XCTAssertEqual(BusinessRules.calcWorkedHours(start: "garbage", end: "17:00", breakMinutes: 0), 0)
    }

    func testClampBreakMinutes() {
        XCTAssertEqual(BusinessRules.clampBreakMinutes(-5), 0)
        XCTAssertEqual(BusinessRules.clampBreakMinutes(45), 45)
        XCTAssertEqual(BusinessRules.clampBreakMinutes(120), 90)
    }

    // MARK: - Visibility windows

    func testStaffShiftDateRange() {
        let now = TestSupport.instant("2026-06-01", "12:00") // a Monday
        let range = BusinessRules.staffShiftDateRange(at: now)
        XCTAssertEqual(range.start, "2026-05-04") // 28 days back
        XCTAssertEqual(range.end, "2026-07-27")   // 56 days forward
    }

    func testShiftWeekOffsetBoundsFromAMonday() {
        let now = TestSupport.instant("2026-06-01", "12:00") // Monday
        let bounds = BusinessRules.shiftWeekOffsetBounds(at: now)
        XCTAssertEqual(bounds.min, -4) // 28 days = exactly 4 Mondays back
        XCTAssertEqual(bounds.max, 8)  // 56 days = exactly 8 Mondays forward
    }

    func testManagerTimesheetCutoffIs90Days() {
        let now = TestSupport.instant("2026-06-01", "12:00")
        let cutoff = BusinessRules.managerTimesheetCutoff(at: now)
        let days = now.timeIntervalSince(cutoff) / 86_400
        XCTAssertEqual(days, 90, accuracy: 0.1)
    }

    // MARK: - Week lock

    func testWeekLock() {
        let now = TestSupport.instant("2026-06-03", "12:00") // Wed of week 2026-06-01
        XCTAssertTrue(BusinessRules.isWeekLockedForStaff(weekStartKey: "2026-06-01", at: now), "current week locked")
        XCTAssertTrue(BusinessRules.isWeekLockedForStaff(weekStartKey: "2026-05-25", at: now), "past week locked")
        XCTAssertFalse(BusinessRules.isWeekLockedForStaff(weekStartKey: "2026-06-08", at: now), "next week editable")
    }

    func testRecurringWeekKeysSpanHorizon() {
        let now = TestSupport.instant("2026-06-01", "12:00") // Monday
        let keys = BusinessRules.recurringWeekKeys(fromMonday: now, at: now)
        // Current Monday through +12 weeks inclusive = 13 keys
        XCTAssertEqual(keys.count, 13)
        XCTAssertEqual(keys.first, "2026-06-01")
        XCTAssertEqual(keys.last, "2026-08-24")
    }

    // MARK: - Display status & action gates

    private let shiftDay = "2026-06-02"
    private var beforeShiftEnd: Date { TestSupport.instant("2026-06-02", "12:00") }
    private var afterShiftEnd: Date { TestSupport.instant("2026-06-02", "18:00") }

    func testDisplayStatusScheduledBeforeEnd() {
        let shift = TestSupport.shift(date: shiftDay)
        XCTAssertEqual(BusinessRules.displayStatus(for: shift, timesheet: nil, at: beforeShiftEnd), .scheduled)
    }

    func testDisplayStatusAwaitingSubmissionAfterEnd() {
        let shift = TestSupport.shift(date: shiftDay)
        XCTAssertEqual(BusinessRules.displayStatus(for: shift, timesheet: nil, at: afterShiftEnd), .awaitingSubmission)
    }

    func testDisplayStatusMirrorsTimesheet() {
        let shift = TestSupport.shift(date: shiftDay)
        let approved = TestSupport.timesheet(status: "approved")
        let absent = TestSupport.timesheet(status: "absent_reported")
        XCTAssertEqual(BusinessRules.displayStatus(for: shift, timesheet: approved, at: afterShiftEnd), .approved)
        XCTAssertEqual(BusinessRules.displayStatus(for: shift, timesheet: absent, at: afterShiftEnd), .absentReported)
    }

    func testCanSubmitHoursGates() {
        let published = TestSupport.shift(date: shiftDay)
        let draft = TestSupport.shift(date: shiftDay, status: "draft")

        // Time gate: not before end, yes after
        XCTAssertFalse(BusinessRules.canSubmitHours(shift: published, timesheet: nil, at: beforeShiftEnd))
        XCTAssertTrue(BusinessRules.canSubmitHours(shift: published, timesheet: nil, at: afterShiftEnd))

        // Status gate: drafts never submittable
        XCTAssertFalse(BusinessRules.canSubmitHours(shift: draft, timesheet: nil, at: afterShiftEnd))

        // Timesheet gate: only rejected allows resubmission
        XCTAssertTrue(BusinessRules.canSubmitHours(shift: published, timesheet: TestSupport.timesheet(status: "rejected"), at: afterShiftEnd))
        XCTAssertFalse(BusinessRules.canSubmitHours(shift: published, timesheet: TestSupport.timesheet(status: "pending"), at: afterShiftEnd))
        XCTAssertFalse(BusinessRules.canSubmitHours(shift: published, timesheet: TestSupport.timesheet(status: "approved"), at: afterShiftEnd))
    }

    func testCanReportAbsenceGates() {
        let shift = TestSupport.shift(date: shiftDay)
        XCTAssertFalse(BusinessRules.canReportAbsence(shift: shift, timesheet: nil, at: beforeShiftEnd), "time gate")
        XCTAssertTrue(BusinessRules.canReportAbsence(shift: shift, timesheet: nil, at: afterShiftEnd))
        XCTAssertTrue(BusinessRules.canReportAbsence(shift: shift, timesheet: TestSupport.timesheet(status: "rejected"), at: afterShiftEnd))
        XCTAssertFalse(BusinessRules.canReportAbsence(shift: shift, timesheet: TestSupport.timesheet(status: "approved"), at: afterShiftEnd))
    }

    func testNeedsStaffAction() {
        let shift = TestSupport.shift(date: shiftDay)
        XCTAssertFalse(BusinessRules.needsStaffAction(shift: shift, timesheet: nil, at: beforeShiftEnd))
        XCTAssertTrue(BusinessRules.needsStaffAction(shift: shift, timesheet: nil, at: afterShiftEnd), "unsubmitted after end")
        XCTAssertTrue(BusinessRules.needsStaffAction(shift: shift, timesheet: TestSupport.timesheet(status: "rejected"), at: afterShiftEnd))
        XCTAssertTrue(BusinessRules.needsStaffAction(shift: shift, timesheet: TestSupport.timesheet(status: "absent_reported"), at: beforeShiftEnd), "undoable absence")
        XCTAssertFalse(BusinessRules.needsStaffAction(shift: shift, timesheet: TestSupport.timesheet(status: "approved"), at: afterShiftEnd))
    }

    func testSubmittableAfterOverridesEndTime() {
        var data: [String: Any] = [
            "staffId": "staff-1", "date": shiftDay,
            "rosteredStart": "09:00", "rosteredEnd": "17:00",
            "status": "published",
        ]
        data["submittableAfter"] = TestSupport.instant("2026-06-02", "20:00")
        let shift = Shift(id: "s", data: data)!
        XCTAssertFalse(shift.isSubmittable(at: afterShiftEnd), "18:00 is before the 20:00 override")
        XCTAssertTrue(shift.isSubmittable(at: TestSupport.instant("2026-06-02", "20:01")))
    }

    // MARK: - Password rules (actual required set: length, uppercase, digit)

    func testPasswordErrorsAllMissing() {
        XCTAssertEqual(BusinessRules.passwordErrors("abc").count, 3)
    }

    func testPasswordValidWithoutSymbol() {
        // A symbol is recommended in the UI checklist but NOT required.
        XCTAssertTrue(BusinessRules.passwordErrors("Abcdefg1").isEmpty)
    }

    func testPasswordMissingUppercase() {
        XCTAssertEqual(BusinessRules.passwordErrors("abcdefg1"), ["One uppercase letter"])
    }

    func testPasswordMissingDigit() {
        XCTAssertEqual(BusinessRules.passwordErrors("Abcdefgh"), ["One number"])
    }

    func testPasswordRulesChecklistShape() {
        let rules = BusinessRules.passwordRules("Abcdefg1")
        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(rules.filter(\.required).count, 3)
        let symbolRule = rules.first { !$0.required }
        XCTAssertEqual(symbolRule?.isMet, false)
    }
}
