import XCTest
@testable import Rosterra

/// Manager Tenure & Hours calculations: service tenure is anchored on the first
/// approved shift, hours are summed from approved timesheets. Business timezone
/// is Australia/Adelaide.
final class TenureMetricsTests: XCTestCase {

    // Fixed "now": Wednesday 3 June 2026, noon Adelaide.
    private let now = TestSupport.instant("2026-06-03", "12:00")

    func testTenureFromFirstApprovedShift() {
        let staff = TestSupport.user(id: "u1", fullName: "Ana Ng",
                                     extra: ["startDate": "2026-01-01", "employmentType": "casual"])
        let shifts = [
            TestSupport.shift(id: "s1", staffId: "u1", date: "2026-05-04"), // first
            TestSupport.shift(id: "s2", staffId: "u1", date: "2026-05-25"),
        ]
        let timesheets = [
            TestSupport.timesheet(id: "s1", shiftId: "s1", staffId: "u1", status: "approved", workedHours: 6),
            TestSupport.timesheet(id: "s2", shiftId: "s2", staffId: "u1", status: "approved", workedHours: 4),
        ]

        let rows = TenureMetrics.compute(users: [staff], timesheets: timesheets, shifts: shifts, now: now)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        // 2026-05-04 -> 2026-06-03 is 30 days.
        XCTAssertEqual(row.tenureDays, 30)
        XCTAssertEqual(row.totalApprovedHours, 10)
    }

    func testOnlyApprovedTimesheetsCount() {
        let staff = TestSupport.user(id: "u1", fullName: "Bo Li")
        let shifts = [TestSupport.shift(id: "s1", staffId: "u1", date: "2026-05-30")]
        let timesheets = [
            TestSupport.timesheet(id: "s1", shiftId: "s1", staffId: "u1", status: "approved", workedHours: 5),
            TestSupport.timesheet(id: "s2", shiftId: "s2", staffId: "u1", status: "pending", workedHours: 8),
            TestSupport.timesheet(id: "s3", shiftId: "s3", staffId: "u1", status: "rejected", workedHours: 8),
        ]

        let row = TenureMetrics.compute(users: [staff], timesheets: timesheets, shifts: shifts, now: now)[0]
        XCTAssertEqual(row.totalApprovedHours, 5, "pending/rejected excluded")
    }

    func testNoApprovedShiftsHasZeroTenure() {
        let staff = TestSupport.user(id: "u1", fullName: "Cy Kim")
        let row = TenureMetrics.compute(users: [staff], timesheets: [], shifts: [], now: now)[0]
        XCTAssertNil(row.firstApprovedDate)
        XCTAssertEqual(row.tenureDays, 0)
        XCTAssertEqual(row.totalApprovedHours, 0)
        XCTAssertEqual(row.avgWeeklyHours, 0)
    }

    func testManagersExcluded() {
        let manager = TestSupport.user(id: "m1", fullName: "Mgr", role: "manager")
        let staff = TestSupport.user(id: "u1", fullName: "Staff")
        let rows = TenureMetrics.compute(users: [manager, staff], timesheets: [], shifts: [], now: now)
        XCTAssertEqual(rows.map(\.id), ["u1"], "only staff-role users are included")
    }

    func testSubmittedAtFallbackWhenShiftMissing() {
        let staff = TestSupport.user(id: "u1", fullName: "Di Wu")
        // Approved timesheet whose shift left the loaded window -> use submittedAt.
        let ts = TestSupport.timesheet(
            id: "s1", shiftId: "s-old", staffId: "u1", status: "approved", workedHours: 7,
            submittedAt: TestSupport.instant("2026-05-04", "18:00"))
        let row = TenureMetrics.compute(users: [staff], timesheets: [ts], shifts: [], now: now)[0]
        XCTAssertNotNil(row.firstApprovedDate)
        XCTAssertEqual(row.tenureDays, 30)
    }

    func testTenureStringFormatting() {
        XCTAssertEqual(TenureMetrics.tenureString(days: 0), "—")
        XCTAssertEqual(TenureMetrics.tenureString(days: 1), "1 day")
        XCTAssertEqual(TenureMetrics.tenureString(days: 5), "5 days")
        XCTAssertEqual(TenureMetrics.tenureString(days: 14), "2 wks")
        XCTAssertEqual(TenureMetrics.tenureString(days: 400), "1 yr, 1 mo")
    }
}
