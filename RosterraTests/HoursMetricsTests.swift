import XCTest
@testable import Rosterra

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
        // (the shift left the ±28/56-day listener window). Bucketing falls
        // back to submittedAt — here a same-year, different-month date.
        let approvedOrphan = TestSupport.timesheet(
            id: "s-old", shiftId: "s-old", status: "approved", workedHours: 2,
            submittedAt: TestSupport.instant("2026-04-10", "18:00"))
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
        XCTAssertEqual(m.year, 10, "June 5h + May 3h + April orphan 2h via submittedAt fallback")
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

    /// Milestone 4 fix: approved timesheets whose shifts left the listener
    /// window bucket via their submittedAt fallback (shift date preferred
    /// when available).
    func testOrphanFallbackBucketing() {
        let orphanSameMonth = TestSupport.timesheet(
            id: "o1", shiftId: "o1", status: "approved", workedHours: 3,
            submittedAt: TestSupport.instant("2026-06-01", "17:30")) // this week + month
        let orphanNoDate = TestSupport.timesheet(
            id: "o2", shiftId: "o2", status: "approved", workedHours: 4) // no shift, no submittedAt

        let m = HoursMetrics.compute(timesheets: [orphanSameMonth, orphanNoDate], shifts: [], now: now)
        XCTAssertEqual(m.week, 3)
        XCTAssertEqual(m.month, 3)
        XCTAssertEqual(m.year, 3)
        XCTAssertEqual(m.all, 7, "undateable hours still count in the all-time total")
    }

    /// Shift date wins over submittedAt when both exist (late submissions
    /// must bucket to the week the shift was worked).
    func testShiftDatePreferredOverSubmittedAt() {
        let shift = TestSupport.shift(id: "s1", date: "2026-05-05") // May
        let ts = TestSupport.timesheet(
            id: "s1", shiftId: "s1", status: "approved", workedHours: 6,
            submittedAt: TestSupport.instant("2026-06-02", "10:00")) // submitted in June

        let m = HoursMetrics.compute(timesheets: [ts], shifts: [shift], now: now)
        XCTAssertEqual(m.month, 0, "buckets to May (shift date), not June (submission)")
        XCTAssertEqual(m.year, 6)
    }
}
