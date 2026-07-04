import XCTest
@testable import RosterStaff

/// Hours rollups shown on Home, History, and Account. Buckets are keyed by
/// *shift date* (not submission date), in Australia/Adelaide.
final class HoursMetricsTests: XCTestCase {

    // Fixed "now": Wednesday 3 June 2026, noon Adelaide.
    // Week = 2026-06-01 (Mon), month = June, year = 2026.
    private let now = TestSupport.instant("2026-06-03", "12:00")

    private func makeFixtures() -> (shifts: [Shift], timesheets: [Timesheet]) {
        let shiftThisWeek = TestSupport.shift(id: "s-week", date: "2026-06-02")
        let shiftLastMonth = TestSupport.shift(id: "s-may", date: "2026-05-05")
        let shifts = [shiftThisWeek, shiftLastMonth]

        let approvedThisWeek = TestSupport.timesheet(
            id: "s-week", shiftId: "s-week", status: "approved", workedHours: 5)
        let approvedLastMonth = TestSupport.timesheet(
            id: "s-may", shiftId: "s-may", status: "approved", workedHours: 3)
        // Approved timesheet whose shift is NOT in the loaded shift list
        // (e.g. the shift left the ±28/56-day listener window).
        let approvedOrphan = TestSupport.timesheet(
            id: "s-old", shiftId: "s-old", status: "approved", workedHours: 2)
        let pending = TestSupport.timesheet(
            id: "s-pend", shiftId: "s-week", status: "pending", workedHours: 4)
        let rejected = TestSupport.timesheet(
            id: "s-rej", shiftId: "s-week", status: "rejected", workedHours: 1)

        return (shifts, [approvedThisWeek, approvedLastMonth, approvedOrphan, pending, rejected])
    }

    func testApprovedBucketsByShiftDate() {
        let (shifts, timesheets) = makeFixtures()
        let m = HoursMetrics.compute(timesheets: timesheets, shifts: shifts, now: now)

        XCTAssertEqual(m.week, 5, "only the shift in the current Mon-start week")
        XCTAssertEqual(m.month, 5, "June only")
        XCTAssertEqual(m.year, 8, "June 5h + May 3h; orphan skipped (see known-bug test)")
        XCTAssertEqual(m.all, 10, "all approved hours incl. the orphan")
    }

    func testPendingAndRejectedCounts() {
        let (shifts, timesheets) = makeFixtures()
        let m = HoursMetrics.compute(timesheets: timesheets, shifts: shifts, now: now)

        XCTAssertEqual(m.pendingHours, 4)
        XCTAssertEqual(m.pendingCount, 1)
        XCTAssertEqual(m.rejectedCount, 1)
    }

    func testEmptyInput() {
        let m = HoursMetrics.compute(timesheets: [], shifts: [], now: now)
        XCTAssertEqual(m.all, 0)
        XCTAssertEqual(m.pendingCount, 0)
    }

    /// KNOWN BUG (roadmap Milestone 4): approved timesheets whose shifts have
    /// left the staff shift listener window (−28…+56 days) are missing from
    /// the year/month/week buckets, because bucketing needs the shift's date
    /// and the shift is no longer loaded. "This year" therefore undercounts
    /// after ~a month of history. This test asserts the DESIRED behavior and
    /// is marked as an expected failure; when Milestone 4 fixes the bucketing
    /// strategy, XCTExpectFailure will flag it for removal.
    func testYearIncludesOrphanApprovedHours_knownBug() throws {
        let (shifts, timesheets) = makeFixtures()
        // Give the orphan a same-year shift date via submittedAt context is not
        // possible today — the current implementation has no fallback at all.
        let m = HoursMetrics.compute(timesheets: timesheets, shifts: shifts, now: now)

        XCTExpectFailure("Milestone 4: orphan approved hours (2h) should count toward the year bucket") {
            XCTAssertEqual(m.year, 10)
        }
    }
}
