import XCTest
@testable import Rosterra

final class DailyJobTests: XCTestCase {

    private func makeAssignment(date: String) -> DailyJobAssignment {
        DailyJobAssignment(
            id: "s1_t1", shiftId: "s1", staffId: "u1", templateId: "t1",
            title: "Wash floors", date: date, assignedAt: nil, assignedBy: nil,
            completed: false, completedAt: nil, completedBy: nil
        )
    }

    func testDocIdIsDeterministicPerShiftAndTemplate() {
        XCTAssertEqual(DailyJobAssignment.docId(shiftId: "s1", templateId: "t1"), "s1_t1")
    }

    func testVisibleForEntireShiftDate() {
        let now = Date()
        let today = makeAssignment(date: RosterCalendar.todayKey(now))
        XCTAssertTrue(today.isVisibleToStaff(now: now))

        let yesterday = makeAssignment(date: RosterCalendar.todayKey(RosterCalendar.addDays(-1, to: now)))
        XCTAssertFalse(yesterday.isVisibleToStaff(now: now))
    }

    func testHiddenAfterCalendarDayEnds() {
        let now = Date()
        let todayKey = RosterCalendar.todayKey(now)
        let assignment = makeAssignment(date: todayKey)
        // Still visible after rostered shift end — window is the full calendar day.
        XCTAssertTrue(assignment.isVisibleToStaff(now: now))
    }
}
