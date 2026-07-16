import XCTest
@testable import Rosterra

final class ShiftReminderSchedulerTests: XCTestCase {
    func testHoursFiledStatuses() {
        XCTAssertTrue(ShiftReminderScheduler.isHoursFiled(.pending))
        XCTAssertTrue(ShiftReminderScheduler.isHoursFiled(.approved))
        XCTAssertTrue(ShiftReminderScheduler.isHoursFiled(.absentReported))
        XCTAssertTrue(ShiftReminderScheduler.isHoursFiled(.absent))
        XCTAssertFalse(ShiftReminderScheduler.isHoursFiled(.draft))
        XCTAssertFalse(ShiftReminderScheduler.isHoursFiled(.rejected))
        XCTAssertFalse(ShiftReminderScheduler.isHoursFiled(nil))
    }

    @MainActor
    func testNotificationTapRoutesSubmitSlotToRoster() {
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo([
            "shiftId": "shift-1",
            "kind": "shift-reminder",
            "slot": "submit-hours",
        ])
        XCTAssertEqual(router.pendingSubmitShiftId, "shift-1")
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.roster.rawValue)
    }

    @MainActor
    func testNotificationTapRoutesStartReminderToHome() {
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo([
            "shiftId": "shift-2",
            "kind": "shift-reminder",
            "slot": "30m",
        ])
        XCTAssertNil(router.pendingSubmitShiftId)
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.home.rawValue)
    }

    @MainActor
    func testNotificationTapUsesIdentifierSuffixWhenSlotMissing() {
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo([
            "shiftId": "shift-3",
            "kind": "shift-reminder",
            "identifier": "shift-reminder.shift-3.forgot-end",
        ])
        XCTAssertEqual(router.pendingSubmitShiftId, "shift-3")
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.roster.rawValue)
    }

    @MainActor
    func testTimesheetRejectedPushOpensSubmit() {
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo([
            "event": "timesheet-rejected",
            "timesheetId": "shift-9",
            "url": "/staff/roster",
        ])
        XCTAssertEqual(router.pendingSubmitShiftId, "shift-9")
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.roster.rawValue)
    }

    @MainActor
    func testTimesheetApprovedPushOpensRoster() {
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo([
            "event": "timesheet-approved",
            "timesheetId": "shift-8",
            "url": "/staff/roster",
        ])
        XCTAssertNil(router.pendingSubmitShiftId)
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.roster.rawValue)
    }

    @MainActor
    func testRosterPublishedPushOpensRoster() {
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo([
            "event": "roster-published",
            "url": "/staff/roster",
        ])
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.roster.rawValue)
    }
}
