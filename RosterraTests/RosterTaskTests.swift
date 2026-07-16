import XCTest
@testable import Rosterra

final class RosterTaskTests: XCTestCase {

    private func makeTask(
        frequency: String = "daily",
        date: String? = nil,
        dayOfWeek: [Int]? = nil,
        active: Bool = true,
        assignedTo: [String]? = nil,
        requiresPhoto: Bool? = nil,
        endDate: String? = nil,
        priority: String? = nil
    ) -> RosterTask {
        RosterTask(
            id: "t1", title: "Test", description: nil, managerPhotoUrl: nil,
            frequency: frequency, date: date, dayOfWeek: dayOfWeek,
            active: active, createdAt: nil, createdBy: nil,
            assignedTo: assignedTo, dueTime: nil, priority: priority,
            requiresPhoto: requiresPhoto, endDate: endDate
        )
    }

    // MARK: - Scheduling

    func testOnceTaskActiveOnlyOnItsDate() {
        let task = makeTask(frequency: "once", date: "2026-07-06")
        XCTAssertTrue(task.isActive(onDayKey: "2026-07-06", weekday: 1))
        XCTAssertFalse(task.isActive(onDayKey: "2026-07-07", weekday: 2))
    }

    func testWeeklyTaskActiveOnSelectedWeekdays() {
        let task = makeTask(frequency: "weekly", dayOfWeek: [1, 3])
        XCTAssertTrue(task.isActive(onDayKey: "2026-07-06", weekday: 1))  // Mon
        XCTAssertFalse(task.isActive(onDayKey: "2026-07-07", weekday: 2)) // Tue
        XCTAssertTrue(task.isActive(onDayKey: "2026-07-08", weekday: 3))  // Wed
    }

    func testDailyTaskActiveEveryDay() {
        let task = makeTask(frequency: "daily")
        XCTAssertTrue(task.isActive(onDayKey: "2026-07-06", weekday: 1))
        XCTAssertTrue(task.isActive(onDayKey: "2026-07-12", weekday: 7))
    }

    func testInactiveTaskNeverActive() {
        let task = makeTask(frequency: "daily", active: false)
        XCTAssertFalse(task.isActive(onDayKey: "2026-07-06", weekday: 1))
    }

    func testEndDateStopsRecurringTask() {
        let task = makeTask(frequency: "daily", endDate: "2026-07-10")
        XCTAssertTrue(task.isActive(onDayKey: "2026-07-10", weekday: 5))
        XCTAssertFalse(task.isActive(onDayKey: "2026-07-11", weekday: 6))
    }

    // MARK: - Assignment

    func testNilOrEmptyAssignmentMeansEveryone() {
        XCTAssertTrue(makeTask().isAssigned(to: "anyone"))
        XCTAssertTrue(makeTask(assignedTo: []).isAssigned(to: "anyone"))
    }

    func testExplicitAssignmentFilters() {
        let task = makeTask(assignedTo: ["alice", "bob"])
        XCTAssertTrue(task.isAssigned(to: "alice"))
        XCTAssertFalse(task.isAssigned(to: "carol"))
        XCTAssertFalse(task.isAssigned(to: nil))
    }

    // MARK: - Assignment push recipients

    func testNotificationRecipientsExplicitAssignees() {
        let ids = RosterTask.notificationRecipientIds(
            assignedTo: ["alice", "bob", "alice", ""],
            allActiveStaffIds: ["alice", "bob", "carol"]
        )
        XCTAssertEqual(Set(ids), Set(["alice", "bob"]))
    }

    func testNotificationRecipientsAllStaffWhenUnassigned() {
        let ids = RosterTask.notificationRecipientIds(
            assignedTo: nil,
            allActiveStaffIds: ["alice", "bob"]
        )
        XCTAssertEqual(Set(ids), Set(["alice", "bob"]))
        let emptyMeansAll = RosterTask.notificationRecipientIds(
            assignedTo: [],
            allActiveStaffIds: ["carol"]
        )
        XCTAssertEqual(emptyMeansAll, ["carol"])
    }

    func testAssigneesChangedDetectsAllVsSpecific() {
        XCTAssertTrue(RosterTask.assigneesChanged(from: nil, to: ["alice"]))
        XCTAssertTrue(RosterTask.assigneesChanged(from: ["alice"], to: nil))
        XCTAssertTrue(RosterTask.assigneesChanged(from: ["alice"], to: ["bob"]))
        XCTAssertFalse(RosterTask.assigneesChanged(from: nil, to: []))
        XCTAssertFalse(RosterTask.assigneesChanged(from: ["alice", "bob"], to: ["bob", "alice"]))
    }

    // MARK: - Defaults on legacy documents

    func testLegacyDocDefaults() {
        let task = makeTask()
        XCTAssertTrue(task.photoRequired) // nil requiresPhoto = photo required
        XCTAssertEqual(task.priorityLevel, .normal)
    }

    func testPrioritySortWeight() {
        XCTAssertLessThan(TaskPriority.high.weight, TaskPriority.normal.weight)
        XCTAssertLessThan(TaskPriority.normal.weight, TaskPriority.low.weight)
    }

    // MARK: - Image compression budget

    func testCompressedImageFitsTwoMegabytes() throws {
        // A large noisy image (noise compresses poorly — worst case for JPEG).
        let size = CGSize(width: 4000, height: 3000)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            for _ in 0..<2000 {
                UIColor(hue: .random(in: 0...1), saturation: 1, brightness: 1, alpha: 1).setFill()
                ctx.fill(CGRect(x: .random(in: 0..<size.width), y: .random(in: 0..<size.height),
                                width: 60, height: 60))
            }
        }
        let data = try XCTUnwrap(ImageCompressor.jpegData(from: image))
        XCTAssertLessThanOrEqual(data.count, ImageCompressor.maxBytes)
    }
}
