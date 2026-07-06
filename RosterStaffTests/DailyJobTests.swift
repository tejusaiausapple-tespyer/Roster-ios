import XCTest
@testable import RosterStaff

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

    func testVisibleUntilShiftEnds() {
        let assignment = makeAssignment(date: "2026-07-06")
        let now = Date()
        XCTAssertTrue(assignment.isVisibleToStaff(shiftEnd: now.addingTimeInterval(3600), now: now))
        XCTAssertFalse(assignment.isVisibleToStaff(shiftEnd: now.addingTimeInterval(-60), now: now))
    }

    func testFallsBackToTodayWhenShiftUnknown() {
        let now = Date()
        let today = makeAssignment(date: RosterCalendar.todayKey(now))
        let yesterday = makeAssignment(date: RosterCalendar.todayKey(RosterCalendar.addDays(-1, to: now)))
        XCTAssertTrue(today.isVisibleToStaff(shiftEnd: nil, now: now))
        XCTAssertFalse(yesterday.isVisibleToStaff(shiftEnd: nil, now: now))
    }
}
