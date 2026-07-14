import XCTest
@testable import RosterStaff

/// RosterCalendar (Adelaide-pinned date math) and RosterFormat (display).
final class CalendarFormatTests: XCTestCase {

    // MARK: - RosterCalendar

    func testTimeZoneIsAdelaide() {
        XCTAssertEqual(RosterCalendar.timeZone.identifier, "Australia/Adelaide")
    }

    func testWeekStartIsMonday() {
        let wednesday = TestSupport.instant("2026-06-03", "12:00")
        let monday = RosterCalendar.weekStart(wednesday)
        XCTAssertEqual(RosterCalendar.dayFormatter.string(from: monday), "2026-06-01")
        XCTAssertEqual(RosterCalendar.calendar.component(.weekday, from: monday), 2, "weekday 2 == Monday")
    }

    func testWeekStartOnAMondayIsItself() {
        let monday = TestSupport.instant("2026-06-01", "00:00")
        XCTAssertEqual(RosterCalendar.weekStartKey(monday), "2026-06-01")
    }

    func testWeekStartOnASundayStaysInSameISOWeek() {
        let sunday = TestSupport.instant("2026-06-07", "23:00")
        XCTAssertEqual(RosterCalendar.weekStartKey(sunday), "2026-06-01")
    }

    func testWeekDaysAreSevenConsecutive() {
        let days = RosterCalendar.weekDays(for: TestSupport.instant("2026-06-03", "12:00"))
        XCTAssertEqual(days.count, 7)
        let keys = days.map { RosterCalendar.dayFormatter.string(from: $0) }
        XCTAssertEqual(keys.first, "2026-06-01")
        XCTAssertEqual(keys.last, "2026-06-07")
    }

    func testDayKeyRoundTrip() {
        let date = RosterCalendar.dateFromKey("2026-12-25")
        XCTAssertNotNil(date)
        XCTAssertEqual(RosterCalendar.dayFormatter.string(from: date!), "2026-12-25")
    }

    func testAddDaysAcrossDSTBoundary() {
        // DST ends 2026-04-05 in Adelaide; adding days must stay wall-clock stable.
        let before = TestSupport.instant("2026-04-04", "12:00")
        let after = RosterCalendar.addDays(2, to: before)
        XCTAssertEqual(RosterCalendar.dayFormatter.string(from: after), "2026-04-06")
        XCTAssertEqual(RosterCalendar.calendar.component(.hour, from: after), 12)
    }

    // MARK: - RosterFormat

    func testTimeFormatting() {
        XCTAssertEqual(RosterFormat.time("09:05"), "9:05 AM")
        XCTAssertEqual(RosterFormat.time("12:00"), "12:00 PM")
        XCTAssertEqual(RosterFormat.time("00:30"), "12:30 AM")
        XCTAssertEqual(RosterFormat.time("17:45"), "5:45 PM")
        XCTAssertEqual(RosterFormat.time("bad"), "bad", "unparseable input passes through")
    }

    func testDateFormatting() {
        XCTAssertEqual(RosterFormat.date("2026-06-02"), "Tue, 2 Jun 2026")
        XCTAssertEqual(RosterFormat.dateShort("2026-06-02"), "2 Jun")
        XCTAssertEqual(RosterFormat.weekdayLong("2026-06-02"), "Tuesday")
    }

    func testHoursFormatting() {
        XCTAssertEqual(RosterFormat.hours(8), "8h")
        XCTAssertEqual(RosterFormat.hours(7.5), "7h 30m")
        XCTAssertEqual(RosterFormat.hours(0.25), "0h 15m")
        XCTAssertEqual(RosterFormat.decimalHours(8), "8")
        XCTAssertEqual(RosterFormat.decimalHours(7.5), "7.5")
    }

    func testWeekRangeSameMonth() {
        let monday = TestSupport.instant("2026-05-04", "00:00")
        XCTAssertEqual(RosterFormat.weekRange(monday: monday), "4 – 10 May")
    }

    // MARK: - Business identifier formatting (as-you-type)

    func testABNFormatting() {
        XCTAssertEqual(RosterFormat.abn("12345678901"), "12 345 678 901")
        XCTAssertEqual(RosterFormat.abn("123"), "12 3", "partial input formats progressively")
        XCTAssertEqual(RosterFormat.abn("12 345 678 901 999"), "12 345 678 901", "capped at 11 digits")
        XCTAssertEqual(RosterFormat.abn("ab12cd345"), "12 345", "non-digits stripped")
        XCTAssertEqual(RosterFormat.abn(""), "")
    }

    func testACNFormatting() {
        XCTAssertEqual(RosterFormat.acn("123456789"), "123 456 789")
        XCTAssertEqual(RosterFormat.acn("1234"), "123 4")
        XCTAssertEqual(RosterFormat.acn("1234567890"), "123 456 789", "capped at 9 digits")
    }

    func testAUPhoneLocalFormatting() {
        XCTAssertEqual(RosterFormat.auPhoneLocal("412345678"), "412 345 678")
        XCTAssertEqual(RosterFormat.auPhoneLocal("0412345678"), "412 345 678", "leading 0 dropped")
        XCTAssertEqual(RosterFormat.auPhoneLocal("41"), "41")
        XCTAssertEqual(RosterFormat.auPhoneLocal(""), "")
    }

    func testComposedAddress() {
        XCTAssertEqual(AppSettings.composedAddress(street: "1 Example St", suburb: "Norwood", state: "SA"),
                       "1 Example St, Norwood SA")
        XCTAssertEqual(AppSettings.composedAddress(street: "", suburb: "Norwood", state: "SA"),
                       "Norwood SA")
        XCTAssertEqual(AppSettings.composedAddress(street: "1 Example St", suburb: "", state: ""),
                       "1 Example St")
    }

    func testWeekRangeCrossMonth() {
        let monday = TestSupport.instant("2026-04-27", "00:00")
        XCTAssertEqual(RosterFormat.weekRange(monday: monday), "27 Apr – 3 May")
    }

    // The Date-based formatters must render in the business timezone
    // (Australia/Adelaide), never the device's — M7 fix.
    func testDateFormattersUseBusinessTimezone() {
        let instant = TestSupport.instant("2026-07-06", "14:05")
        XCTAssertEqual(RosterFormat.hhmm(instant), "14:05")
        XCTAssertEqual(RosterFormat.time(instant), "2:05 PM")
        XCTAssertEqual(RosterFormat.dateFull(instant), "Monday, 6 July 2026")
        XCTAssertEqual(RosterFormat.dateTime(instant), "6 Jul 2026, 2:05 PM")
    }

    // MARK: - Month keys (payslip month filter)

    func testMonthKeyFromDateAndComponents() {
        let instant = TestSupport.instant("2026-07-06", "14:05")
        XCTAssertEqual(RosterCalendar.monthKey(instant), "2026-07")
        XCTAssertEqual(RosterCalendar.monthKey(year: 2026, month: 1), "2026-01")
        XCTAssertEqual(RosterCalendar.monthKeyComponents("2026-07")?.year, 2026)
        XCTAssertEqual(RosterCalendar.monthKeyComponents("2026-07")?.month, 7)
        XCTAssertNil(RosterCalendar.monthKeyComponents("garbage"))
        XCTAssertNil(RosterCalendar.monthKeyComponents("2026-13"))
    }

    func testMonthDayKeyBoundsIncludingYearRollover() {
        let july = RosterCalendar.monthDayKeyBounds("2026-07")
        XCTAssertEqual(july?.start, "2026-07-01")
        XCTAssertEqual(july?.end, "2026-08-01")
        let december = RosterCalendar.monthDayKeyBounds("2026-12")
        XCTAssertEqual(december?.end, "2027-01-01")
        XCTAssertNil(RosterCalendar.monthDayKeyBounds("nope"))
    }

    func testMonthBoundsContainPayslipDocIdsLexicographically() {
        // Payslip doc ids are "{periodStart}_{staffId}" — a month is an id range.
        let bounds = RosterCalendar.monthDayKeyBounds("2026-07")!
        XCTAssertTrue("2026-07-06_abc123" >= bounds.start && "2026-07-06_abc123" < bounds.end)
        XCTAssertTrue("2026-07-27_abc123_c2" < bounds.end)
        XCTAssertFalse("2026-06-29_abc123" >= bounds.start)
        XCTAssertFalse("2026-08-03_abc123" < bounds.end)
    }

    func testMonthKeyStepping() {
        XCTAssertEqual(RosterCalendar.monthKey(byAdding: 1, to: "2026-12"), "2027-01")
        XCTAssertEqual(RosterCalendar.monthKey(byAdding: -1, to: "2026-01"), "2025-12")
        XCTAssertEqual(RosterCalendar.monthKey(byAdding: 0, to: "2026-07"), "2026-07")
        XCTAssertNil(RosterCalendar.monthKey(byAdding: 1, to: "bad"))
    }
}
