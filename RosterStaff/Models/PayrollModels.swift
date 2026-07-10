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
        case .draft, .underReview: return true
        case .approved, .submitted, .archived: return false
        }
    }

    /// Staff may see the payslip in these states.
    var isStaffVisible: Bool { self == .submitted || self == .archived }
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

    init(action: String, userId: String, userName: String, at: Date = Date(), detail: String = "") {
        self.id = UUID().uuidString
        self.action = action
        self.userId = userId
        self.userName = userName
        self.at = at
        self.detail = detail
    }

    init(dict: [String: Any]) {
        self.id = FS.stringValue(dict, "id", default: UUID().uuidString)
        self.action = FS.stringValue(dict, "action")
        self.userId = FS.stringValue(dict, "userId")
        self.userName = FS.stringValue(dict, "userName")
        self.at = FS.date(dict, "at") ?? Date(timeIntervalSince1970: 0)
        self.detail = FS.stringValue(dict, "detail")
    }

    var asDictionary: [String: Any] {
        ["id": id, "action": action, "userId": userId,
         "userName": userName, "at": at, "detail": detail]
    }
}

/// A weekly payslip. Everything money-related is a stored snapshot.
struct Payslip: Identifiable, Equatable {
    let id: String
    var staffId: String
    var staffName: String        // snapshot
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

    // Deductions (all manager-entered).
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

    init(id: String, staffId: String, staffName: String, position: String = "",
         employmentType: String = "", awardName: String = "", awardCode: String = "",
         classification: String = "", periodStart: String, periodEnd: String,
         payDate: String = "", status: PayslipStatus = .draft,
         baseHourlyRate: Double = 0,
         ordinaryHours: Double = 0, weekendHours: Double = 0, weekendRate: Double = 0,
         publicHolidayHours: Double = 0, publicHolidayRate: Double = 0,
         overtimeHours: Double = 0, overtimeRate: Double = 0,
         extraEarnings: [PayslipEarning] = [],
         payg: Double = 0, otherDeductions: Double = 0, salarySacrifice: Double = 0,
         deductionNotes: String = "", superRate: Double = 12.0, notes: String = "",
         generatedAt: Date? = nil, updatedAt: Date? = nil,
         approvedBy: String? = nil, approvedAt: Date? = nil,
         submittedBy: String? = nil, submittedAt: Date? = nil,
         audit: [PayslipAuditEntry] = []) {
        self.id = id
        self.staffId = staffId
        self.staffName = staffName
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
        self.payg = FS.double(data, "payg")
        self.otherDeductions = FS.double(data, "otherDeductions")
        self.salarySacrifice = FS.double(data, "salarySacrifice")
        self.deductionNotes = FS.stringValue(data, "deductionNotes")
        self.superRate = FS.double(data, "superRate", default: 12.0)
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
