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

final class HomeDashboardSnapshotTests: XCTestCase {

    func testFiltersSortsAndLimitsPublishedShifts() {
        let today = "2026-09-12"
        let shifts = [
            TestSupport.shift(id: "later-today", date: today, start: "14:00"),
            TestSupport.shift(id: "earlier-today", date: today, start: "08:00"),
            TestSupport.shift(id: "draft-today", date: today, start: "06:00", status: "draft"),
            TestSupport.shift(id: "future-4", date: "2026-09-16"),
            TestSupport.shift(id: "future-2", date: "2026-09-14"),
            TestSupport.shift(id: "future-1", date: "2026-09-13", start: "12:00"),
            TestSupport.shift(id: "future-1-early", date: "2026-09-13", start: "07:00"),
        ]

        let snapshot = HomeDashboardSnapshot(shifts: shifts, todayKey: today)

        XCTAssertEqual(snapshot.todayShifts.map(\.id), ["earlier-today", "later-today"])
        XCTAssertEqual(
            snapshot.upcomingShifts.map(\.id),
            ["future-1-early", "future-1", "future-2"]
        )
    }

    func testClockabilityKeepsActiveShiftAndBlocksCompetingShift() {
        XCTAssertTrue(
            HomeDashboardSnapshot.isClockable(
                shiftId: "active",
                activeClockShiftId: "active",
                hasTimesheet: true
            ),
            "The active clock session remains visible even if a timesheet arrives."
        )
        XCTAssertFalse(
            HomeDashboardSnapshot.isClockable(
                shiftId: "other",
                activeClockShiftId: "active",
                hasTimesheet: false
            ),
            "A second shift cannot start while another shift has an active session."
        )
        XCTAssertTrue(
            HomeDashboardSnapshot.isClockable(
                shiftId: "fresh",
                activeClockShiftId: nil,
                hasTimesheet: false
            )
        )
        XCTAssertFalse(
            HomeDashboardSnapshot.isClockable(
                shiftId: "submitted",
                activeClockShiftId: nil,
                hasTimesheet: true
            )
        )
    }

    func testMissedTimesheetsOnlyIncludesSubmittableMissingOrDraftRecords() {
        let now = TestSupport.instant("2026-09-12", "18:00")
        let newestMissing = TestSupport.shift(
            id: "newest-missing",
            date: "2026-09-12",
            start: "09:00",
            end: "12:00"
        )
        let olderDraft = TestSupport.shift(
            id: "older-draft",
            date: "2026-09-11",
            start: "09:00",
            end: "12:00"
        )
        let approved = TestSupport.shift(
            id: "approved",
            date: "2026-09-10",
            start: "09:00",
            end: "12:00"
        )
        let future = TestSupport.shift(
            id: "future",
            date: "2026-09-13",
            start: "09:00",
            end: "12:00"
        )
        let unpublished = TestSupport.shift(
            id: "unpublished",
            date: "2026-09-09",
            start: "09:00",
            end: "12:00",
            status: "draft"
        )
        let timesheets = [
            TestSupport.timesheet(id: "older-draft", shiftId: "older-draft", status: "draft"),
            TestSupport.timesheet(id: "approved", shiftId: "approved", status: "approved"),
        ]

        let result = HomeDashboardSnapshot.missedTimesheetShifts(
            shifts: [approved, future, olderDraft, unpublished, newestMissing],
            timesheets: timesheets,
            now: now
        )

        XCTAssertEqual(result.map(\.id), ["newest-missing", "older-draft"])
    }
}
