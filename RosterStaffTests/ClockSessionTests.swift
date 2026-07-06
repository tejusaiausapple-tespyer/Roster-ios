import XCTest
@testable import RosterStaff

/// Clock in/out session math: break accumulation, worked time, and the
/// rounding/clamping that feeds the timesheet break stepper.
final class ClockSessionTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func session() -> ClockSession {
        ClockSession(shiftId: "s1", staffId: "u1", clockInAt: t0)
    }

    func testNoBreakSubmitsZeroBreak() {
        var s = session()
        s.clockOut(at: t0.addingTimeInterval(4 * 3600))
        XCTAssertEqual(s.timesheetBreakMinutes(), 0)
        XCTAssertEqual(s.workedSeconds(), 4 * 3600, accuracy: 0.5)
        XCTAssertFalse(s.isActive)
    }

    func testBreakDeductedFromWorkedTime() {
        var s = session()
        s.startBreak(at: t0.addingTimeInterval(3600))
        s.endBreak(at: t0.addingTimeInterval(3600 + 30 * 60))
        s.clockOut(at: t0.addingTimeInterval(8 * 3600))
        XCTAssertEqual(s.timesheetBreakMinutes(), 30)
        XCTAssertEqual(s.workedSeconds(), 7.5 * 3600, accuracy: 0.5)
    }

    // MARK: - Early check-in / paid time

    func testEarlyCheckInNotPaid() {
        // Clock in 5 minutes before the rostered start; paid time begins at
        // the rostered start.
        var s = session()
        let rosterStart = t0.addingTimeInterval(5 * 60)
        s.clockOut(at: rosterStart.addingTimeInterval(4 * 3600))
        XCTAssertEqual(s.paidWorkedSeconds(rosterStart: rosterStart), 4 * 3600, accuracy: 0.5)
        XCTAssertEqual(s.paidStart(rosterStart: rosterStart), rosterStart)
        // The raw session still records the true 4h05m on-clock time.
        XCTAssertEqual(s.workedSeconds(), 4 * 3600 + 5 * 60, accuracy: 0.5)
    }

    func testLateCheckInPaidFromClockIn() {
        var s = session()
        let rosterStart = t0.addingTimeInterval(-30 * 60) // clocked in 30m late
        s.clockOut(at: t0.addingTimeInterval(2 * 3600))
        XCTAssertEqual(s.paidWorkedSeconds(rosterStart: rosterStart), 2 * 3600, accuracy: 0.5)
        XCTAssertEqual(s.paidStart(rosterStart: rosterStart), t0)
    }

    func testBreakDuringEarlyWindowNotDoubleDeducted() {
        // A break spanning the unpaid early window only deducts its paid part.
        var s = session()
        let rosterStart = t0.addingTimeInterval(10 * 60)
        s.startBreak(at: t0.addingTimeInterval(5 * 60))       // starts before roster start
        s.endBreak(at: rosterStart.addingTimeInterval(10 * 60)) // ends 10m into paid time
        s.clockOut(at: rosterStart.addingTimeInterval(3600))
        // Paid window is 1h; only 10m of the break overlaps it.
        XCTAssertEqual(s.paidWorkedSeconds(rosterStart: rosterStart), 50 * 60, accuracy: 0.5)
    }

    func testMultipleBreaksAccumulate() {
        var s = session()
        s.startBreak(at: t0.addingTimeInterval(3600))
        s.endBreak(at: t0.addingTimeInterval(3600 + 600))       // 10m
        s.startBreak(at: t0.addingTimeInterval(3 * 3600))
        s.endBreak(at: t0.addingTimeInterval(3 * 3600 + 900))   // 15m
        XCTAssertEqual(s.totalBreakSeconds(at: t0.addingTimeInterval(4 * 3600)), 1500, accuracy: 0.5)
        XCTAssertEqual(s.timesheetBreakMinutes(at: t0.addingTimeInterval(4 * 3600)), 25)
    }

    func testBreakMinutesRoundToStepAndClamp() {
        var s = session()
        s.startBreak(at: t0)
        s.endBreak(at: t0.addingTimeInterval(23 * 60)) // 23m → nearest 5 = 25
        XCTAssertEqual(s.timesheetBreakMinutes(), 25)

        var long = session()
        long.startBreak(at: t0)
        long.endBreak(at: t0.addingTimeInterval(2 * 3600)) // 120m → clamp 90
        XCTAssertEqual(long.timesheetBreakMinutes(), 90)
    }

    func testClockOutEndsOpenBreak() {
        var s = session()
        s.startBreak(at: t0.addingTimeInterval(3600))
        XCTAssertTrue(s.isOnBreak)
        s.clockOut(at: t0.addingTimeInterval(3600 + 300))
        XCTAssertFalse(s.isOnBreak)
        XCTAssertEqual(s.totalBreakSeconds(), 300, accuracy: 0.5)
    }

    func testStartBreakIgnoredWhileOnBreakOrAfterClockOut() {
        var s = session()
        s.startBreak(at: t0.addingTimeInterval(60))
        s.startBreak(at: t0.addingTimeInterval(120)) // ignored — already on break
        XCTAssertEqual(s.breaks.count, 1)
        s.clockOut(at: t0.addingTimeInterval(3600))
        s.startBreak(at: t0.addingTimeInterval(3700)) // ignored — clocked out
        XCTAssertEqual(s.breaks.count, 1)
    }

    func testCodableRoundTrip() throws {
        var s = session()
        s.startBreak(at: t0.addingTimeInterval(3600))
        s.endBreak(at: t0.addingTimeInterval(3900))
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(ClockSession.self, from: data)
        XCTAssertEqual(decoded, s)
    }
}
