import XCTest
@testable import Rosterra

final class ShiftReminderSchedulerTests: XCTestCase {
    @MainActor
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
    func testLiveActivityStartLinkRoutesToHomeClockAction() {
        let router = AppRouter()
        router.selectedTab = AppRouter.Tab.account.rawValue

        router.handle(url: URL(
            string: "surafoster://staff/home?shiftId=shift-live&shiftAction=start"
        )!)

        XCTAssertEqual(
            router.pendingClockAction,
            AppRouter.PendingClockAction(shiftId: "shift-live", kind: .start)
        )
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.home.rawValue)
    }

    @MainActor
    func testLiveActivitySelectsShiftOnlyInsideClockWindow() {
        let now = TestSupport.instant("2026-09-12", "12:00")
        let ready = TestSupport.shift(
            id: "ready",
            staffId: "staff-1",
            date: "2026-09-12",
            start: "12:03",
            end: "18:00"
        )
        let tooEarly = TestSupport.shift(
            id: "too-early",
            staffId: "staff-1",
            date: "2026-09-12",
            start: "13:00",
            end: "18:00"
        )

        XCTAssertEqual(
            ShiftLiveActivityManager.activeShift(
                staffID: "staff-1",
                shifts: [tooEarly, ready],
                timesheets: [],
                clockSession: nil,
                now: now
            )?.id,
            "ready"
        )

        XCTAssertNil(
            ShiftLiveActivityManager.activeShift(
                staffID: "staff-1",
                shifts: [tooEarly],
                timesheets: [],
                clockSession: nil,
                now: now
            )
        )
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

    @MainActor
    func testPayslipGeneratedOpensPayslipsNotRoster() {
        // The registry still uses the legacy `/staff/history` URL, so the
        // event must take precedence and open the dedicated Payslips tab.
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo([
            "event": "payslip-generated",
            "url": "/staff/history",
        ])
        XCTAssertEqual(router.selectedTab, AppRouter.Tab.payslips.rawValue)
    }

    // MARK: - Manager notification routing (5.2)

    @MainActor
    private func assertManagerEvent(_ event: String, opens tab: ManagerTab, file: StaticString = #filePath, line: UInt = #line) {
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo(["event": event])
        XCTAssertEqual(router.selectedManagerTab, tab, "event \(event)", file: file, line: line)
    }

    @MainActor
    func testManagerTimesheetSubmittedOpensTimesheets() {
        assertManagerEvent("timesheet-submitted", opens: .timesheets)
    }

    @MainActor
    func testManagerTimesheetAbsentOpensTimesheets() {
        assertManagerEvent("timesheet-absent", opens: .timesheets)
    }

    @MainActor
    func testManagerShiftStartedOpensDashboard() {
        assertManagerEvent("shift-started", opens: .dashboard)
    }

    @MainActor
    func testManagerShiftEndedOpensDashboard() {
        assertManagerEvent("shift-ended", opens: .dashboard)
    }

    @MainActor
    func testManagerShiftRunningLateOpensDashboard() {
        assertManagerEvent("shift-running-late", opens: .dashboard)
    }

    @MainActor
    func testManagerShiftOvertimeStartedOpensDashboard() {
        assertManagerEvent("shift-overtime-started", opens: .dashboard)
    }

    @MainActor
    func testManagerTaskCompletedOpensTasks() {
        assertManagerEvent("task-completed", opens: .tasks)
    }

    @MainActor
    func testManagerJobsAllCompletedOpensDashboard() {
        assertManagerEvent("jobs-all-completed", opens: .dashboard)
    }

    @MainActor
    func testManagerAvailabilityUpdatedOpensAccountOnPhone() {
        // .availability isn't one of the 5 tabs ManagerMainView tags on the
        // iPhone TabView (only reachable there via Account -> Management),
        // so selectManager fails closed to .account rather than selecting a
        // tag the TabView doesn't recognize (a silent no-op otherwise).
        // Unit tests run under the iPhone simulator idiom, so this is the
        // behavior exercised here; iPad/Mac's sidebar tags every tab and
        // would route straight to .availability.
        assertManagerEvent("availability-updated", opens: .account)
    }

    @MainActor
    func testUnrecognizedEventDoesNotTouchManagerTab() {
        // A staff-facing event (or any device that isn't a manager) must not
        // perturb selectedManagerTab, since ManagerMainView is the only
        // observer and staff devices never render it.
        let router = AppRouter()
        AppRouter.shared = router
        router.handleNotificationUserInfo(["event": "timesheet-approved"])
        XCTAssertEqual(router.selectedManagerTab, .dashboard)
    }
}
