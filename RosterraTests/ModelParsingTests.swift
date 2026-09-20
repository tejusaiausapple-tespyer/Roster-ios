import XCTest
import FirebaseFirestore
@testable import Rosterra

#if targetEnvironment(macCatalyst)
final class MacRosterCopyPlanTests: XCTestCase {
    func testPublishedCardsStayLockedAcrossWeeks() {
        for date in ["2026-08-31", "2026-09-07", "2026-09-14"] {
            XCTAssertFalse(MacRosterCopyPlan.canDrag(TestSupport.shift(date: date)))
            XCTAssertTrue(MacRosterCopyPlan.canDrag(TestSupport.shift(date: date, status: "draft")))
        }
        for status in ["completed", "cancelled"] {
            XCTAssertFalse(MacRosterCopyPlan.canDrag(TestSupport.shift(date: "2026-09-14", status: status)))
        }
    }

    func testCopySelectedStaffCreatesDraftsAndKeepsSourceUnchanged() {
        let first = TestSupport.shift(id: "a", staffId: "one", date: "2026-09-07")
        let second = TestSupport.shift(id: "b", staffId: "two", date: "2026-09-07")
        let plan = MacRosterCopyPlan(source: [first, second], existing: [], staffIDs: ["two"])
        XCTAssertEqual(plan.drafts.count, 1)
        XCTAssertEqual(plan.drafts.first?.staffId, "two")
        XCTAssertEqual(plan.drafts.first?.date, "2026-09-14")
        XCTAssertEqual(plan.drafts.first?.status, .draft)
        XCTAssertEqual(second.status, .published)
        XCTAssertEqual(second.date, "2026-09-07")
        XCTAssertTrue(MacRosterCopyPlan(source: [first], existing: [], staffIDs: []).drafts.isEmpty)
    }

    func testCopySkipsDuplicatesConflictsAndCancelledSources() {
        let source = TestSupport.shift(id: "a", date: "2026-09-07")
        let cancelled = TestSupport.shift(id: "b", date: "2026-09-08", status: "cancelled")
        let conflict = TestSupport.shift(id: "existing", date: "2026-09-14", start: "16:00", end: "19:00")
        let plan = MacRosterCopyPlan(source: [source, cancelled], existing: [conflict], staffIDs: nil)
        XCTAssertTrue(plan.drafts.isEmpty)
        XCTAssertEqual(plan.skipped, 1)
        let firstCopy = MacRosterCopyPlan(source: [source], existing: [], staffIDs: nil)
        let retry = MacRosterCopyPlan(source: [source], existing: firstCopy.drafts, staffIDs: nil)
        XCTAssertTrue(retry.drafts.isEmpty)
        XCTAssertEqual(retry.skipped, 1)
    }

    func testCopyDetectsOvernightOverlapButAllowsAdjacentShifts() {
        let source = TestSupport.shift(date: "2026-09-07", start: "00:30", end: "06:00")
        let overnight = TestSupport.shift(id: "overnight", date: "2026-09-13", start: "22:00", end: "01:00")
        XCTAssertTrue(MacRosterCopyPlan(source: [source], existing: [overnight], staffIDs: nil).drafts.isEmpty)
        let adjacent = TestSupport.shift(id: "adjacent", date: "2026-09-14", start: "06:00", end: "09:00")
        XCTAssertEqual(MacRosterCopyPlan(source: [source], existing: [adjacent], staffIDs: nil).drafts.count, 1)
    }
}
#endif

/// FS coercion helpers and model `init?(id:data:)` parsing — the tolerant
/// boundary between loosely-typed Firestore documents and the typed domain.
final class ModelParsingTests: XCTestCase {

    func testManagerCanCorrectPendingAndApprovedTimesheets() {
        XCTAssertTrue(TestSupport.timesheet(status: "pending").isManagerTimeEditable)
        XCTAssertTrue(TestSupport.timesheet(status: "approved").isManagerTimeEditable)
        XCTAssertFalse(TestSupport.timesheet(status: "draft").isManagerTimeEditable)
        XCTAssertFalse(TestSupport.timesheet(status: "rejected").isManagerTimeEditable)
        XCTAssertFalse(TestSupport.timesheet(status: "absent_reported").isManagerTimeEditable)
        XCTAssertFalse(TestSupport.timesheet(status: "absent").isManagerTimeEditable)
    }

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

    func testEmployeeIdParsing() {
        let user = AppUser(id: "u1", data: [
            "fullName": "Ada Lovelace", "email": "ada@x.com", "employeeId": "EMP001",
        ])!
        XCTAssertEqual(user.employeeId, "EMP001")

        let noId = AppUser(id: "u2", data: ["fullName": "Bob", "email": "bob@x.com"])!
        XCTAssertNil(noId.employeeId, "absent employeeId parses as nil, not empty string")
    }

    func testEmergencyContactFieldsAndLegacyFallback() {
        let legacy = AppUser(id: "u2", data: [
            "fullName": "Bob", "email": "bob@x.com",
            "emergencyContact": "Jane Doe",
        ])!
        XCTAssertEqual(legacy.emergencyContactName, "Jane Doe")

        let structured = AppUser(id: "u3", data: [
            "fullName": "Carol", "email": "carol@x.com",
            "emergencyContactName": "Pat",
            "emergencyContactPhone": "0400000000",
            "emergencyContactAddress": "1 Main St",
            "emergencyContactEmail": "pat@example.com",
        ])!
        XCTAssertEqual(structured.emergencyContactPhone, "0400000000")
        XCTAssertEqual(structured.emergencyContactEmail, "pat@example.com")
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

        let emergencyRequired = TestSupport.user(extra: [
            "dob": "1990-01-01", "address": "1 Test St", "phone": "0400000000",
            "emergencyDetailsRequired": true,
        ])
        XCTAssertTrue(emergencyRequired.needsProfileCompletion, "required emergency details block staff access")

        let roleReview = TestSupport.user(extra: [
            "dob": "1990-01-01", "address": "1 Test St", "phone": "0400000000",
            "roleReviewRequired": true,
        ])
        XCTAssertTrue(roleReview.needsProfileCompletion, "a changed role must be acknowledged")

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

    func testResolvedAvailabilityUsesWeekOverrideThenRecurringTemplate() {
        let user = TestSupport.user(extra: [
            "availability": [
                "monday": ["available": true, "allDay": false, "start": "08:00", "end": "12:00"],
            ],
            "weeklyAvailability": [
                "2026-06-01": [
                    "monday": ["available": false, "allDay": false],
                ],
            ],
        ])

        XCTAssertFalse(user.resolvedAvailability(forWeekKey: "2026-06-01")[.monday].available)
        let recurring = user.resolvedAvailability(forWeekKey: "2026-06-08")[.monday]
        XCTAssertTrue(recurring.available)
        XCTAssertEqual(recurring.start, "08:00")
        XCTAssertEqual(recurring.end, "12:00")
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
        XCTAssertEqual(AppSettings(data: [:]).companyName, "Rosterra")
        XCTAssertEqual(AppSettings(data: ["companyName": ""]).companyName, "Rosterra")
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

    // MARK: - Wages module

    func testWageAwardRoundTripAndKindGuard() {
        let award = WageAward(id: "a1", name: "General Retail Industry Award",
                              code: "MA000004", industry: "Retail",
                              classifications: [AwardClassification(level: "2", title: "Retail Employee Level 2", baseHourlyRate: 26.18)])
        let restored = WageAward(id: "a1", data: award.asDictionary)
        XCTAssertEqual(restored, award)
        XCTAssertNil(EarningsLine(id: "a1", data: award.asDictionary),
                     "kind discriminator prevents cross-parsing")
    }

    func testEarningsLineRoundTripAndSummary() {
        let overtime = EarningsLine(id: "e1", name: "Overtime 1.5x",
                                    category: .overtime, rateType: .multipleOfOrdinary, multiplier: 1.5)
        XCTAssertEqual(EarningsLine(id: "e1", data: overtime.asDictionary), overtime)
        XCTAssertEqual(overtime.rateSummary, "1.5× ordinary")

        let level = EarningsLine(id: "e3", name: "Adult 20+", category: .ordinaryHours,
                                 rateType: .fixedAmount, fixedRate: 36.85,
                                 awardId: "a1", level: "20+", baseHourlyRate: 36.85,
                                 weekendHourlyRate: 48.07)
        XCTAssertTrue(level.isClassificationLevel)
        XCTAssertEqual(level.rateSummary, "$36.85 M–F · $48.07 Wknd/PH")
        XCTAssertEqual(EarningsLine(id: "e3", data: level.asDictionary), level)

        let kmAllowance = EarningsLine(id: "e2", name: "Vehicle allowance",
                                       category: .allowance, rateType: .ratePerUnit,
                                       fixedRate: 0.96, unitName: "km", exemptFromSuper: true)
        XCTAssertEqual(kmAllowance.rateSummary, "$0.96/km")
        XCTAssertEqual(EarningsLine(id: "e2", data: kmAllowance.asDictionary), kmAllowance)
    }

    func testStaffWageProfileRoundTrip() {
        let profile = StaffWageProfile(staffId: "u1", awardId: "a1",
                                       classificationLevel: "2", earningsLineIds: ["e1", "e2"])
        XCTAssertEqual(profile.id, "staff_u1")
        let restored = StaffWageProfile(id: profile.id, data: profile.asDictionary)
        XCTAssertEqual(restored, profile)

        let bare = StaffWageProfile(staffId: "u2")
        let restoredBare = StaffWageProfile(id: bare.id, data: bare.asDictionary)
        XCTAssertEqual(restoredBare?.awardId, nil)
    }

    func testUserSuperRateParsing() {
        XCTAssertEqual(TestSupport.user(extra: ["superRate": 12.0]).superRate, 12.0)
        XCTAssertNil(TestSupport.user().superRate)
    }

    // MARK: - Contact validation

    func testPhoneValidationSupportsAustraliaAndInternationalCountries() {
        XCTAssertTrue(ContactValidation.isValidPhone("0412 345 678"))
        XCTAssertTrue(ContactValidation.isValidPhone("+61 412 345 678"))
        XCTAssertTrue(ContactValidation.isValidPhone("+64 21 123 4567"))
        XCTAssertTrue(ContactValidation.isValidPhone("+44 20 7946 0958"))
        XCTAssertTrue(ContactValidation.isValidPhone("+1 202-555-0123"))
        XCTAssertTrue(ContactValidation.isValidPhone("+91 98765 43210"))
        XCTAssertEqual(ContactValidation.normalizedPhone("0412 345 678"), "+61412345678")
    }

    func testPhoneValidationRejectsIncompleteOrImpossibleNumbers() {
        XCTAssertFalse(ContactValidation.isValidPhone(""))
        XCTAssertFalse(ContactValidation.isValidPhone("+61"))
        XCTAssertFalse(ContactValidation.isValidPhone("0412 34"))
        XCTAssertFalse(ContactValidation.isValidPhone("not a phone"))
        XCTAssertNotNil(ContactValidation.phoneError("+61"))
    }

    func testEmailValidationRequiresACompleteDomain() {
        XCTAssertTrue(ContactValidation.isValidEmail("person@gmail.com"))
        XCTAssertTrue(ContactValidation.isValidEmail("person@outlook.com"))
        XCTAssertTrue(ContactValidation.isValidEmail("payroll@example.com.au"))
        XCTAssertFalse(ContactValidation.isValidEmail("person@"))
        XCTAssertFalse(ContactValidation.isValidEmail("person@gmail"))
        XCTAssertFalse(ContactValidation.isValidEmail("@outlook.com"))
        XCTAssertFalse(ContactValidation.isValidEmail("person outlook.com"))
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
