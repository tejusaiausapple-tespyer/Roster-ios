import XCTest
import FirebaseFirestore
@testable import RosterStaff

/// FS coercion helpers and model `init?(id:data:)` parsing — the tolerant
/// boundary between loosely-typed Firestore documents and the typed domain.
final class ModelParsingTests: XCTestCase {

    // MARK: - FS coercions

    func testStringHelpers() {
        let d: [String: Any] = ["a": "x", "b": 5]
        XCTAssertEqual(FS.string(d, "a"), "x")
        XCTAssertNil(FS.string(d, "b"), "numbers are not coerced to strings")
        XCTAssertEqual(FS.stringValue(d, "missing", default: "z"), "z")
    }

    func testBoolCoercion() {
        let d: [String: Any] = ["t": true, "n": NSNumber(value: 1)]
        XCTAssertTrue(FS.bool(d, "t"))
        XCTAssertTrue(FS.bool(d, "n"))
        XCTAssertFalse(FS.bool(d, "missing"))
    }

    func testNumericCoercion() {
        let d: [String: Any] = ["i": 7, "d": 7.9, "n": NSNumber(value: 3.5)]
        XCTAssertEqual(FS.int(d, "i"), 7)
        XCTAssertEqual(FS.int(d, "n"), 3)
        XCTAssertEqual(FS.double(d, "i"), 7.0)
        XCTAssertEqual(FS.double(d, "n"), 3.5)
        XCTAssertEqual(FS.double(d, "missing", default: -1), -1)
    }

    func testDateCoercionFromAllRepresentations() {
        let ref = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(FS.date(any: Timestamp(date: ref)), ref)
        XCTAssertEqual(FS.date(any: ref), ref)
        // ISO string with fractional seconds
        XCTAssertNotNil(FS.date(any: "2026-06-01T02:30:00.000Z"))
        // ISO string without fractional seconds (fallback formatter)
        XCTAssertNotNil(FS.date(any: "2026-06-01T02:30:00Z"))
        XCTAssertNil(FS.date(any: "not a date"))
        XCTAssertNil(FS.date(any: nil))
    }

    func testIsoStringFromTimestamp() {
        let d: [String: Any] = ["ts": Timestamp(date: Date(timeIntervalSince1970: 0))]
        XCTAssertEqual(FS.isoString(d, "ts"), "1970-01-01T00:00:00.000Z")
    }

    // MARK: - AppUser

    func testUserDefaults() {
        let user = AppUser(id: "u1", data: ["fullName": "Ada Lovelace", "email": "ada@x.com"])!
        XCTAssertEqual(user.role, .staff, "role defaults to staff")
        XCTAssertEqual(user.status, .active, "status defaults to active")
        XCTAssertEqual(user.firstName, "Ada")
        XCTAssertEqual(user.initials, "AL")
        XCTAssertFalse(user.mustChangePassword)
    }

    func testStaffProfileCompletionGate() {
        let incomplete = TestSupport.user()
        XCTAssertTrue(incomplete.needsProfileCompletion, "staff missing dob/address/phone")

        let complete = TestSupport.user(extra: [
            "dob": "1990-01-01", "address": "1 Test St", "phone": "0400000000",
        ])
        XCTAssertFalse(complete.needsProfileCompletion)

        let forced = TestSupport.user(extra: [
            "dob": "1990-01-01", "address": "1 Test St", "phone": "0400000000",
            "profileUpdateRequired": true,
        ])
        XCTAssertTrue(forced.needsProfileCompletion, "manager-forced update overrides completeness")

        let manager = TestSupport.user(role: "manager")
        XCTAssertFalse(manager.needsProfileCompletion, "gate is staff-only")
    }

    func testUserWeeklyAvailabilityParsing() {
        let user = TestSupport.user(extra: [
            "weeklyAvailability": [
                "2026-06-01": [
                    "monday": ["available": false, "allDay": false],
                ],
            ],
        ])
        let week = user.weeklyAvailability["2026-06-01"]
        XCTAssertNotNil(week)
        XCTAssertEqual(week?[.monday].available, false)
        XCTAssertEqual(week?[.tuesday].available, true, "unspecified days fall back to default")
    }

    // MARK: - Shift / Timesheet

    func testShiftStatusDefaultsToDraft() {
        let shift = Shift(id: "s", data: ["staffId": "u", "date": "2026-06-01",
                                          "rosteredStart": "09:00", "rosteredEnd": "17:00"])!
        XCTAssertEqual(shift.status, .draft)
    }

    func testTimesheetEditability() {
        XCTAssertTrue(TestSupport.timesheet(status: "pending").isStaffEditable)
        XCTAssertTrue(TestSupport.timesheet(status: "rejected").isStaffEditable)
        XCTAssertTrue(TestSupport.timesheet(status: "absent_reported").isStaffEditable)
        XCTAssertFalse(TestSupport.timesheet(status: "approved").isStaffEditable)
        XCTAssertFalse(TestSupport.timesheet(status: "absent").isStaffEditable)
    }

    func testTimesheetAbsenceFlag() {
        XCTAssertTrue(TestSupport.timesheet(status: "absent_reported").isStaffReportedAbsence)
        XCTAssertFalse(TestSupport.timesheet(status: "absent").isStaffReportedAbsence)
    }

    // MARK: - Message

    func testMessageActiveByExpiry() {
        let now = Date()
        let active = Message(id: "m1", data: [
            "recipientId": "u", "body": "hi",
            "expiresAt": FS.isoFormatter.string(from: now.addingTimeInterval(3600)),
        ])!
        let expired = Message(id: "m2", data: [
            "recipientId": "u", "body": "old",
            "expiresAt": FS.isoFormatter.string(from: now.addingTimeInterval(-3600)),
        ])!
        let noExpiry = Message(id: "m3", data: ["recipientId": "u", "body": "keep"])!
        XCTAssertTrue(active.isActive(at: now))
        XCTAssertFalse(expired.isActive(at: now))
        XCTAssertTrue(noExpiry.isActive(at: now), "missing expiry means always active")
    }

    func testMessageBodyLines() {
        let message = Message(id: "m", data: [
            "recipientId": "u",
            "body": "First line\nSecond \u{2022} Third",
        ])!
        XCTAssertEqual(message.bodyLines, ["First line", "Second", "Third"])
    }

    // MARK: - AppSettings (company details)

    func testAppSettingsParsingAndRoundTrip() {
        let settings = AppSettings(data: [
            "companyName": "Sura Investments Pty Ltd",
            "businessAddress": "1 Example St, Adelaide SA",
            "abn": "12345678901",
        ])
        XCTAssertEqual(settings.companyName, "Sura Investments Pty Ltd")
        XCTAssertEqual(settings.abn, "12345678901")
        XCTAssertEqual(settings.contactPhone, "", "missing fields default empty")

        let restored = AppSettings(data: settings.asDictionary)
        XCTAssertEqual(restored, settings)
    }

    func testAppSettingsFallbackName() {
        XCTAssertEqual(AppSettings(data: [:]).companyName, "Sura Roster")
    }

    // MARK: - RosterLocation

    func testLocationCapitalMapping() {
        XCTAssertEqual(RosterLocation.capital(for: "SA"), "Adelaide")
        XCTAssertEqual(RosterLocation.capital(for: "NSW"), "Sydney")
        XCTAssertEqual(RosterLocation.capital(for: "ACT"), "Canberra")
        XCTAssertEqual(RosterLocation.capital(for: "??"), "")
        XCTAssertEqual(RosterLocation.states.count, 8)
    }

    func testLocationAutoCityAndRoundTrip() {
        let loc = RosterLocation(suburb: "Norwood", state: "SA")
        XCTAssertEqual(loc.city, "Adelaide", "capital auto-derived from state")
        XCTAssertEqual(loc.displayName, "Norwood, SA")

        let restored = RosterLocation(dict: loc.asDictionary)
        XCTAssertEqual(restored, loc)

        let custom = RosterLocation(suburb: "Whyalla", state: "SA", city: "Whyalla")
        XCTAssertEqual(custom.city, "Whyalla", "explicit city overrides the capital")
    }

    func testLocationParsingRejectsIncomplete() {
        XCTAssertNil(RosterLocation(dict: ["suburb": "Norwood"]))
        XCTAssertNil(RosterLocation(dict: ["state": "SA"]))
    }

    // MARK: - Availability round-trip

    func testDayAvailabilityDictionaryRoundTrip() {
        let day = DayAvailability(available: true, allDay: false, start: "10:00", end: "14:00")
        let restored = DayAvailability(dict: day.asDictionary)
        XCTAssertEqual(restored, day)
    }

    func testUserAvailabilityDefaultsAndRoundTrip() {
        let avail = UserAvailability.defaultAvailability
        XCTAssertEqual(avail.days.count, 7)
        XCTAssertEqual(avail[.sunday], .defaultDay)

        let restored = UserAvailability(dict: avail.asDictionary)
        XCTAssertEqual(restored, avail)
    }
}
