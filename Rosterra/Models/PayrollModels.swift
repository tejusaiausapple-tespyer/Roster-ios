import Foundation

// ─── Payroll module data model ────────────────────────────────────────────────
//
// Payslips live in their own `payslips` collection (NOT `wages` — staff must
// be able to read their own SUBMITTED payslips, and `wages` is manager-only).
// Doc id: "{periodStart}_{staffId}" so weekly draft generation is idempotent;
// corrected re-issues append "_c{n}".
//
// LIFECYCLE: draft → underReview → approved → submitted (→ archived).
// Only `submitted`/`archived` payslips are staff-visible — enforced by the
// Firestore rules (see docs/reference/firestore.rules.payroll-proposed), not
// by client filtering.
//
// SNAPSHOTS: generation copies the staff member's name, award, classification
// and resolved hourly rate ONTO the payslip. Later edits to wage profiles,
// awards, rosters or timesheets never change an existing payslip — a manager
// must explicitly regenerate a draft or issue a corrected version.

enum PayslipStatus: String, CaseIterable, Identifiable {
    case draft
    case underReview = "under_review"
    case approved
    case submitted
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .underReview: return "Under Review"
        case .approved: return "Approved"
        case .submitted: return "Submitted"
        case .archived: return "Archived"
        }
    }

    /// Manager can still edit amounts in these states.
    var isEditable: Bool {
        switch self {
        case .draft, .underReview, .approved: return true
        case .submitted, .archived: return false
        }
    }

    /// Staff may see the payslip in these states.
    var isStaffVisible: Bool { self == .submitted || self == .archived }
}

/// A published, already-ended shift within a payroll period that does not
/// yet have an approved timesheet — either staff hasn't submitted, a
/// submission is still awaiting the manager's review, or an absence report
/// hasn't been confirmed. `generateDraftPayslips` silently skips these
/// (it only counts approved hours), so this surfaces the gap explicitly
/// before generation instead of leaving a manager to wonder why a staff
/// member's payslip is missing or incomplete.
struct PayrollGapItem: Identifiable, Equatable {
    enum Reason: Equatable {
        case notSubmitted
        case draftNotSubmitted
        case pendingApproval
        case rejected
        case absenceUnconfirmed

        var label: String {
            switch self {
            case .notSubmitted: return "Not submitted"
            case .draftNotSubmitted: return "Started, not submitted"
            case .pendingApproval: return "Pending your approval"
            case .rejected: return "Rejected — awaiting resubmission"
            case .absenceUnconfirmed: return "Absence reported — needs confirmation"
            }
        }
    }

    var id: String { shiftId }
    let shiftId: String
    let staffId: String
    let staffName: String
    let date: String
    let rosteredStart: String
    let rosteredEnd: String
    let reason: Reason
}

/// An unpublished payslip whose snapshotted hours no longer match the latest
/// approved timesheets. Regeneration is always an explicit manager action
/// because it replaces manual adjustments and returns an approved slip to Draft.
struct PayslipRegenerationChange: Identifiable, Equatable {
    var id: String { payslip.id }
    let payslip: Payslip
    let previousHours: Double
    let latestHours: Double
}

/// One earnings row on a payslip (snapshot — owns its own rate and amount).
struct PayslipEarning: Equatable, Identifiable {
    var id: String
    var name: String
    /// Hours or units. 0 for fixed-amount rows.
    var quantity: Double
    /// $ per hour/unit. 0 for fixed-amount rows (amount carries the value).
    var rate: Double
    var amount: Double
    var exemptFromTax: Bool
    var exemptFromSuper: Bool

    init(id: String = UUID().uuidString, name: String, quantity: Double = 0,
         rate: Double = 0, amount: Double = 0,
         exemptFromTax: Bool = false, exemptFromSuper: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.rate = rate
        self.amount = amount
        self.exemptFromTax = exemptFromTax
        self.exemptFromSuper = exemptFromSuper
    }

    init(dict: [String: Any]) {
        self.id = FS.stringValue(dict, "id", default: UUID().uuidString)
        self.name = FS.stringValue(dict, "name")
        self.quantity = FS.double(dict, "quantity")
        self.rate = FS.double(dict, "rate")
        self.amount = FS.double(dict, "amount")
        self.exemptFromTax = FS.bool(dict, "exemptFromTax")
        self.exemptFromSuper = FS.bool(dict, "exemptFromSuper")
    }

    var asDictionary: [String: Any] {
        ["id": id, "name": name, "quantity": quantity, "rate": rate,
         "amount": amount, "exemptFromTax": exemptFromTax,
         "exemptFromSuper": exemptFromSuper]
    }
}

/// One immutable audit-trail entry stored on the payslip document.
struct PayslipAuditEntry: Equatable, Identifiable {
    var id: String
    var action: String       // generated / edited / approved / submitted / regenerated / downloaded / archived
    var userId: String
    var userName: String
    var at: Date
    var detail: String
    /// Set only for field-level "edited" entries (see `PayrollCalculator.auditDiff`) —
    /// nil for coarse-grained actions like generated/approved/submitted/archived.
    var field: String?
    var previousValue: String?
    var newValue: String?

    init(action: String, userId: String, userName: String, at: Date = Date(), detail: String = "",
         field: String? = nil, previousValue: String? = nil, newValue: String? = nil) {
        self.id = UUID().uuidString
        self.action = action
        self.userId = userId
        self.userName = userName
        self.at = at
        self.detail = detail
        self.field = field
        self.previousValue = previousValue
        self.newValue = newValue
    }

    init(dict: [String: Any]) {
        self.id = FS.stringValue(dict, "id", default: UUID().uuidString)
        self.action = FS.stringValue(dict, "action")
        self.userId = FS.stringValue(dict, "userId")
        self.userName = FS.stringValue(dict, "userName")
        self.at = FS.date(dict, "at") ?? Date(timeIntervalSince1970: 0)
        self.detail = FS.stringValue(dict, "detail")
        self.field = FS.string(dict, "field")
        self.previousValue = FS.string(dict, "previousValue")
        self.newValue = FS.string(dict, "newValue")
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = ["id": id, "action": action, "userId": userId,
                                    "userName": userName, "at": at, "detail": detail]
        dict["field"] = field ?? NSNull()
        dict["previousValue"] = previousValue ?? NSNull()
        dict["newValue"] = newValue ?? NSNull()
        return dict
    }
}

/// A weekly payslip. Everything money-related is a stored snapshot.
struct Payslip: Identifiable, Equatable {
    let id: String
    var staffId: String
    var staffName: String        // snapshot
    var employeeId: String       // snapshot (manager-assigned ID, may be "")
    /// Last 4 digits of TFN at generation time (full TFN stays on users/{uid}).
    var tfnLast4: String
    var position: String         // snapshot (role label)
    var employmentType: String   // snapshot (EmploymentType raw or "")
    var awardName: String        // snapshot
    var awardCode: String        // snapshot
    var classification: String   // snapshot (title)
    var periodStart: String      // Monday, yyyy-MM-dd (Adelaide)
    var periodEnd: String        // Sunday, yyyy-MM-dd
    var payDate: String          // yyyy-MM-dd — defaults to period end, editable
    var status: PayslipStatus

    var baseHourlyRate: Double   // resolved ordinary rate snapshot

    // Hours buckets — each with its own editable rate (defaults derived from
    // the base rate; award penalty rules vary too much to hard-code).
    var ordinaryHours: Double
    var weekendHours: Double
    var weekendRate: Double
    var publicHolidayHours: Double
    var publicHolidayRate: Double
    var overtimeHours: Double
    var overtimeRate: Double

    /// Allowances / bonuses / other pay items (from assigned earnings lines
    /// at generation, manager-editable afterwards).
    var extraEarnings: [PayslipEarning]

    /// Drives which ATO weekly withholding scale `PAYGCalculator` uses
    /// (snapshot — see `StaffWageProfile.claimsTaxFreeThreshold`).
    var claimsTaxFreeThreshold: Bool

    // Deductions. `payg` is auto-calculated at generation time from the ATO
    // formula (PayrollCalculator.calculatedPAYG) but stays manager-editable —
    // e.g. for a HELP/STSL debt or foreign-resident declaration the formula
    // doesn't model.
    var payg: Double
    var otherDeductions: Double
    var salarySacrifice: Double
    var deductionNotes: String

    /// Employer super guarantee percentage (e.g. 12.0).
    var superRate: Double

    var notes: String

    var generatedAt: Date?
    var updatedAt: Date?
    var approvedBy: String?
    var approvedAt: Date?
    var submittedBy: String?
    var submittedAt: Date?

    var audit: [PayslipAuditEntry]

    static func docId(periodStart: String, staffId: String) -> String {
        "\(periodStart)_\(staffId)"
    }

    init(id: String, staffId: String, staffName: String, employeeId: String = "", tfnLast4: String = "",
         position: String = "",
         employmentType: String = "", awardName: String = "", awardCode: String = "",
         classification: String = "", periodStart: String, periodEnd: String,
         payDate: String = "", status: PayslipStatus = .draft,
         baseHourlyRate: Double = 0,
         ordinaryHours: Double = 0, weekendHours: Double = 0, weekendRate: Double = 0,
         publicHolidayHours: Double = 0, publicHolidayRate: Double = 0,
         overtimeHours: Double = 0, overtimeRate: Double = 0,
         extraEarnings: [PayslipEarning] = [],
         claimsTaxFreeThreshold: Bool = true,
         payg: Double = 0, otherDeductions: Double = 0, salarySacrifice: Double = 0,
         deductionNotes: String = "", superRate: Double = BusinessRules.defaultSuperRatePercent, notes: String = "",
         generatedAt: Date? = nil, updatedAt: Date? = nil,
         approvedBy: String? = nil, approvedAt: Date? = nil,
         submittedBy: String? = nil, submittedAt: Date? = nil,
         audit: [PayslipAuditEntry] = []) {
        self.id = id
        self.staffId = staffId
        self.staffName = staffName
        self.employeeId = employeeId
        self.tfnLast4 = tfnLast4
        self.position = position
        self.employmentType = employmentType
        self.awardName = awardName
        self.awardCode = awardCode
        self.classification = classification
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.payDate = payDate.isEmpty ? periodEnd : payDate
        self.status = status
        self.baseHourlyRate = baseHourlyRate
        self.ordinaryHours = ordinaryHours
        self.weekendHours = weekendHours
        self.weekendRate = weekendRate
        self.publicHolidayHours = publicHolidayHours
        self.publicHolidayRate = publicHolidayRate
        self.overtimeHours = overtimeHours
        self.overtimeRate = overtimeRate
        self.extraEarnings = extraEarnings
        self.claimsTaxFreeThreshold = claimsTaxFreeThreshold
        self.payg = payg
        self.otherDeductions = otherDeductions
        self.salarySacrifice = salarySacrifice
        self.deductionNotes = deductionNotes
        self.superRate = superRate
        self.notes = notes
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.submittedBy = submittedBy
        self.submittedAt = submittedAt
        self.audit = audit
    }

    init?(id: String, data: [String: Any]) {
        guard !FS.stringValue(data, "staffId").isEmpty else { return nil }
        self.id = id
        self.staffId = FS.stringValue(data, "staffId")
        self.staffName = FS.stringValue(data, "staffName")
        self.employeeId = FS.stringValue(data, "employeeId")
        self.tfnLast4 = FS.stringValue(data, "tfnLast4")
        self.position = FS.stringValue(data, "position")
        self.employmentType = FS.stringValue(data, "employmentType")
        self.awardName = FS.stringValue(data, "awardName")
        self.awardCode = FS.stringValue(data, "awardCode")
        self.classification = FS.stringValue(data, "classification")
        self.periodStart = FS.stringValue(data, "periodStart")
        self.periodEnd = FS.stringValue(data, "periodEnd")
        self.payDate = FS.stringValue(data, "payDate")
        self.status = PayslipStatus(rawValue: FS.stringValue(data, "status", default: "draft")) ?? .draft
        self.baseHourlyRate = FS.double(data, "baseHourlyRate")
        self.ordinaryHours = FS.double(data, "ordinaryHours")
        self.weekendHours = FS.double(data, "weekendHours")
        self.weekendRate = FS.double(data, "weekendRate")
        self.publicHolidayHours = FS.double(data, "publicHolidayHours")
        self.publicHolidayRate = FS.double(data, "publicHolidayRate")
        self.overtimeHours = FS.double(data, "overtimeHours")
        self.overtimeRate = FS.double(data, "overtimeRate")
        self.extraEarnings = (data["extraEarnings"] as? [[String: Any]] ?? []).map { PayslipEarning(dict: $0) }
        self.claimsTaxFreeThreshold = FS.bool(data, "claimsTaxFreeThreshold", default: true)
        self.payg = FS.double(data, "payg")
        self.otherDeductions = FS.double(data, "otherDeductions")
        self.salarySacrifice = FS.double(data, "salarySacrifice")
        self.deductionNotes = FS.stringValue(data, "deductionNotes")
        self.superRate = FS.double(data, "superRate", default: BusinessRules.defaultSuperRatePercent)
        self.notes = FS.stringValue(data, "notes")
        self.generatedAt = FS.date(data, "generatedAt")
        self.updatedAt = FS.date(data, "updatedAt")
        self.approvedBy = FS.string(data, "approvedBy")
        self.approvedAt = FS.date(data, "approvedAt")
        self.submittedBy = FS.string(data, "submittedBy")
        self.submittedAt = FS.date(data, "submittedAt")
        self.audit = (data["audit"] as? [[String: Any]] ?? []).map { PayslipAuditEntry(dict: $0) }
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "staffId": staffId,
            "staffName": staffName,
            "employeeId": employeeId,
            "tfnLast4": tfnLast4,
            "position": position,
            "employmentType": employmentType,
            "awardName": awardName,
            "awardCode": awardCode,
            "classification": classification,
            "periodStart": periodStart,
            "periodEnd": periodEnd,
            "payDate": payDate,
            "status": status.rawValue,
            "baseHourlyRate": baseHourlyRate,
            "ordinaryHours": ordinaryHours,
            "weekendHours": weekendHours,
            "weekendRate": weekendRate,
            "publicHolidayHours": publicHolidayHours,
            "publicHolidayRate": publicHolidayRate,
            "overtimeHours": overtimeHours,
            "overtimeRate": overtimeRate,
            "extraEarnings": extraEarnings.map { $0.asDictionary },
            "claimsTaxFreeThreshold": claimsTaxFreeThreshold,
            "payg": payg,
            "otherDeductions": otherDeductions,
            "salarySacrifice": salarySacrifice,
            "deductionNotes": deductionNotes,
            "superRate": superRate,
            "notes": notes,
            "audit": audit.map { $0.asDictionary },
        ]
        dict["generatedAt"] = generatedAt ?? NSNull()
        dict["updatedAt"] = updatedAt ?? NSNull()
        dict["approvedBy"] = approvedBy ?? NSNull()
        dict["approvedAt"] = approvedAt ?? NSNull()
        dict["submittedBy"] = submittedBy ?? NSNull()
        dict["submittedAt"] = submittedAt ?? NSNull()
        return dict
    }

    // MARK: Derived money (always computed — the single source of truth for
    // totals is PayrollCalculator; stored docs carry inputs, not totals).

    var totals: PayrollCalculator.Totals { PayrollCalculator.totals(for: self) }
}

/// Pure payroll arithmetic — unit-tested, no Firestore/UI dependencies.
enum PayrollCalculator {
    struct Totals: Equatable {
        var ordinaryAmount: Double
        var weekendAmount: Double
        var publicHolidayAmount: Double
        var overtimeAmount: Double
        var extrasAmount: Double
        var gross: Double
        var tax: Double            // PAYG
        var deductions: Double     // other + salary sacrifice
        var superAmount: Double    // employer SG (on OTE: ordinary+weekend+PH + non-exempt extras)
        var net: Double
        var totalHours: Double
    }

    static func totals(for slip: Payslip) -> Totals {
        let ordinary = round2(slip.ordinaryHours * slip.baseHourlyRate)
        let weekend = round2(slip.weekendHours * slip.weekendRate)
        let publicHoliday = round2(slip.publicHolidayHours * slip.publicHolidayRate)
        let overtime = round2(slip.overtimeHours * slip.overtimeRate)
        let extras = round2(slip.extraEarnings.reduce(0) { $0 + $1.amount })
        let gross = round2(ordinary + weekend + publicHoliday + overtime + extras)

        // Super guarantee applies to ordinary time earnings — overtime is
        // excluded, as are earnings rows flagged exempt (ATO SGR 2009/2).
        let superableExtras = slip.extraEarnings.filter { !$0.exemptFromSuper }.reduce(0) { $0 + $1.amount }
        let ote = ordinary + weekend + publicHoliday + superableExtras
        let superAmount = round2(ote * slip.superRate / 100)

        let deductions = round2(slip.otherDeductions + slip.salarySacrifice)
        let net = round2(gross - slip.payg - deductions)

        return Totals(
            ordinaryAmount: ordinary,
            weekendAmount: weekend,
            publicHolidayAmount: publicHoliday,
            overtimeAmount: overtime,
            extrasAmount: extras,
            gross: gross,
            tax: round2(slip.payg),
            deductions: deductions,
            superAmount: superAmount,
            net: net,
            totalHours: slip.ordinaryHours + slip.weekendHours + slip.publicHolidayHours + slip.overtimeHours
        )
    }

    /// Weekly earnings PAYG withholding is calculated on: ordinary + weekend +
    /// PH + overtime + extras NOT flagged `exemptFromTax`, less salary
    /// sacrifice (a pre-tax deduction). `otherDeductions` is left out — it's
    /// typically post-tax and the model doesn't distinguish, so a manager
    /// adjusts `payg` manually if a specific deduction needs pre-tax treatment.
    static func taxableEarnings(for slip: Payslip) -> Double {
        let taxableExtras = slip.extraEarnings.filter { !$0.exemptFromTax }.reduce(0) { $0 + $1.amount }
        let ordinary = slip.ordinaryHours * slip.baseHourlyRate
        let weekend = slip.weekendHours * slip.weekendRate
        let publicHoliday = slip.publicHolidayHours * slip.publicHolidayRate
        let overtime = slip.overtimeHours * slip.overtimeRate
        return max(0, round2(ordinary + weekend + publicHoliday + overtime + taxableExtras - slip.salarySacrifice))
    }

    /// The ATO-formula PAYG withholding for this payslip (Australian
    /// resident, weekly pay period; see `PAYGCalculator`). This is what
    /// generation seeds `payg` with and what the manager "Recalculate" action
    /// re-derives — `payg` itself stays a plain stored/editable field so a
    /// manager can override for HELP/STSL debt, foreign residency, etc.
    static func calculatedPAYG(for slip: Payslip) -> Double {
        PAYGCalculator.weeklyWithholding(taxableEarnings: taxableEarnings(for: slip),
                                         claimsTaxFreeThreshold: slip.claimsTaxFreeThreshold)
    }

    /// Field-level diff between two payslip snapshots — one `PayslipAuditEntry`
    /// per manager-editable field that changed, `[]` if nothing did. Powers
    /// `RosterRepository.savePayslip`'s audit trail. Numeric fields are
    /// compared post-`round2` so float noise from arithmetic elsewhere (e.g.
    /// the quantity×rate sync on an earnings row) never produces a spurious
    /// entry. Excludes `payDate` (not wired to any editable control today)
    /// and every snapshot-only/system field (staffName, status, generatedAt,
    /// audit itself, etc).
    static func auditDiff(from old: Payslip, to new: Payslip, editor: AppUser) -> [PayslipAuditEntry] {
        func hours(_ v: Double) -> String { String(format: "%.2f", v) }
        func money(_ v: Double) -> String { RosterFormat.money(v) }
        func percent(_ v: Double) -> String { String(format: "%g%%", v) }
        func yesNo(_ v: Bool) -> String { v ? "Yes" : "No" }
        func text(_ v: String) -> String { v }

        var entries: [PayslipAuditEntry] = []
        func log<T: Equatable>(_ field: String, _ oldValue: T, _ newValue: T, _ format: (T) -> String) {
            guard oldValue != newValue else { return }
            let previous = format(oldValue), updated = format(newValue)
            entries.append(PayslipAuditEntry(
                action: "edited", userId: editor.id, userName: editor.fullName,
                detail: "\(field): \(previous) → \(updated)",
                field: field, previousValue: previous, newValue: updated))
        }

        log("Base hourly rate", round2(old.baseHourlyRate), round2(new.baseHourlyRate), money)
        log("Ordinary hours", round2(old.ordinaryHours), round2(new.ordinaryHours), hours)
        log("Weekend hours", round2(old.weekendHours), round2(new.weekendHours), hours)
        log("Weekend rate", round2(old.weekendRate), round2(new.weekendRate), money)
        log("Public holiday hours", round2(old.publicHolidayHours), round2(new.publicHolidayHours), hours)
        log("Public holiday rate", round2(old.publicHolidayRate), round2(new.publicHolidayRate), money)
        log("Overtime hours", round2(old.overtimeHours), round2(new.overtimeHours), hours)
        log("Overtime rate", round2(old.overtimeRate), round2(new.overtimeRate), money)
        log("Claims tax-free threshold", old.claimsTaxFreeThreshold, new.claimsTaxFreeThreshold, yesNo)
        log("PAYG withholding", round2(old.payg), round2(new.payg), money)
        log("Other deductions", round2(old.otherDeductions), round2(new.otherDeductions), money)
        log("Salary sacrifice", round2(old.salarySacrifice), round2(new.salarySacrifice), money)
        log("Deduction notes", old.deductionNotes, new.deductionNotes, text)
        log("Super guarantee", round2(old.superRate), round2(new.superRate), percent)
        log("Notes", old.notes, new.notes, text)

        entries.append(contentsOf: extraEarningsDiff(from: old.extraEarnings, to: new.extraEarnings, editor: editor))
        return entries
    }

    /// Row-level diff for `extraEarnings`, matched by id: added rows, removed
    /// rows, and rows present in both whose amount changed. Diffs on `amount`
    /// alone (not `quantity`/`rate` separately) — a quantity edit already
    /// resyncs `amount` (see `ManagerPayslipDetailSheet.extraBinding`), so
    /// diffing both would double-report the same edit.
    private static func extraEarningsDiff(from old: [PayslipEarning], to new: [PayslipEarning],
                                          editor: AppUser) -> [PayslipAuditEntry] {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        var entries: [PayslipAuditEntry] = []

        for earning in new where oldByID[earning.id] == nil {
            let amount = RosterFormat.money(round2(earning.amount))
            entries.append(PayslipAuditEntry(
                action: "edited", userId: editor.id, userName: editor.fullName,
                detail: "Added earnings row: \(earning.name) (\(amount))",
                field: "Earnings: \(earning.name)", newValue: amount))
        }
        for earning in old where newByID[earning.id] == nil {
            let amount = RosterFormat.money(round2(earning.amount))
            entries.append(PayslipAuditEntry(
                action: "edited", userId: editor.id, userName: editor.fullName,
                detail: "Removed earnings row: \(earning.name)",
                field: "Earnings: \(earning.name)", previousValue: amount))
        }
        for newEarning in new {
            guard let oldEarning = oldByID[newEarning.id],
                  round2(oldEarning.amount) != round2(newEarning.amount) else { continue }
            let previous = RosterFormat.money(round2(oldEarning.amount))
            let updated = RosterFormat.money(round2(newEarning.amount))
            entries.append(PayslipAuditEntry(
                action: "edited", userId: editor.id, userName: editor.fullName,
                detail: "\(newEarning.name): \(previous) → \(updated)",
                field: "Earnings: \(newEarning.name)", previousValue: previous, newValue: updated))
        }
        return entries
    }

    /// Splits approved worked hours into ordinary (Mon–Fri) vs weekend
    /// (Sat/Sun) buckets by shift date key.
    static func hoursBuckets(workedHoursByDate: [String: Double]) -> (ordinary: Double, weekend: Double) {
        var ordinary = 0.0, weekend = 0.0
        for (dateKey, hours) in workedHoursByDate {
            guard let date = RosterCalendar.dateFromKey(dateKey) else { continue }
            let weekday = RosterCalendar.calendar.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 { weekend += hours } else { ordinary += hours }
        }
        return (ordinary, weekend)
    }

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

/// Australian PAYG withholding — ATO Schedule 1, "Statement of formulas for
/// calculating amounts to be withheld" (NAT 1004), weekly earnings, resident
/// individual rates. Coefficients below are effective from 1 July 2026
/// (2026–27 income year — the 2025–26 16% band dropped to 15%).
///
/// Payslip pay periods are always a Mon–Sun week (see `PayrollModels.swift`
/// header), so only the weekly scales are implemented; there's no
/// fortnightly/monthly conversion to do.
///
/// Only resident Scale 1 (no tax-free threshold) and Scale 2 (threshold
/// claimed) are modelled — the two declarations that cover the vast majority
/// of staff. HELP/STSL debt, foreign residency, and seniors/pensioner offsets
/// aren't in the ATO Schedule 1 formula either (they're separate schedules) —
/// a manager overrides `payg` manually for those, same as before this existed.
enum PAYGCalculator {
    /// One coefficient band of the ATO formula `withholding = a×x − b`, valid
    /// while `x` (see `weeklyWithholding`) is below `upperBound`.
    private struct Band {
        let upperBound: Double
        let a: Double
        let b: Double
    }

    /// Scale 1 — tax-free threshold NOT claimed.
    private static let scale1: [Band] = [
        Band(upperBound: 371, a: 0.2084, b: 11.0185),
        Band(upperBound: 515, a: 0.1790, b: 0.1066),
        Band(upperBound: 932, a: 0.3227, b: 74.1674),
        Band(upperBound: 2246, a: 0.3200, b: 71.6508),
        Band(upperBound: 3303, a: 0.3900, b: 228.8816),
        Band(upperBound: .infinity, a: 0.4700, b: 493.1893),
    ]

    /// Scale 2 — tax-free threshold claimed (the common case: this is the
    /// staff member's main or only job).
    private static let scale2: [Band] = [
        Band(upperBound: 362, a: 0, b: 0),
        Band(upperBound: 538, a: 0.1500, b: 54.3462),
        Band(upperBound: 673, a: 0.2500, b: 108.2135),
        Band(upperBound: 721, a: 0.1700, b: 54.3473),
        Band(upperBound: 865, a: 0.1790, b: 60.8377),
        Band(upperBound: 1282, a: 0.3227, b: 185.1935),
        Band(upperBound: 2596, a: 0.3200, b: 181.7319),
        Band(upperBound: 3653, a: 0.3900, b: 363.4627),
        Band(upperBound: .infinity, a: 0.4700, b: 655.7704),
    ]

    /// Weekly PAYG withholding for `taxableEarnings` (dollars and cents).
    /// Mirrors the ATO's documented method exactly: truncate earnings to
    /// whole dollars, add 99 cents (`x`), apply the matching band's linear
    /// formula, then round to the nearest dollar — an exact 50 cents rounds
    /// up (`.rounded()`'s away-from-zero default does this for positives).
    static func weeklyWithholding(taxableEarnings: Double, claimsTaxFreeThreshold: Bool) -> Double {
        guard taxableEarnings > 0 else { return 0 }
        let x = taxableEarnings.rounded(.down) + 0.99
        let bands = claimsTaxFreeThreshold ? scale2 : scale1
        guard let band = bands.first(where: { x < $0.upperBound }) else { return 0 }
        return max(0, (band.a * x - band.b).rounded())
    }
}

/// Formatting shared by payroll UI + PDF.
extension RosterFormat {
    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.locale = Locale(identifier: "en_AU")
        return formatter
    }()

    static func money(_ value: Double) -> String {
        moneyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}
