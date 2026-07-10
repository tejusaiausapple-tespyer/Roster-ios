import Foundation

// ─── Wages module data model ──────────────────────────────────────────────────
//
// Modelled on Xero Payroll AU's structure so payroll exports stay compatible
// with Australian employment standards:
//   • Wage Award      — a modern award (e.g. MA000004 General Retail Industry
//                       Award) with classification levels and base hourly rates.
//   • Earnings Line   — a pay item (Xero: "Earnings Rate"): ordinary hours,
//                       overtime multiples, allowances (fixed / per unit),
//                       bonuses, leave — with rate type and super/tax
//                       exemption flags (STP reporting alignment).
//   • StaffWageProfile — per-staff assignment: award + classification +
//                       selected earnings lines (+ optional rate override).
//
// STORAGE + VISIBILITY: every document lives in the `wages` collection with a
// `kind` discriminator. The deployed Firestore rules make `wages` readable and
// writable by MANAGERS ONLY — staff can never see or modify earnings lines or
// assignments, which is a product requirement. Do NOT move any of these fields
// onto `users/{id}` (staff can read their own user doc).
//
// No awards/lines are seeded — managers create and maintain them manually.

/// Xero-style earnings categories (subset relevant to this business).
enum EarningsCategory: String, CaseIterable, Identifiable {
    case ordinaryHours = "ordinary_hours"
    case overtime
    case allowance
    case bonusCommission = "bonus_commission"
    case leave
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ordinaryHours: return "Ordinary Hours"
        case .overtime: return "Overtime"
        case .allowance: return "Allowance"
        case .bonusCommission: return "Bonus / Commission"
        case .leave: return "Leave"
        case .other: return "Other"
        }
    }
}

/// How an earnings line's rate is calculated (mirrors Xero's rate types).
enum EarningsRateType: String, CaseIterable, Identifiable {
    /// e.g. overtime at 1.5× or 2× the ordinary hourly rate.
    case multipleOfOrdinary = "multiple_of_ordinary"
    /// A fixed dollar amount per pay run (e.g. a weekly allowance).
    case fixedAmount = "fixed_amount"
    /// Dollars per unit (e.g. per km, per meal).
    case ratePerUnit = "rate_per_unit"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .multipleOfOrdinary: return "Multiple of ordinary rate"
        case .fixedAmount: return "Fixed amount"
        case .ratePerUnit: return "Rate per unit"
        }
    }
}

/// A classification level within an award (e.g. "Level 2 — Retail Employee").
struct AwardClassification: Equatable, Identifiable {
    var level: String          // e.g. "2"
    var title: String          // e.g. "Retail Employee Level 2"
    var baseHourlyRate: Double // ordinary hourly rate for this level

    var id: String { level + title }

    init(level: String, title: String, baseHourlyRate: Double) {
        self.level = level
        self.title = title
        self.baseHourlyRate = baseHourlyRate
    }

    init(dict: [String: Any]) {
        self.level = FS.stringValue(dict, "level")
        self.title = FS.stringValue(dict, "title")
        self.baseHourlyRate = FS.double(dict, "baseHourlyRate")
    }

    var asDictionary: [String: Any] {
        ["level": level, "title": title, "baseHourlyRate": baseHourlyRate]
    }
}

/// A wage award (modern award) with its classification levels.
struct WageAward: Identifiable, Equatable {
    let id: String
    var name: String            // e.g. "General Retail Industry Award"
    var code: String            // e.g. "MA000004"
    var industry: String        // free text, e.g. "Retail"
    var classifications: [AwardClassification]
    var active: Bool

    static let kind = "award"

    init(id: String, name: String, code: String = "", industry: String = "",
         classifications: [AwardClassification] = [], active: Bool = true) {
        self.id = id
        self.name = name
        self.code = code
        self.industry = industry
        self.classifications = classifications
        self.active = active
    }

    init?(id: String, data: [String: Any]) {
        guard FS.stringValue(data, "kind") == Self.kind else { return nil }
        self.id = id
        self.name = FS.stringValue(data, "name")
        self.code = FS.stringValue(data, "code")
        self.industry = FS.stringValue(data, "industry")
        self.classifications = (data["classifications"] as? [[String: Any]] ?? [])
            .map { AwardClassification(dict: $0) }
        self.active = FS.bool(data, "active", default: true)
    }

    var asDictionary: [String: Any] {
        [
            "kind": Self.kind,
            "name": name,
            "code": code,
            "industry": industry,
            "classifications": classifications.map { $0.asDictionary },
            "active": active,
        ]
    }
}

/// A pay item ("earnings rate" in Xero terms).
struct EarningsLine: Identifiable, Equatable {
    let id: String
    var name: String            // internal name, e.g. "Overtime 1.5x"
    var displayName: String     // shown on payslips (defaults to name)
    var category: EarningsCategory
    var rateType: EarningsRateType
    var multiplier: Double      // used when rateType == .multipleOfOrdinary
    var fixedRate: Double       // $ amount for fixedAmount / ratePerUnit
    var unitName: String        // e.g. "km", "meal" (ratePerUnit only)
    var exemptFromSuper: Bool
    var exemptFromTax: Bool
    var active: Bool

    static let kind = "earningsLine"

    init(id: String, name: String, displayName: String = "",
         category: EarningsCategory = .ordinaryHours,
         rateType: EarningsRateType = .multipleOfOrdinary,
         multiplier: Double = 1.0, fixedRate: Double = 0, unitName: String = "",
         exemptFromSuper: Bool = false, exemptFromTax: Bool = false,
         active: Bool = true) {
        self.id = id
        self.name = name
        self.displayName = displayName.isEmpty ? name : displayName
        self.category = category
        self.rateType = rateType
        self.multiplier = multiplier
        self.fixedRate = fixedRate
        self.unitName = unitName
        self.exemptFromSuper = exemptFromSuper
        self.exemptFromTax = exemptFromTax
        self.active = active
    }

    init?(id: String, data: [String: Any]) {
        guard FS.stringValue(data, "kind") == Self.kind else { return nil }
        self.id = id
        self.name = FS.stringValue(data, "name")
        let display = FS.stringValue(data, "displayName")
        self.displayName = display.isEmpty ? FS.stringValue(data, "name") : display
        self.category = EarningsCategory(rawValue: FS.stringValue(data, "category")) ?? .other
        self.rateType = EarningsRateType(rawValue: FS.stringValue(data, "rateType")) ?? .multipleOfOrdinary
        self.multiplier = FS.double(data, "multiplier", default: 1.0)
        self.fixedRate = FS.double(data, "fixedRate")
        self.unitName = FS.stringValue(data, "unitName")
        self.exemptFromSuper = FS.bool(data, "exemptFromSuper")
        self.exemptFromTax = FS.bool(data, "exemptFromTax")
        self.active = FS.bool(data, "active", default: true)
    }

    var asDictionary: [String: Any] {
        [
            "kind": Self.kind,
            "name": name,
            "displayName": displayName,
            "category": category.rawValue,
            "rateType": rateType.rawValue,
            "multiplier": multiplier,
            "fixedRate": fixedRate,
            "unitName": unitName,
            "exemptFromSuper": exemptFromSuper,
            "exemptFromTax": exemptFromTax,
            "active": active,
        ]
    }

    /// Short human description of the rate, e.g. "1.5× ordinary" or "$0.96/km".
    var rateSummary: String {
        switch rateType {
        case .multipleOfOrdinary:
            return String(format: "%.2g× ordinary", multiplier)
        case .fixedAmount:
            return String(format: "$%.2f fixed", fixedRate)
        case .ratePerUnit:
            return String(format: "$%.2f/%@", fixedRate, unitName.isEmpty ? "unit" : unitName)
        }
    }
}

/// Per-staff wage assignment (doc id: "staff_{staffId}"). Manager-only.
///
/// A profile edit only affects FUTURE payroll: draft generation snapshots the
/// resolved rate/award onto the payslip document, so historical payslips never
/// change unless a manager explicitly regenerates them.
struct StaffWageProfile: Identifiable, Equatable {
    let id: String
    var staffId: String
    var awardId: String?
    var classificationLevel: String?
    var earningsLineIds: [String]
    var hourlyRateOverride: Double?
    /// Overrides the user-doc employment type for payroll purposes (raw
    /// `EmploymentType` value). Empty/nil → fall back to `AppUser.employmentType`.
    var employmentType: String?
    /// Free-form award age group (e.g. "Under 18", "20", "Adult") — some
    /// awards pay junior percentages by age.
    var ageGroup: String?
    /// Date this assignment takes effect (yyyy-MM-dd). Informational — payroll
    /// generation always uses the profile as it stands at generation time.
    var effectiveDate: String?
    /// Superannuation on/off — e.g. under-18 staff working ≤30h/week are not
    /// SG-eligible. OFF ⇒ payslips generate with 0% super and hide the super
    /// block on the PDF.
    var superEnabled: Bool
    /// Optional SG percentage override (e.g. 12.0). nil ⇒ user doc / statutory
    /// default. Ignored when `superEnabled` is false.
    var superRate: Double?
    /// Inactive profiles are skipped by automatic draft payslip generation.
    var active: Bool

    static let kind = "staffProfile"

    static func docId(for staffId: String) -> String { "staff_\(staffId)" }

    init(staffId: String, awardId: String? = nil, classificationLevel: String? = nil,
         earningsLineIds: [String] = [], hourlyRateOverride: Double? = nil,
         employmentType: String? = nil, ageGroup: String? = nil,
         effectiveDate: String? = nil, superEnabled: Bool = true,
         superRate: Double? = nil, active: Bool = true) {
        self.id = Self.docId(for: staffId)
        self.staffId = staffId
        self.awardId = awardId
        self.classificationLevel = classificationLevel
        self.earningsLineIds = earningsLineIds
        self.hourlyRateOverride = hourlyRateOverride
        self.employmentType = employmentType
        self.ageGroup = ageGroup
        self.effectiveDate = effectiveDate
        self.superEnabled = superEnabled
        self.superRate = superRate
        self.active = active
    }

    init?(id: String, data: [String: Any]) {
        guard FS.stringValue(data, "kind") == Self.kind else { return nil }
        self.id = id
        self.staffId = FS.stringValue(data, "staffId")
        self.awardId = FS.string(data, "awardId")
        self.classificationLevel = FS.string(data, "classificationLevel")
        self.earningsLineIds = data["earningsLineIds"] as? [String] ?? []
        self.hourlyRateOverride = (data["hourlyRateOverride"] as? NSNumber)?.doubleValue
        self.employmentType = FS.string(data, "employmentType")
        self.ageGroup = FS.string(data, "ageGroup")
        self.effectiveDate = FS.string(data, "effectiveDate")
        self.superEnabled = FS.bool(data, "superEnabled", default: true)
        self.superRate = (data["superRate"] as? NSNumber)?.doubleValue
        self.active = FS.bool(data, "active", default: true)
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "kind": Self.kind,
            "staffId": staffId,
            "earningsLineIds": earningsLineIds,
            "superEnabled": superEnabled,
            "active": active,
        ]
        dict["awardId"] = awardId ?? NSNull()
        dict["classificationLevel"] = classificationLevel ?? NSNull()
        dict["hourlyRateOverride"] = hourlyRateOverride ?? NSNull()
        dict["employmentType"] = employmentType ?? NSNull()
        dict["ageGroup"] = ageGroup ?? NSNull()
        dict["effectiveDate"] = effectiveDate ?? NSNull()
        dict["superRate"] = superRate ?? NSNull()
        return dict
    }

    /// The SG percentage payroll generation should use (0 when super is off).
    func resolvedSuperRate(userDefault: Double?) -> Double {
        guard superEnabled else { return 0 }
        if let superRate, superRate > 0 { return superRate }
        return userDefault ?? 12.0
    }

    /// The ordinary hourly rate this profile resolves to. Precedence:
    /// 1. explicit rate override,
    /// 2. the award classification's base hourly rate,
    /// 3. an ASSIGNED ordinary-hours earnings line that carries its own
    ///    dollar rate (fixed amount or rate-per-unit — a manager who defines
    ///    "Ordinary Hours $30.00" expects that to BE the wage; a
    ///    multiple-of-ordinary line can't bootstrap a rate from nothing).
    /// Returns nil when no source yields a positive rate — callers must
    /// surface that, never silently pay $0.
    func resolvedHourlyRate(award: WageAward?, earningsLines: [EarningsLine] = []) -> Double? {
        if let override = hourlyRateOverride, override > 0 { return override }
        if let award,
           let level = classificationLevel,
           let classification = award.classifications.first(where: { $0.level == level }),
           classification.baseHourlyRate > 0 {
            return classification.baseHourlyRate
        }
        if let line = earningsLines.first(where: {
            earningsLineIds.contains($0.id) && $0.active
                && $0.category == .ordinaryHours
                && $0.rateType != .multipleOfOrdinary && $0.fixedRate > 0
        }) {
            return line.fixedRate
        }
        return nil
    }
}
