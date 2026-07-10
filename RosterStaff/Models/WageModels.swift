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

/// A classification level within an award (e.g. "Level 2 — Retail Employee",
/// or an age bracket like "Under 17" / "Adult 20+").
struct AwardClassification: Equatable, Identifiable {
    var level: String          // e.g. "2", "U17", "20+"
    var title: String          // e.g. "Retail Employee Level 2", "Under 17"
    var baseHourlyRate: Double // ordinary (Mon–Fri) hourly rate for this level
    /// Weekend & public holiday hourly rate. 0 ⇒ not specified — payroll
    /// generation falls back to its default multipliers of the base rate.
    var weekendHourlyRate: Double

    var id: String { level + title }

    init(level: String, title: String, baseHourlyRate: Double,
         weekendHourlyRate: Double = 0) {
        self.level = level
        self.title = title
        self.baseHourlyRate = baseHourlyRate
        self.weekendHourlyRate = weekendHourlyRate
    }

    init(dict: [String: Any]) {
        self.level = FS.stringValue(dict, "level")
        self.title = FS.stringValue(dict, "title")
        self.baseHourlyRate = FS.double(dict, "baseHourlyRate")
        self.weekendHourlyRate = FS.double(dict, "weekendHourlyRate")
    }

    var asDictionary: [String: Any] {
        ["level": level, "title": title, "baseHourlyRate": baseHourlyRate,
         "weekendHourlyRate": weekendHourlyRate]
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

    /// Owner-supplied Console age-rate table (2026-07): Mon–Fri base rate and
    /// the combined Weekend & Public Holiday rate per age bracket. Offered as
    /// a one-tap prefill in the award editor — the manager still reviews and
    /// saves manually.
    static let consoleTemplateClassifications: [AwardClassification] = [
        AwardClassification(level: "U17", title: "Under 17", baseHourlyRate: 17.50, weekendHourlyRate: 22.83),
        AwardClassification(level: "17", title: "17 years", baseHourlyRate: 18.43, weekendHourlyRate: 24.04),
        AwardClassification(level: "18", title: "18 years", baseHourlyRate: 23.03, weekendHourlyRate: 30.04),
        AwardClassification(level: "19", title: "19 years", baseHourlyRate: 27.64, weekendHourlyRate: 36.05),
        AwardClassification(level: "20+", title: "Adult 20+", baseHourlyRate: 36.85, weekendHourlyRate: 48.07),
    ]
}

/// A pay item ("earnings rate" in Xero terms). For **ordinary hours**, each
/// line is also a **classification level** (level code + M–F / weekend rates)
/// — the award editor no longer carries classifications; they live here.
struct EarningsLine: Identifiable, Equatable {
    let id: String
    var name: String            // internal name, e.g. "Under 17"
    var displayName: String     // shown on payslips (defaults to name)
    var category: EarningsCategory
    var rateType: EarningsRateType
    var multiplier: Double      // used when rateType == .multipleOfOrdinary
    var fixedRate: Double       // $ amount for fixedAmount / ratePerUnit
    var unitName: String        // e.g. "km", "meal" (ratePerUnit only)
    var exemptFromSuper: Bool
    var exemptFromTax: Bool
    var active: Bool
    /// Parent award (optional). Classification-level lines are grouped here.
    var awardId: String?
    /// Classification level code, e.g. "2", "U17", "20+" (ordinary-hours lines).
    var level: String
    /// Mon–Fri ordinary hourly rate for this classification level.
    var baseHourlyRate: Double
    /// Weekend & public holiday hourly rate. 0 ⇒ payroll uses default multipliers.
    var weekendHourlyRate: Double

    static let kind = "earningsLine"

    init(id: String, name: String, displayName: String = "",
         category: EarningsCategory = .ordinaryHours,
         rateType: EarningsRateType = .multipleOfOrdinary,
         multiplier: Double = 1.0, fixedRate: Double = 0, unitName: String = "",
         exemptFromSuper: Bool = false, exemptFromTax: Bool = false,
         active: Bool = true, awardId: String? = nil,
         level: String = "", baseHourlyRate: Double = 0,
         weekendHourlyRate: Double = 0) {
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
        self.awardId = awardId
        self.level = level
        self.baseHourlyRate = baseHourlyRate
        self.weekendHourlyRate = weekendHourlyRate
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
        self.awardId = FS.string(data, "awardId")
        self.level = FS.stringValue(data, "level")
        self.baseHourlyRate = FS.double(data, "baseHourlyRate")
        self.weekendHourlyRate = FS.double(data, "weekendHourlyRate")
        // Legacy docs may only have fixedRate on ordinary-hours lines.
        if self.baseHourlyRate <= 0, self.category == .ordinaryHours, self.fixedRate > 0 {
            self.baseHourlyRate = self.fixedRate
        }
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
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
            "level": level,
            "baseHourlyRate": baseHourlyRate,
            "weekendHourlyRate": weekendHourlyRate,
        ]
        dict["awardId"] = awardId ?? NSNull()
        return dict
    }

    /// Whether this line defines a pay classification level (ordinary hours).
    var isClassificationLevel: Bool {
        guard category == .ordinaryHours else { return false }
        return !level.trimmingCharacters(in: .whitespaces).isEmpty
            || baseHourlyRate > 0
            || fixedRate > 0
    }

    /// Classification title for payslips / pickers.
    var classificationTitle: String {
        let title = displayName.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? name : title
    }

    /// Short human description of the rate, e.g. "1.5× ordinary" or "$36.85/h M–F".
    var rateSummary: String {
        if isClassificationLevel {
            let base = baseHourlyRate > 0 ? baseHourlyRate : fixedRate
            if base > 0 {
                if weekendHourlyRate > 0 {
                    return String(format: "$%.2f M–F · $%.2f Wknd/PH", base, weekendHourlyRate)
                }
                return String(format: "$%.2f/h", base)
            }
        }
        switch rateType {
        case .multipleOfOrdinary:
            return String(format: "%.2g× ordinary", multiplier)
        case .fixedAmount:
            return String(format: "$%.2f fixed", fixedRate)
        case .ratePerUnit:
            return String(format: "$%.2f/%@", fixedRate, unitName.isEmpty ? "unit" : unitName)
        }
    }

    /// Build an editable earnings line from a legacy award classification row.
    static func from(classification: AwardClassification, awardId: String) -> EarningsLine {
        EarningsLine(
            id: "",
            name: classification.title,
            displayName: classification.title,
            category: .ordinaryHours,
            rateType: .fixedAmount,
            fixedRate: classification.baseHourlyRate,
            awardId: awardId,
            level: classification.level,
            baseHourlyRate: classification.baseHourlyRate,
            weekendHourlyRate: classification.weekendHourlyRate
        )
    }

    /// Console age-rate rows as earnings lines (one per level).
    static func consoleTemplateLines(awardId: String?) -> [EarningsLine] {
        WageAward.consoleTemplateClassifications.map { classification in
            EarningsLine(
                id: "",
                name: classification.title,
                displayName: classification.title,
                category: .ordinaryHours,
                rateType: .fixedAmount,
                fixedRate: classification.baseHourlyRate,
                awardId: awardId,
                level: classification.level,
                baseHourlyRate: classification.baseHourlyRate,
                weekendHourlyRate: classification.weekendHourlyRate
            )
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
    /// 2. assigned ordinary-hours earnings line matching `classificationLevel`,
    /// 3. legacy award classification on the award doc,
    /// 4. any assigned ordinary-hours line with its own dollar rate.
    /// Returns nil when no source yields a positive rate — callers must
    /// surface that, never silently pay $0.
    func resolvedHourlyRate(award: WageAward?, earningsLines: [EarningsLine] = []) -> Double? {
        if let override = hourlyRateOverride, override > 0 { return override }
        if let level = classificationLevel,
           let line = earningsLines.first(where: {
               $0.active && $0.isClassificationLevel && $0.level == level
                   && (awardId == nil || $0.awardId == nil || $0.awardId == awardId)
           }),
           line.baseHourlyRate > 0 {
            return line.baseHourlyRate
        }
        if let award,
           let level = classificationLevel,
           let classification = award.classifications.first(where: { $0.level == level }),
           classification.baseHourlyRate > 0 {
            return classification.baseHourlyRate
        }
        if let line = earningsLines.first(where: {
            earningsLineIds.contains($0.id) && $0.active
                && $0.category == .ordinaryHours
                && $0.rateType != .multipleOfOrdinary
                && ($0.baseHourlyRate > 0 || $0.fixedRate > 0)
        }) {
            return line.baseHourlyRate > 0 ? line.baseHourlyRate : line.fixedRate
        }
        return nil
    }

    /// Weekend/PH rate for payslip generation from the assigned classification.
    func resolvedWeekendRate(award: WageAward?, earningsLines: [EarningsLine] = []) -> Double? {
        if let level = classificationLevel,
           let line = earningsLines.first(where: {
               $0.active && $0.isClassificationLevel && $0.level == level
                   && (awardId == nil || $0.awardId == nil || $0.awardId == awardId)
           }),
           line.weekendHourlyRate > 0 {
            return line.weekendHourlyRate
        }
        if let award,
           let level = classificationLevel,
           let classification = award.classifications.first(where: { $0.level == level }),
           classification.weekendHourlyRate > 0 {
            return classification.weekendHourlyRate
        }
        return nil
    }

    /// Classification title for payslip snapshot.
    func resolvedClassificationTitle(award: WageAward?, earningsLines: [EarningsLine] = []) -> String {
        if let level = classificationLevel,
           let line = earningsLines.first(where: {
               $0.isClassificationLevel && $0.level == level
                   && (awardId == nil || $0.awardId == nil || $0.awardId == awardId)
           }) {
            return line.classificationTitle
        }
        if let award,
           let level = classificationLevel,
           let classification = award.classifications.first(where: { $0.level == level }) {
            return classification.title
        }
        return ""
    }
}
