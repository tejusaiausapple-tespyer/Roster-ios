import XCTest
@testable import Rosterra

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
        claimsTaxFreeThreshold: Bool = true,
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
                claimsTaxFreeThreshold: claimsTaxFreeThreshold,
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

    // MARK: - PAYG withholding (ATO Schedule 1, weekly, 2026–27)
    //
    // Expected values cross-checked against the ATO's own published weekly
    // withholding lookup table for 2026–27 (independent of this formula/
    // coefficient implementation) — not just re-deriving the same numbers.

    func testPAYGScale2ThresholdClaimedMatchesATOWeeklyTable() {
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 0, claimsTaxFreeThreshold: true), 0)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 350, claimsTaxFreeThreshold: true), 0)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 361, claimsTaxFreeThreshold: true), 0)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 500, claimsTaxFreeThreshold: true), 21)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 1000, claimsTaxFreeThreshold: true), 138)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 2000, claimsTaxFreeThreshold: true), 459)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 3500, claimsTaxFreeThreshold: true), 1002)
    }

    func testPAYGScale1NoThresholdMatchesATOWeeklyTable() {
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 350, claimsTaxFreeThreshold: false), 62)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 500, claimsTaxFreeThreshold: false), 90)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 1000, claimsTaxFreeThreshold: false), 249)
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: 3500, claimsTaxFreeThreshold: false), 1152)
    }

    func testPAYGTruncatesCentsBeforeApplyingFormula() {
        // ATO method: truncate to whole dollars, add 99c, then apply a×x−b —
        // so any cents on the input collapse to the same result as the whole
        // dollar amount, NOT round-to-nearest-cent first.
        let whole = PAYGCalculator.weeklyWithholding(taxableEarnings: 500, claimsTaxFreeThreshold: true)
        let withCents = PAYGCalculator.weeklyWithholding(taxableEarnings: 500.50, claimsTaxFreeThreshold: true)
        XCTAssertEqual(whole, 21)
        XCTAssertEqual(withCents, 21)
    }

    func testPAYGNeverNegative() {
        XCTAssertEqual(PAYGCalculator.weeklyWithholding(taxableEarnings: -50, claimsTaxFreeThreshold: true), 0)
    }

    func testTaxableEarningsExcludesExemptExtrasAndSalarySacrifice() {
        let extras = [
            PayslipEarning(name: "Bonus", amount: 30, exemptFromTax: false),
            PayslipEarning(name: "Tax-exempt allowance", amount: 50, exemptFromTax: true),
        ]
        let slip = makeSlip(ordinaryHours: 40, baseRate: 25, extras: extras, sacrifice: 100)
        // Gross includes both extras; taxable base excludes the exempt one
        // and subtracts salary sacrifice (pre-tax): 1000 + 30 - 100 = 930.
        XCTAssertEqual(slip.totals.gross, 1080)
        XCTAssertEqual(PayrollCalculator.taxableEarnings(for: slip), 930)
    }

    func testCalculatedPAYGUsesTheSlipsThresholdDeclaration() {
        let claimed = makeSlip(ordinaryHours: 20, baseRate: 25, claimsTaxFreeThreshold: true)
        let notClaimed = makeSlip(ordinaryHours: 20, baseRate: 25, claimsTaxFreeThreshold: false)
        XCTAssertEqual(PayrollCalculator.taxableEarnings(for: claimed), 500)
        XCTAssertEqual(PayrollCalculator.calculatedPAYG(for: claimed), 21)
        XCTAssertEqual(PayrollCalculator.calculatedPAYG(for: notClaimed), 90)
    }

    func testClaimsTaxFreeThresholdRoundTrips() {
        let notClaimed = makeSlip(ordinaryHours: 1, baseRate: 1, claimsTaxFreeThreshold: false)
        XCTAssertEqual(Payslip(id: notClaimed.id, data: notClaimed.asDictionary)?.claimsTaxFreeThreshold, false)

        // Docs written before this field existed must still default to
        // claimed (true) — the common case and the ATO's own default.
        let legacy: [String: Any] = ["staffId": "s1", "periodStart": "2026-07-06", "periodEnd": "2026-07-12"]
        XCTAssertEqual(Payslip(id: "x", data: legacy)?.claimsTaxFreeThreshold, true)
    }

    func testWageProfileClaimsTaxFreeThresholdRoundTrips() {
        let profile = StaffWageProfile(staffId: "s1", claimsTaxFreeThreshold: false)
        let parsed = StaffWageProfile(id: profile.id, data: profile.asDictionary)
        XCTAssertEqual(parsed?.claimsTaxFreeThreshold, false)

        // Pre-existing profiles (written before this field existed) default
        // to claimed, same as a fresh TFN declaration would assume.
        let legacy: [String: Any] = ["kind": "staffProfile", "staffId": "s1", "earningsLineIds": []]
        XCTAssertEqual(StaffWageProfile(id: "staff_s1", data: legacy)?.claimsTaxFreeThreshold, true)
    }

    // MARK: - Field-level audit diff (bulk publish / payslip editing)

    private var testEditor: AppUser {
        TestSupport.user(id: "m1", fullName: "Manager One", role: "manager")
    }

    func testAuditDiffDetectsChangedScalarFields() {
        let old = makeSlip(ordinaryHours: 20, baseRate: 25, payg: 50, superRate: 12)
        var new = old
        new.ordinaryHours = 25
        new.payg = 60

        let entries = PayrollCalculator.auditDiff(from: old, to: new, editor: testEditor)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.action == "edited" && $0.userId == "m1" && $0.userName == "Manager One" })
        XCTAssertTrue(entries.contains {
            $0.field == "Ordinary hours" && $0.previousValue == "20.00" && $0.newValue == "25.00"
                && $0.detail == "Ordinary hours: 20.00 → 25.00"
        })
        XCTAssertTrue(entries.contains {
            $0.field == "PAYG withholding" && $0.previousValue == RosterFormat.money(50) && $0.newValue == RosterFormat.money(60)
        })
    }

    func testAuditDiffEmptyWhenNothingChanged() {
        let slip = makeSlip(ordinaryHours: 20, baseRate: 25, payg: 50)
        XCTAssertTrue(PayrollCalculator.auditDiff(from: slip, to: slip, editor: testEditor).isEmpty)
    }

    func testAuditDiffToleratesFloatNoiseViaRounding() {
        // 7.365 and 7.37 both round to the same displayed 7.37 (round2) —
        // must not fire a spurious entry over float-arithmetic noise.
        let old = makeSlip(ordinaryHours: 7.37, baseRate: 26.18)
        var new = old
        new.ordinaryHours = 7.365
        XCTAssertTrue(PayrollCalculator.auditDiff(from: old, to: new, editor: testEditor).isEmpty)
    }

    func testAuditDiffExcludesPayDate() {
        // payDate is displayed but not wired to any editable control today —
        // deliberately excluded from the diff.
        var old = makeSlip(ordinaryHours: 20, baseRate: 25)
        old.payDate = "2026-07-12"
        var new = old
        new.payDate = "2026-07-13"
        XCTAssertTrue(PayrollCalculator.auditDiff(from: old, to: new, editor: testEditor).isEmpty)
    }

    func testAuditDiffHandlesExtraEarningsAddRemoveAndChange() {
        let kept = PayslipEarning(id: "e1", name: "Tool allowance", amount: 50)
        let removed = PayslipEarning(id: "e2", name: "Old bonus", amount: 20)
        let old = makeSlip(extras: [kept, removed])

        var changedKept = kept
        changedKept.amount = 75
        let added = PayslipEarning(id: "e3", name: "New bonus", amount: 30)
        let new = makeSlip(extras: [changedKept, added])

        let entries = PayrollCalculator.auditDiff(from: old, to: new, editor: testEditor)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains { $0.detail == "Removed earnings row: Old bonus" })
        XCTAssertTrue(entries.contains { $0.detail == "Added earnings row: New bonus (\(RosterFormat.money(30)))" })
        XCTAssertTrue(entries.contains { $0.detail == "Tool allowance: \(RosterFormat.money(50)) → \(RosterFormat.money(75))" })
    }

    func testAuditDiffIgnoresUnchangedExtraEarningsQuantityOnlySync() {
        // A quantity edit already resyncs `amount` (ManagerPayslipDetailSheet.extraBinding) —
        // amount is the only thing diffed, so this must report exactly one entry, not two.
        let old = makeSlip(extras: [PayslipEarning(id: "e1", name: "Laundry", quantity: 2, rate: 1.25, amount: 2.50)])
        let new = makeSlip(extras: [PayslipEarning(id: "e1", name: "Laundry", quantity: 4, rate: 1.25, amount: 5.00)])
        let entries = PayrollCalculator.auditDiff(from: old, to: new, editor: testEditor)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.detail, "Laundry: \(RosterFormat.money(2.50)) → \(RosterFormat.money(5.00))")
    }

    func testPayslipAuditEntryFieldLevelDataRoundTrips() {
        let entry = PayslipAuditEntry(action: "edited", userId: "m1", userName: "Manager One",
                                      detail: "Ordinary hours: 20.00 → 25.00",
                                      field: "Ordinary hours", previousValue: "20.00", newValue: "25.00")
        let parsed = PayslipAuditEntry(dict: entry.asDictionary)
        XCTAssertEqual(parsed.field, "Ordinary hours")
        XCTAssertEqual(parsed.previousValue, "20.00")
        XCTAssertEqual(parsed.newValue, "25.00")
        XCTAssertEqual(parsed.detail, entry.detail)
    }

    func testPayslipAuditEntryFieldDataNilForCoarseGrainedActions() {
        // Existing coarse actions (generated/approved/submitted/regenerated/...)
        // never set these — must default to nil, not crash or coerce to "".
        let entry = PayslipAuditEntry(action: "generated", userId: "m1", userName: "Manager One", detail: "Auto-generated")
        XCTAssertNil(entry.field)
        let parsed = PayslipAuditEntry(dict: entry.asDictionary)
        XCTAssertNil(parsed.field)
        XCTAssertNil(parsed.previousValue)
        XCTAssertNil(parsed.newValue)
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
        original.employeeId = "EMP007"
        original.audit = [PayslipAuditEntry(action: "generated", userId: "m1", userName: "Manager")]

        let parsed = Payslip(id: original.id, data: original.asDictionary)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.status, .approved)
        XCTAssertEqual(parsed?.employeeId, "EMP007")
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

    func testResolvedHourlyRateFromClassificationEarningsLine() {
        let lines = [
            EarningsLine(id: "l1", name: "Adult 20+", category: .ordinaryHours,
                         rateType: .fixedAmount, fixedRate: 36.85,
                         awardId: "a1", level: "20+", baseHourlyRate: 36.85),
        ]
        let profile = StaffWageProfile(staffId: "s", awardId: "a1", classificationLevel: "20+")
        XCTAssertEqual(profile.resolvedHourlyRate(award: nil, earningsLines: lines), 36.85)
        XCTAssertEqual(profile.resolvedClassificationTitle(award: nil, earningsLines: lines), "Adult 20+")
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

    // MARK: - Classification display order (Wage list ⇔ assignment picker)

    func testClassificationDisplayOrderIsNumericAware() {
        // "2" before "10" (plain string compare would invert them).
        XCTAssertTrue(ClassificationDisplayOrder.areInOrder(levelA: "2", titleA: "L2", levelB: "10", titleB: "L10"))
        XCTAssertFalse(ClassificationDisplayOrder.areInOrder(levelA: "10", titleA: "L10", levelB: "2", titleB: "L2"))
    }

    func testClassificationDisplayOrderFallsBackToTitleWhenLevelEmpty() {
        XCTAssertTrue(ClassificationDisplayOrder.areInOrder(levelA: "", titleA: "Apprentice", levelB: "", titleB: "Senior"))
        // Empty level compares by title against a populated level code.
        XCTAssertTrue(ClassificationDisplayOrder.areInOrder(levelA: "17", titleA: "17 years", levelB: "", titleB: "Under 21"))
    }

    func testClassificationDisplayOrderSortsAgeBrackets() {
        let levels = [("U17", "Under 17"), ("19", "19 years"), ("20+", "Adult 20+"), ("17", "17 years"), ("18", "18 years")]
        let sorted = levels.sorted {
            ClassificationDisplayOrder.areInOrder(levelA: $0.0, titleA: $0.1, levelB: $1.0, titleB: $1.1)
        }
        XCTAssertEqual(sorted.map(\.0), ["17", "18", "19", "20+", "U17"])
    }

    // MARK: - Classification weekend rates

    func testClassificationWeekendRateRoundTrip() {
        // Console seed template removed 2026-07-10 (owner: managers create
        // levels manually) — round-trip coverage kept with an inline fixture.
        let classifications = [
            AwardClassification(level: "U17", title: "Under 17", baseHourlyRate: 17.50, weekendHourlyRate: 22.83),
            AwardClassification(level: "20+", title: "Adult 20+", baseHourlyRate: 36.85, weekendHourlyRate: 48.07),
        ]
        let award = WageAward(id: "a1", name: "Console", classifications: classifications)
        let parsed = WageAward(id: "a1", data: award.asDictionary)
        XCTAssertEqual(parsed?.classifications, classifications)
    }

    func testLegacyClassificationParsesWithoutWeekendRate() {
        let classification = AwardClassification(dict: [
            "level": "2", "title": "L2", "baseHourlyRate": 26.18,
        ])
        XCTAssertEqual(classification.weekendHourlyRate, 0) // → payroll falls back to multipliers
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

    // MARK: - Live rate resolution (Roster cost chip, Reports, Timesheet detail)
    //
    // Before this, those three screens all did `user.hourlyRate ?? 25.0`,
    // completely bypassing the wage-profile model that payroll generation
    // already used — the same schema/behavior gap that was found on the PWA
    // side (see docs/PWA-IOS-PARITY-AND-DISCREPANCY-REPORT.md §2.1/§2.2).

    // 2026-06-01 is a Monday (weekday); 2026-06-06 is a Saturday (weekend).
    private let weekday = "2026-06-01"
    private let weekend = "2026-06-06"

    func testIsWeekendDetectsSaturdayAndSunday() {
        XCTAssertFalse(RosterCalendar.isWeekend(dateKey: weekday))
        XCTAssertTrue(RosterCalendar.isWeekend(dateKey: weekend))
        XCTAssertTrue(RosterCalendar.isWeekend(dateKey: "2026-06-07")) // Sunday
        XCTAssertFalse(RosterCalendar.isWeekend(dateKey: "not-a-date"))
    }

    func testLoadedRateReturnsNilWithNoProfile() {
        XCTAssertNil(StaffWageProfile.loadedRate(profile: nil, award: nil, earningsLines: [], shiftDateKey: weekday))
    }

    func testLoadedRateUsesOrdinaryRateOnAWeekday() {
        let line = EarningsLine(id: "l1", name: "L2", category: .ordinaryHours,
                                rateType: .fixedAmount, level: "2", baseHourlyRate: 24.85)
        let profile = StaffWageProfile(staffId: "s", classificationLevel: "2")
        let rate = StaffWageProfile.loadedRate(profile: profile, award: nil, earningsLines: [line], shiftDateKey: weekday)
        XCTAssertEqual(rate, 24.85)
    }

    func testLoadedRateUsesExplicitWeekendRateWhenSet() {
        let line = EarningsLine(id: "l1", name: "L2", category: .ordinaryHours,
                                rateType: .fixedAmount, level: "2", baseHourlyRate: 24, weekendHourlyRate: 31.06)
        let profile = StaffWageProfile(staffId: "s", classificationLevel: "2")
        let rate = StaffWageProfile.loadedRate(profile: profile, award: nil, earningsLines: [line], shiftDateKey: weekend)
        XCTAssertEqual(rate, 31.06)
    }

    func testLoadedRateFallsBackTo1point5xOnWeekendWithNoExplicitRate() {
        let line = EarningsLine(id: "l1", name: "L2", category: .ordinaryHours,
                                rateType: .fixedAmount, level: "2", baseHourlyRate: 20)
        let profile = StaffWageProfile(staffId: "s", classificationLevel: "2")
        let rate = StaffWageProfile.loadedRate(profile: profile, award: nil, earningsLines: [line], shiftDateKey: weekend)
        XCTAssertEqual(rate, 30) // 20 * 1.5, same default the payslip generator applies
    }

    func testLoadedRateWithNoDateKeyIgnoresWeekendCheck() {
        // Callers that can't supply a shift date (e.g. no linked shift) still
        // get the resolved ordinary rate rather than nil.
        let line = EarningsLine(id: "l1", name: "L2", category: .ordinaryHours,
                                rateType: .fixedAmount, level: "2", baseHourlyRate: 24)
        let profile = StaffWageProfile(staffId: "s", classificationLevel: "2")
        let rate = StaffWageProfile.loadedRate(profile: profile, award: nil, earningsLines: [line], shiftDateKey: nil)
        XCTAssertEqual(rate, 24)
    }

    func testLoadedRateReturnsNilWhenProfileResolvesNoRate() {
        // Caller (RosterRepository.liveHourlyRate) is responsible for the
        // hourlyRate/default fallback chain — this function must not guess.
        let profile = StaffWageProfile(staffId: "s", classificationLevel: "does-not-exist")
        let rate = StaffWageProfile.loadedRate(profile: profile, award: nil, earningsLines: [], shiftDateKey: weekday)
        XCTAssertNil(rate)
    }
}
