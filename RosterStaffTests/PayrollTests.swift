import XCTest
@testable import RosterStaff

/// Payroll arithmetic, hour bucketing, status workflow flags, and Firestore
/// round-tripping for the Payroll module. All money math must survive these —
/// payslips are official records.
final class PayrollTests: XCTestCase {

    // MARK: - PayrollCalculator totals

    private func makeSlip(
        ordinaryHours: Double = 0, baseRate: Double = 0,
        weekendHours: Double = 0, weekendRate: Double = 0,
        publicHolidayHours: Double = 0, publicHolidayRate: Double = 0,
        overtimeHours: Double = 0, overtimeRate: Double = 0,
        extras: [PayslipEarning] = [],
        payg: Double = 0, other: Double = 0, sacrifice: Double = 0,
        superRate: Double = 12.0
    ) -> Payslip {
        Payslip(id: "2026-07-06_s1", staffId: "s1", staffName: "Test Staff",
                periodStart: "2026-07-06", periodEnd: "2026-07-12",
                baseHourlyRate: baseRate,
                ordinaryHours: ordinaryHours,
                weekendHours: weekendHours, weekendRate: weekendRate,
                publicHolidayHours: publicHolidayHours, publicHolidayRate: publicHolidayRate,
                overtimeHours: overtimeHours, overtimeRate: overtimeRate,
                extraEarnings: extras,
                payg: payg, otherDeductions: other, salarySacrifice: sacrifice,
                superRate: superRate)
    }

    func testGrossFromAllBuckets() {
        let slip = makeSlip(ordinaryHours: 20, baseRate: 30,
                            weekendHours: 8, weekendRate: 45,
                            publicHolidayHours: 4, publicHolidayRate: 67.50,
                            overtimeHours: 2, overtimeRate: 45)
        let totals = slip.totals
        XCTAssertEqual(totals.ordinaryAmount, 600)
        XCTAssertEqual(totals.weekendAmount, 360)
        XCTAssertEqual(totals.publicHolidayAmount, 270)
        XCTAssertEqual(totals.overtimeAmount, 90)
        XCTAssertEqual(totals.gross, 1320)
        XCTAssertEqual(totals.totalHours, 34)
    }

    func testNetSubtractsTaxAndDeductions() {
        let slip = makeSlip(ordinaryHours: 40, baseRate: 25,
                            payg: 150, other: 20, sacrifice: 50)
        let totals = slip.totals
        XCTAssertEqual(totals.gross, 1000)
        XCTAssertEqual(totals.tax, 150)
        XCTAssertEqual(totals.deductions, 70)
        XCTAssertEqual(totals.net, 780)
    }

    func testSuperExcludesOvertime() {
        // SG applies to OTE: ordinary + weekend + PH, NOT overtime.
        let slip = makeSlip(ordinaryHours: 10, baseRate: 30,
                            overtimeHours: 10, overtimeRate: 45,
                            superRate: 12)
        XCTAssertEqual(slip.totals.superAmount, 36) // 300 * 12%
    }

    func testSuperExcludesExemptExtras() {
        let extras = [
            PayslipEarning(name: "Tool allowance", amount: 100, exemptFromSuper: false),
            PayslipEarning(name: "Meal allowance", amount: 50, exemptFromSuper: true),
        ]
        let slip = makeSlip(ordinaryHours: 0, baseRate: 0, extras: extras, superRate: 10)
        XCTAssertEqual(slip.totals.extrasAmount, 150)
        XCTAssertEqual(slip.totals.gross, 150)
        XCTAssertEqual(slip.totals.superAmount, 10) // only the $100 row
    }

    func testMoneyRoundingToCents() {
        let slip = makeSlip(ordinaryHours: 7.37, baseRate: 26.18)
        // 7.37 * 26.18 = 192.9466 → 192.95
        XCTAssertEqual(slip.totals.ordinaryAmount, 192.95)
    }

    // MARK: - Hours bucketing (Adelaide weekends)

    func testHoursBucketsSplitsWeekend() {
        // 2026-07-06 Mon … 2026-07-11 Sat, 2026-07-12 Sun
        let buckets = PayrollCalculator.hoursBuckets(workedHoursByDate: [
            "2026-07-06": 8,   // Mon
            "2026-07-08": 6,   // Wed
            "2026-07-11": 5,   // Sat
            "2026-07-12": 4,   // Sun
        ])
        XCTAssertEqual(buckets.ordinary, 14)
        XCTAssertEqual(buckets.weekend, 9)
    }

    func testHoursBucketsIgnoresBadKeys() {
        let buckets = PayrollCalculator.hoursBuckets(workedHoursByDate: ["garbage": 8])
        XCTAssertEqual(buckets.ordinary, 0)
        XCTAssertEqual(buckets.weekend, 0)
    }

    // MARK: - Status workflow

    func testEditableStatuses() {
        XCTAssertTrue(PayslipStatus.draft.isEditable)
        XCTAssertTrue(PayslipStatus.underReview.isEditable)
        XCTAssertFalse(PayslipStatus.approved.isEditable)
        XCTAssertFalse(PayslipStatus.submitted.isEditable)
        XCTAssertFalse(PayslipStatus.archived.isEditable)
    }

    func testStaffVisibility() {
        // The core product rule: staff see nothing before submission.
        XCTAssertFalse(PayslipStatus.draft.isStaffVisible)
        XCTAssertFalse(PayslipStatus.underReview.isStaffVisible)
        XCTAssertFalse(PayslipStatus.approved.isStaffVisible)
        XCTAssertTrue(PayslipStatus.submitted.isStaffVisible)
        XCTAssertTrue(PayslipStatus.archived.isStaffVisible)
    }

    // MARK: - Firestore round-trip

    func testPayslipRoundTrip() {
        var original = makeSlip(ordinaryHours: 12.5, baseRate: 28.40,
                                weekendHours: 3, weekendRate: 42.60,
                                extras: [PayslipEarning(name: "Laundry", quantity: 2, rate: 1.25, amount: 2.50)],
                                payg: 88, superRate: 11.5)
        original.status = .approved
        original.notes = "Week note"
        original.audit = [PayslipAuditEntry(action: "generated", userId: "m1", userName: "Manager")]

        let parsed = Payslip(id: original.id, data: original.asDictionary)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.status, .approved)
        XCTAssertEqual(parsed?.ordinaryHours, 12.5)
        XCTAssertEqual(parsed?.baseHourlyRate, 28.40)
        XCTAssertEqual(parsed?.weekendRate, 42.60)
        XCTAssertEqual(parsed?.superRate, 11.5)
        XCTAssertEqual(parsed?.extraEarnings.count, 1)
        XCTAssertEqual(parsed?.extraEarnings.first?.amount, 2.50)
        XCTAssertEqual(parsed?.audit.count, 1)
        XCTAssertEqual(parsed?.audit.first?.action, "generated")
        XCTAssertEqual(parsed?.totals, original.totals)
    }

    func testPayslipParsingRejectsMissingStaffId() {
        XCTAssertNil(Payslip(id: "x", data: ["periodStart": "2026-07-06"]))
    }

    func testPayslipDocIdIsIdempotentPerWeekAndStaff() {
        XCTAssertEqual(Payslip.docId(periodStart: "2026-07-06", staffId: "abc"),
                       "2026-07-06_abc")
    }

    // MARK: - StaffWageProfile extensions

    func testWageProfileRoundTripWithPayrollFields() {
        let profile = StaffWageProfile(staffId: "s1", awardId: "a1",
                                       classificationLevel: "2",
                                       earningsLineIds: ["l1"],
                                       hourlyRateOverride: 31.25,
                                       employmentType: "casual",
                                       ageGroup: "Adult",
                                       effectiveDate: "2026-07-01",
                                       active: false)
        let parsed = StaffWageProfile(id: profile.id, data: profile.asDictionary)
        XCTAssertEqual(parsed?.employmentType, "casual")
        XCTAssertEqual(parsed?.ageGroup, "Adult")
        XCTAssertEqual(parsed?.effectiveDate, "2026-07-01")
        XCTAssertEqual(parsed?.active, false)
        XCTAssertEqual(parsed?.hourlyRateOverride, 31.25)
    }

    func testResolvedHourlyRateOverrideWins() {
        let award = WageAward(id: "a1", name: "Retail",
                              classifications: [AwardClassification(level: "2", title: "L2", baseHourlyRate: 26.18)])
        let withOverride = StaffWageProfile(staffId: "s", awardId: "a1",
                                            classificationLevel: "2", hourlyRateOverride: 30)
        XCTAssertEqual(withOverride.resolvedHourlyRate(award: award), 30)

        let fromAward = StaffWageProfile(staffId: "s", awardId: "a1", classificationLevel: "2")
        XCTAssertEqual(fromAward.resolvedHourlyRate(award: award), 26.18)

        let noMatch = StaffWageProfile(staffId: "s", awardId: "a1", classificationLevel: "9")
        XCTAssertNil(noMatch.resolvedHourlyRate(award: award))
    }

    func testResolvedHourlyRateFromOrdinaryEarningsLine() {
        // Root cause of the 2026-07-10 "$0.00 payslip" bug: a profile with
        // ONLY an earnings line assigned (no award classification, no
        // override) must still resolve a rate from an ordinary-hours line
        // that carries its own dollar amount.
        let lines = [
            EarningsLine(id: "l1", name: "Ordinary Hours", category: .ordinaryHours,
                         rateType: .fixedAmount, fixedRate: 30.50),
            EarningsLine(id: "l2", name: "Overtime 1.5x", category: .overtime,
                         rateType: .multipleOfOrdinary, multiplier: 1.5),
        ]
        let profile = StaffWageProfile(staffId: "s", earningsLineIds: ["l1", "l2"])
        XCTAssertEqual(profile.resolvedHourlyRate(award: nil, earningsLines: lines), 30.50)
    }

    func testResolvedHourlyRateIgnoresUnassignedAndUnusableLines() {
        let lines = [
            // Not assigned to this profile.
            EarningsLine(id: "other", name: "Ordinary", category: .ordinaryHours,
                         rateType: .fixedAmount, fixedRate: 99),
            // Assigned but multiple-of-ordinary — can't bootstrap a rate.
            EarningsLine(id: "l1", name: "Ordinary 1x", category: .ordinaryHours,
                         rateType: .multipleOfOrdinary, multiplier: 1),
            // Assigned but inactive.
            EarningsLine(id: "l2", name: "Old rate", category: .ordinaryHours,
                         rateType: .fixedAmount, fixedRate: 25, active: false),
        ]
        let profile = StaffWageProfile(staffId: "s", earningsLineIds: ["l1", "l2"])
        XCTAssertNil(profile.resolvedHourlyRate(award: nil, earningsLines: lines))
    }

    func testClassificationBeatsEarningsLineRate() {
        let award = WageAward(id: "a1", name: "Retail",
                              classifications: [AwardClassification(level: "2", title: "L2", baseHourlyRate: 26.18)])
        let lines = [EarningsLine(id: "l1", name: "Ordinary", category: .ordinaryHours,
                                  rateType: .fixedAmount, fixedRate: 30)]
        let profile = StaffWageProfile(staffId: "s", awardId: "a1",
                                       classificationLevel: "2", earningsLineIds: ["l1"])
        XCTAssertEqual(profile.resolvedHourlyRate(award: award, earningsLines: lines), 26.18)
    }

    // MARK: - Superannuation toggle (under-18 staff)

    func testResolvedSuperRateWhenDisabled() {
        let profile = StaffWageProfile(staffId: "s", superEnabled: false, superRate: 12)
        XCTAssertEqual(profile.resolvedSuperRate(userDefault: 11.5), 0)
    }

    func testResolvedSuperRatePrecedence() {
        // Profile override → user default → statutory 12%.
        XCTAssertEqual(StaffWageProfile(staffId: "s", superRate: 10.5)
            .resolvedSuperRate(userDefault: 11.5), 10.5)
        XCTAssertEqual(StaffWageProfile(staffId: "s")
            .resolvedSuperRate(userDefault: 11.5), 11.5)
        XCTAssertEqual(StaffWageProfile(staffId: "s")
            .resolvedSuperRate(userDefault: nil), 12.0)
    }

    func testSuperToggleRoundTrip() {
        let profile = StaffWageProfile(staffId: "s1", superEnabled: false, superRate: 10)
        let parsed = StaffWageProfile(id: profile.id, data: profile.asDictionary)
        XCTAssertEqual(parsed?.superEnabled, false)
        XCTAssertEqual(parsed?.superRate, 10)
    }

    func testZeroSuperRateProducesZeroSuperAmount() {
        let slip = makeSlip(ordinaryHours: 20, baseRate: 25, superRate: 0)
        XCTAssertEqual(slip.totals.superAmount, 0)
        XCTAssertEqual(slip.totals.gross, 500)
    }

    // MARK: - Legacy profile parsing (pre-payroll docs)

    func testLegacyWageProfileDefaultsToActive() {
        // Docs written before the payroll fields existed must stay eligible
        // for draft generation (active defaults true).
        let legacy: [String: Any] = [
            "kind": "staffProfile", "staffId": "s1", "earningsLineIds": [],
        ]
        let parsed = StaffWageProfile(id: "staff_s1", data: legacy)
        XCTAssertEqual(parsed?.active, true)
        XCTAssertNil(parsed?.employmentType)
        // Pre-toggle docs keep paying super (default ON).
        XCTAssertEqual(parsed?.superEnabled, true)
        XCTAssertNil(parsed?.superRate)
    }
}
