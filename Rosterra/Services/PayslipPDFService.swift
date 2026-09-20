import UIKit

/// Renders a payslip as an A4 PDF, Australian payroll layout: company block
/// (logo, name, address, ABN), employee block, hours/earnings table, tax,
/// super and net summary, employer-super footnote.
///
/// Design: monochrome ink on white — no colour fills or tinted text (owner
/// request 2026-07-10). Hierarchy comes from weight, size, letter-spaced
/// section labels, hairlines and whitespace only; the company logo is the
/// single colour element on the page.
///
/// The SAME renderer produces the manager's live preview and every export, so
/// the preview always matches the downloaded/printed document exactly.
enum PayslipPDFService {
    // A4 at 72dpi.
    private static let pageWidth: CGFloat = 595.2
    private static let pageHeight: CGFloat = 841.8
    private static let margin: CGFloat = 52

    private static let ink = UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1)
    private static let secondary = UIColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1)
    private static let rule = UIColor(red: 0.85, green: 0.86, blue: 0.88, alpha: 1)
    private static let panel = UIColor(red: 0.975, green: 0.975, blue: 0.98, alpha: 1)

    private static let rowHeight: CGFloat = 22
    private static let sectionGap: CGFloat = 30

    static func render(_ slip: Payslip, settings: AppSettings) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Payslip \(slip.staffName) \(slip.periodStart)",
            kCGPDFContextCreator as String: settings.companyName,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        let totals = slip.totals

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            // ── Header: logo + company block left, PAYSLIP + status right
            if let logo = UIImage(named: "AppLogo") {
                let logoRect = CGRect(x: margin, y: y, width: 40, height: 40)
                let path = UIBezierPath(roundedRect: logoRect, cornerRadius: 9)
                ctx.cgContext.saveGState()
                path.addClip()
                logo.draw(in: logoRect)
                ctx.cgContext.restoreGState()
            }
            draw(settings.companyName, at: CGPoint(x: margin + 52, y: y + 1),
                 font: .systemFont(ofSize: 16, weight: .bold), color: ink)
            var companyLineY = y + 22
            let addressLine = settings.businessAddress.isEmpty
                ? AppSettings.composedAddress(street: settings.businessStreet,
                                              suburb: settings.businessSuburb,
                                              state: settings.businessState)
                : settings.businessAddress
            if !addressLine.isEmpty {
                draw(addressLine, at: CGPoint(x: margin + 52, y: companyLineY),
                     font: .systemFont(ofSize: 9), color: secondary)
                companyLineY += 13
            }
            if !settings.abn.isEmpty {
                draw("ABN \(RosterFormat.abn(settings.abn))", at: CGPoint(x: margin + 52, y: companyLineY),
                     font: .systemFont(ofSize: 9), color: secondary)
            }
            draw("PAYSLIP", at: CGPoint(x: pageWidth - margin - 160, y: y + 1), width: 160,
                 font: .systemFont(ofSize: 19, weight: .semibold), color: ink,
                 align: .right, kern: 2.5)
            draw(slip.status.label.uppercased(),
                 at: CGPoint(x: pageWidth - margin - 160, y: y + 28), width: 160,
                 font: .systemFont(ofSize: 8, weight: .semibold), color: secondary,
                 align: .right, kern: 1.5)
            y += 58
            hairline(ctx, y: y)
            y += 22

            // ── Employee + period block (two label/value columns)
            let leftPairs: [(String, String)] = [
                ("Employee", slip.staffName),
                ("Employee ID", slip.employeeId.isEmpty ? "—" : slip.employeeId),
                ("Position", slip.position.isEmpty ? "—" : slip.position),
                ("Employment type", EmploymentType(rawValue: slip.employmentType)?.label ?? "—"),
            ]
            let rightPairs: [(String, String)] = [
                ("Pay period", "\(RosterFormat.dateShort(slip.periodStart)) – \(RosterFormat.dateShort(slip.periodEnd))"),
                ("Pay date", RosterFormat.date(slip.payDate)),
                ("Award", slip.awardName.isEmpty ? "—" : awardLabel(slip)),
                ("Classification", slip.classification.isEmpty ? "—" : slip.classification),
            ]
            let colWidth = (pageWidth - margin * 2) / 2
            var leftY = y
            for (label, value) in leftPairs {
                leftY += drawPair(label: label, value: value, x: margin, y: leftY, width: colWidth - 16)
            }
            var rightY = y
            for (label, value) in rightPairs {
                rightY += drawPair(label: label, value: value, x: margin + colWidth + 8, y: rightY, width: colWidth - 8)
            }
            y = max(leftY, rightY) + sectionGap - 12

            // ── Earnings table
            y = sectionTitle(ctx, "EARNINGS", y: y)
            y = tableHeader(ctx, y: y)

            var rows: [(String, String, String, String)] = []
            func hourRow(_ name: String, _ hours: Double, _ rate: Double, _ amount: Double) {
                guard hours > 0 || amount != 0 else { return }
                rows.append((name, RosterFormat.decimalHours(hours),
                             RosterFormat.money(rate), RosterFormat.money(amount)))
            }
            hourRow("Ordinary hours", slip.ordinaryHours, slip.baseHourlyRate, totals.ordinaryAmount)
            hourRow("Weekend hours", slip.weekendHours, slip.weekendRate, totals.weekendAmount)
            hourRow("Public holiday hours", slip.publicHolidayHours, slip.publicHolidayRate, totals.publicHolidayAmount)
            hourRow("Overtime", slip.overtimeHours, slip.overtimeRate, totals.overtimeAmount)
            for extra in slip.extraEarnings where extra.amount != 0 || extra.quantity > 0 {
                rows.append((extra.name,
                             extra.quantity > 0 ? RosterFormat.decimalHours(extra.quantity) : "—",
                             extra.rate > 0 ? RosterFormat.money(extra.rate) : "—",
                             RosterFormat.money(extra.amount)))
            }
            if rows.isEmpty { rows.append(("No earnings recorded", "—", "—", RosterFormat.money(0))) }
            for row in rows {
                y = tableRow(ctx, y: y, row: row)
            }
            y = totalRow(ctx, y: y, label: "Gross earnings", amount: totals.gross)
            y += sectionGap

            // ── Tax & deductions
            y = sectionTitle(ctx, "TAX & DEDUCTIONS", y: y)
            var deductionRows: [(String, String, String, String)] = [
                ("PAYG withholding", "", "", RosterFormat.money(totals.tax)),
            ]
            if slip.salarySacrifice > 0 {
                deductionRows.append(("Salary sacrifice", "", "", RosterFormat.money(slip.salarySacrifice)))
            }
            if slip.otherDeductions > 0 {
                let label = slip.deductionNotes.isEmpty ? "Other deductions" : "Other — \(slip.deductionNotes)"
                deductionRows.append((label, "", "", RosterFormat.money(slip.otherDeductions)))
            }
            for row in deductionRows {
                y = tableRow(ctx, y: y, row: row)
            }
            y = totalRow(ctx, y: y, label: "Total tax & deductions", amount: totals.tax + totals.deductions)
            y += sectionGap

            // ── Superannuation (omitted entirely when super is off — e.g.
            //    under-18 staff not entitled to SG)
            let hasSuper = slip.superRate > 0
            if hasSuper {
                y = sectionTitle(ctx, "SUPERANNUATION", y: y)
                y = tableRow(ctx, y: y, row: (
                    "Employer contribution (SG \(String(format: "%g", slip.superRate))%)",
                    "", "", RosterFormat.money(totals.superAmount)))
                y += sectionGap
            }

            // ── Net pay: bordered panel, dark text — no colour fill
            let panelRect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 46)
            let panelPath = UIBezierPath(roundedRect: panelRect, cornerRadius: 8)
            panel.setFill()
            panelPath.fill()
            rule.setStroke()
            panelPath.lineWidth = 0.8
            panelPath.stroke()
            draw("NET PAY", at: CGPoint(x: margin + 18, y: y + 17),
                 font: .systemFont(ofSize: 10, weight: .semibold), color: ink, kern: 1.5)
            draw(RosterFormat.money(totals.net),
                 at: CGPoint(x: pageWidth - margin - 218, y: y + 13), width: 200,
                 font: .systemFont(ofSize: 17, weight: .bold), color: ink, align: .right)
            y += 46 + 20

            // ── Notes
            if !slip.notes.isEmpty {
                draw("Notes: \(slip.notes)", at: CGPoint(x: margin, y: y),
                     width: pageWidth - margin * 2, font: .systemFont(ofSize: 9), color: secondary)
                y += 28
            }

            // ── Footer (pinned)
            let footerY = pageHeight - margin - 30
            hairline(ctx, y: footerY - 10)
            let footerText = hasSuper
                ? "Superannuation is paid by the employer to the employee's nominated fund and is not included in net pay. This payslip is issued in accordance with the Fair Work Act 2009 record-keeping requirements."
                : "This payslip is issued in accordance with the Fair Work Act 2009 record-keeping requirements."
            draw(footerText,
                 at: CGPoint(x: margin, y: footerY),
                 width: pageWidth - margin * 2, font: .systemFont(ofSize: 7.5), color: secondary)
            draw("Generated by \(settings.companyName) · \(RosterFormat.dateTime(Date()))",
                 at: CGPoint(x: margin, y: footerY + 21),
                 width: pageWidth - margin * 2, font: .systemFont(ofSize: 7.5), color: secondary)
        }
    }

    // MARK: - Pay run register PDF (manager)

    /// Multi-page pay-run PDF for Mac Payroll → Pay run register.
    /// Page 1: period summary + employee register. Page 2+: final hours and
    /// any hour/rate adjustments from each payslip's audit trail.
    static func renderPayRun(_ slips: [Payslip], settings: AppSettings) -> Data {
        let ordered = slips.sorted {
            $0.staffName.localizedCaseInsensitiveCompare($1.staffName) == .orderedAscending
        }
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        let periodLabel: String
        if let first = ordered.first {
            periodLabel = "\(RosterFormat.dateShort(first.periodStart)) – \(RosterFormat.dateShort(first.periodEnd))"
        } else {
            periodLabel = "Pay run"
        }
        format.documentInfo = [
            kCGPDFContextTitle as String: "Pay run \(periodLabel)",
            kCGPDFContextCreator as String: settings.companyName,
        ]

        let runTotals = ordered.reduce(
            PayrollCalculator.Totals(
                ordinaryAmount: 0, weekendAmount: 0, publicHolidayAmount: 0,
                overtimeAmount: 0, extrasAmount: 0, gross: 0, tax: 0,
                deductions: 0, superAmount: 0, net: 0, totalHours: 0
            )
        ) { result, slip in
            let value = slip.totals
            return PayrollCalculator.Totals(
                ordinaryAmount: result.ordinaryAmount + value.ordinaryAmount,
                weekendAmount: result.weekendAmount + value.weekendAmount,
                publicHolidayAmount: result.publicHolidayAmount + value.publicHolidayAmount,
                overtimeAmount: result.overtimeAmount + value.overtimeAmount,
                extrasAmount: result.extrasAmount + value.extrasAmount,
                gross: result.gross + value.gross,
                tax: result.tax + value.tax,
                deductions: result.deductions + value.deductions,
                superAmount: result.superAmount + value.superAmount,
                net: result.net + value.net,
                totalHours: result.totalHours + value.totalHours
            )
        }

        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { ctx in
            // ── Page 1: pay run detail / register
            ctx.beginPage()
            var y = drawPayRunHeader(ctx, settings: settings, title: "PAY RUN",
                                     subtitle: periodLabel.uppercased())
            y += 8

            let summaryPairs: [(String, String)] = [
                ("Employees", "\(ordered.count)"),
                ("Total hours", RosterFormat.decimalHours(runTotals.totalHours)),
                ("Gross wages", RosterFormat.money(runTotals.gross)),
                ("PAYG withholding", RosterFormat.money(runTotals.tax)),
                ("Employer super", RosterFormat.money(runTotals.superAmount)),
                ("Net pay", RosterFormat.money(runTotals.net)),
            ]
            y = sectionTitle(ctx, "PERIOD TOTALS", y: y)
            let colWidth = (pageWidth - margin * 2) / 2
            var leftY = y
            var rightY = y
            for (index, pair) in summaryPairs.enumerated() {
                if index % 2 == 0 {
                    leftY += drawPair(label: pair.0, value: pair.1, x: margin, y: leftY, width: colWidth - 16)
                } else {
                    rightY += drawPair(label: pair.0, value: pair.1, x: margin + colWidth + 8, y: rightY, width: colWidth - 8)
                }
            }
            y = max(leftY, rightY) + sectionGap - 12

            y = sectionTitle(ctx, "PAY RUN REGISTER", y: y)
            y = payRunRegisterHeader(ctx, y: y)
            let pageBottom = pageHeight - margin - 40
            for slip in ordered {
                if y + 22 > pageBottom {
                    drawPageFooter(settings: settings, label: "Pay run register · \(periodLabel)")
                    ctx.beginPage()
                    y = drawPayRunHeader(ctx, settings: settings, title: "PAY RUN",
                                         subtitle: "\(periodLabel.uppercased()) · CONTINUED")
                    y = sectionTitle(ctx, "PAY RUN REGISTER", y: y)
                    y = payRunRegisterHeader(ctx, y: y)
                }
                y = payRunRegisterRow(ctx, y: y, slip: slip)
            }
            drawPageFooter(settings: settings, label: "Pay run register · \(periodLabel)")

            // ── Page 2+: hours + adjustments per staff
            ctx.beginPage()
            y = drawPayRunHeader(ctx, settings: settings, title: "HOURS & ADJUSTMENTS",
                                 subtitle: periodLabel.uppercased())
            y += 4
            draw("Final hours for each employee and any manager edits recorded on the payslip audit trail.",
                 at: CGPoint(x: margin, y: y),
                 width: pageWidth - margin * 2, font: .systemFont(ofSize: 9), color: secondary)
            y += 22

            if ordered.isEmpty {
                draw("No payslips in this pay run.",
                     at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 10), color: secondary)
                drawPageFooter(settings: settings, label: "Hours & adjustments · \(periodLabel)")
            } else {
                for slip in ordered {
                    let blockHeight = estimatedStaffAdjustmentHeight(slip)
                    if y + min(blockHeight, 120) > pageBottom {
                        drawPageFooter(settings: settings, label: "Hours & adjustments · \(periodLabel)")
                        ctx.beginPage()
                        y = drawPayRunHeader(ctx, settings: settings, title: "HOURS & ADJUSTMENTS",
                                             subtitle: "\(periodLabel.uppercased()) · CONTINUED")
                        y += 8
                    }
                    y = drawStaffHoursAndAdjustments(ctx, slip: slip, y: y, pageBottom: pageBottom,
                                                     settings: settings, periodLabel: periodLabel)
                    y += 16
                }
                drawPageFooter(settings: settings, label: "Hours & adjustments · \(periodLabel)")
            }
        }
    }

    /// True when every slip in the run has reached approval (or later publish/archive).
    static func payRunIsPrintable(_ slips: [Payslip]) -> Bool {
        guard !slips.isEmpty else { return false }
        return slips.allSatisfy {
            $0.status == .approved || $0.status == .submitted || $0.status == .archived
        }
    }

    // MARK: Pay-run drawing helpers

    @discardableResult
    private static func drawPayRunHeader(
        _ ctx: UIGraphicsPDFRendererContext,
        settings: AppSettings,
        title: String,
        subtitle: String
    ) -> CGFloat {
        var y = margin
        if let logo = UIImage(named: "AppLogo") {
            let logoRect = CGRect(x: margin, y: y, width: 40, height: 40)
            let path = UIBezierPath(roundedRect: logoRect, cornerRadius: 9)
            ctx.cgContext.saveGState()
            path.addClip()
            logo.draw(in: logoRect)
            ctx.cgContext.restoreGState()
        }
        draw(settings.companyName, at: CGPoint(x: margin + 52, y: y + 1),
             font: .systemFont(ofSize: 16, weight: .bold), color: ink)
        var companyLineY = y + 22
        let addressLine = settings.businessAddress.isEmpty
            ? AppSettings.composedAddress(street: settings.businessStreet,
                                          suburb: settings.businessSuburb,
                                          state: settings.businessState)
            : settings.businessAddress
        if !addressLine.isEmpty {
            draw(addressLine, at: CGPoint(x: margin + 52, y: companyLineY),
                 font: .systemFont(ofSize: 9), color: secondary)
            companyLineY += 13
        }
        if !settings.abn.isEmpty {
            draw("ABN \(RosterFormat.abn(settings.abn))", at: CGPoint(x: margin + 52, y: companyLineY),
                 font: .systemFont(ofSize: 9), color: secondary)
        }
        draw(title, at: CGPoint(x: pageWidth - margin - 200, y: y + 1), width: 200,
             font: .systemFont(ofSize: 16, weight: .semibold), color: ink,
             align: .right, kern: 1.8)
        draw(subtitle, at: CGPoint(x: pageWidth - margin - 200, y: y + 26), width: 200,
             font: .systemFont(ofSize: 8, weight: .semibold), color: secondary,
             align: .right, kern: 1.2)
        y += 58
        hairline(ctx, y: y)
        return y + 20
    }

    private static func drawPageFooter(settings: AppSettings, label: String) {
        let footerY = pageHeight - margin - 24
        if let cg = UIGraphicsGetCurrentContext() {
            cg.setStrokeColor(rule.cgColor)
            cg.setLineWidth(0.7)
            cg.move(to: CGPoint(x: margin, y: footerY - 8))
            cg.addLine(to: CGPoint(x: pageWidth - margin, y: footerY - 8))
            cg.strokePath()
        }
        draw(label, at: CGPoint(x: margin, y: footerY),
             width: pageWidth - margin * 2 - 160, font: .systemFont(ofSize: 7.5), color: secondary)
        draw("\(settings.companyName) · \(RosterFormat.dateTime(Date()))",
             at: CGPoint(x: pageWidth - margin - 200, y: footerY), width: 200,
             font: .systemFont(ofSize: 7.5), color: secondary, align: .right)
    }

    private static let registerColumns: [(String, CGFloat, NSTextAlignment)] = [
        ("Employee", 0.00, .left),
        ("Hours", 0.38, .right),
        ("Gross", 0.50, .right),
        ("PAYG", 0.62, .right),
        ("Super", 0.74, .right),
        ("Net", 0.86, .right),
    ]

    private static func payRunRegisterHeader(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        let width = pageWidth - margin * 2
        for (title, offset, align) in registerColumns {
            draw(title, at: CGPoint(x: margin + width * offset, y: y),
                 width: width * 0.12, font: .systemFont(ofSize: 8, weight: .medium),
                 color: secondary, align: align)
        }
        let bottom = y + 15
        hairline(ctx, y: bottom)
        return bottom + 6
    }

    private static func payRunRegisterRow(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat, slip: Payslip) -> CGFloat {
        let width = pageWidth - margin * 2
        let totals = slip.totals
        let values = [
            slip.staffName,
            RosterFormat.decimalHours(totals.totalHours),
            RosterFormat.money(totals.gross),
            RosterFormat.money(totals.tax),
            RosterFormat.money(totals.superAmount),
            RosterFormat.money(totals.net),
        ]
        for (index, (_, offset, align)) in registerColumns.enumerated() {
            let isName = index == 0
            draw(values[index],
                 at: CGPoint(x: margin + width * offset, y: y),
                 width: isName ? width * 0.36 : width * 0.12,
                 font: .systemFont(ofSize: 9, weight: isName ? .medium : .regular),
                 color: ink, align: align)
        }
        // Status tucked under name on a second micro-line when space allows — keep single row for density.
        return y + 20
    }

    private static func hourAdjustmentEntries(for slip: Payslip) -> [PayslipAuditEntry] {
        slip.audit
            .filter { entry in
                if entry.action == "edited" {
                    let field = (entry.field ?? entry.detail).lowercased()
                    return field.contains("hour") || field.contains("rate")
                        || field.contains("ordinary") || field.contains("weekend")
                        || field.contains("overtime") || field.contains("holiday")
                }
                return entry.action == "regenerated"
            }
            .sorted { $0.at < $1.at }
    }

    private static func estimatedStaffAdjustmentHeight(_ slip: Payslip) -> CGFloat {
        let edits = hourAdjustmentEntries(for: slip)
        return 78 + CGFloat(max(edits.count, 1)) * 16
    }

    @discardableResult
    private static func drawStaffHoursAndAdjustments(
        _ ctx: UIGraphicsPDFRendererContext,
        slip: Payslip,
        y startY: CGFloat,
        pageBottom: CGFloat,
        settings: AppSettings,
        periodLabel: String
    ) -> CGFloat {
        var y = startY
        draw(slip.staffName, at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 11, weight: .semibold), color: ink)
        let meta = [slip.classification, slip.status.label]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        draw(meta, at: CGPoint(x: margin + 220, y: y + 2), width: pageWidth - margin * 2 - 220,
             font: .systemFont(ofSize: 8.5), color: secondary, align: .right)
        y += 18
        hairline(ctx, y: y)
        y += 10

        let hourBits: [(String, Double, Double)] = [
            ("Ordinary", slip.ordinaryHours, slip.baseHourlyRate),
            ("Weekend", slip.weekendHours, slip.weekendRate),
            ("Public holiday", slip.publicHolidayHours, slip.publicHolidayRate),
            ("Overtime", slip.overtimeHours, slip.overtimeRate),
        ]
        let present = hourBits.filter { $0.1 > 0 || $0.2 > 0 }
        if present.isEmpty {
            draw("No hours recorded.", at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 9), color: secondary)
            y += 16
        } else {
            draw("Final hours", at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 8, weight: .semibold), color: secondary, kern: 0.8)
            y += 14
            for (label, hours, rate) in present {
                if y + 16 > pageBottom {
                    drawPageFooter(settings: settings, label: "Hours & adjustments · \(periodLabel)")
                    ctx.beginPage()
                    y = drawPayRunHeader(ctx, settings: settings, title: "HOURS & ADJUSTMENTS",
                                         subtitle: "\(periodLabel.uppercased()) · CONTINUED")
                    draw(slip.staffName + " (continued)", at: CGPoint(x: margin, y: y),
                         font: .systemFont(ofSize: 11, weight: .semibold), color: ink)
                    y += 20
                }
                let line = "\(label): \(RosterFormat.decimalHours(hours)) h × \(RosterFormat.money(rate))"
                draw(line, at: CGPoint(x: margin, y: y),
                     width: pageWidth - margin * 2 - 100, font: .systemFont(ofSize: 9.5), color: ink)
                let amount: Double = {
                    switch label {
                    case "Ordinary": return slip.totals.ordinaryAmount
                    case "Weekend": return slip.totals.weekendAmount
                    case "Public holiday": return slip.totals.publicHolidayAmount
                    case "Overtime": return slip.totals.overtimeAmount
                    default: return hours * rate
                    }
                }()
                draw(RosterFormat.money(amount),
                     at: CGPoint(x: pageWidth - margin - 90, y: y), width: 90,
                     font: .systemFont(ofSize: 9.5, weight: .medium), color: ink, align: .right)
                y += 15
            }
        }

        y += 6
        let edits = hourAdjustmentEntries(for: slip)
        draw("Changed hours / audit", at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 8, weight: .semibold), color: secondary, kern: 0.8)
        y += 14
        if edits.isEmpty {
            draw("No hour or rate changes recorded for this payslip.",
                 at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 9), color: secondary)
            y += 14
        } else {
            for entry in edits {
                if y + 18 > pageBottom {
                    drawPageFooter(settings: settings, label: "Hours & adjustments · \(periodLabel)")
                    ctx.beginPage()
                    y = drawPayRunHeader(ctx, settings: settings, title: "HOURS & ADJUSTMENTS",
                                         subtitle: "\(periodLabel.uppercased()) · CONTINUED")
                    draw(slip.staffName + " (continued)", at: CGPoint(x: margin, y: y),
                         font: .systemFont(ofSize: 11, weight: .semibold), color: ink)
                    y += 20
                }
                let when = RosterFormat.dateTime(entry.at)
                let change: String
                if let field = entry.field, let previous = entry.previousValue, let newValue = entry.newValue {
                    change = "\(field): \(previous) → \(newValue)"
                } else if !entry.detail.isEmpty {
                    change = entry.detail
                } else {
                    change = entry.action.capitalized
                }
                draw("\(when) · \(entry.userName)", at: CGPoint(x: margin, y: y),
                     width: pageWidth - margin * 2, font: .systemFont(ofSize: 8), color: secondary)
                y += 11
                draw(change, at: CGPoint(x: margin, y: y),
                     width: pageWidth - margin * 2, font: .systemFont(ofSize: 9.5), color: ink)
                y += 15
            }
        }

        hairline(ctx, y: y)
        return y + 4
    }

    private static func awardLabel(_ slip: Payslip) -> String {
        slip.awardCode.isEmpty ? slip.awardName : "\(slip.awardName) (\(slip.awardCode))"
    }

    // MARK: Drawing primitives

    private static func draw(_ text: String, at point: CGPoint, width: CGFloat = 320,
                             font: UIFont, color: UIColor, align: NSTextAlignment = .left,
                             kern: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        if kern != 0 { attributes[.kern] = kern }
        (text as NSString).draw(
            in: CGRect(x: point.x, y: point.y, width: width, height: 200),
            withAttributes: attributes)
    }

    /// Draws a label/value pair and returns the row height consumed — long
    /// values (e.g. award names) wrap, and the next row must clear them.
    @discardableResult
    private static func drawPair(label: String, value: String, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let valueFont = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        draw(label, at: CGPoint(x: x, y: y), width: 104,
             font: .systemFont(ofSize: 9), color: secondary)
        draw(value, at: CGPoint(x: x + 104, y: y), width: width - 104,
             font: valueFont, color: ink)
        let used = (value as NSString).boundingRect(
            with: CGSize(width: width - 104, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: valueFont], context: nil).height
        return max(19, ceil(used) + 7)
    }

    private static func hairline(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat,
                                 color: UIColor = rule) {
        ctx.cgContext.setStrokeColor(color.cgColor)
        ctx.cgContext.setLineWidth(0.7)
        ctx.cgContext.move(to: CGPoint(x: margin, y: y))
        ctx.cgContext.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        ctx.cgContext.strokePath()
    }

    /// Letter-spaced section label with a hairline underneath.
    private static func sectionTitle(_ ctx: UIGraphicsPDFRendererContext,
                                     _ title: String, y: CGFloat) -> CGFloat {
        draw(title, at: CGPoint(x: margin, y: y),
             font: .systemFont(ofSize: 9, weight: .semibold), color: ink, kern: 1.8)
        return y + 20
    }

    private static let columns: [(String, CGFloat)] = [
        ("Description", 0), ("Hours/Units", 0.52), ("Rate", 0.68), ("Amount", 0.84)
    ]

    private static func tableHeader(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        let width = pageWidth - margin * 2
        for (title, offset) in columns {
            let isFirst = offset == 0
            draw(title, at: CGPoint(x: margin + width * offset, y: y),
                 width: width * 0.16, font: .systemFont(ofSize: 8, weight: .medium),
                 color: secondary, align: isFirst ? .left : .right)
        }
        let bottom = y + 15
        hairline(ctx, y: bottom)
        return bottom + 7
    }

    private static func tableRow(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat,
                                 row: (String, String, String, String)) -> CGFloat {
        let width = pageWidth - margin * 2
        let values = [row.0, row.1, row.2, row.3]
        for (index, (_, offset)) in columns.enumerated() {
            let isFirst = index == 0
            guard !values[index].isEmpty else { continue }
            draw(values[index],
                 at: CGPoint(x: margin + width * offset, y: y),
                 width: isFirst ? width * 0.5 : width * 0.16,
                 font: .systemFont(ofSize: 9.5, weight: isFirst ? .regular : .medium),
                 color: ink, align: isFirst ? .left : .right)
        }
        return y + rowHeight
    }

    private static func totalRow(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat,
                                 label: String, amount: Double) -> CGFloat {
        hairline(ctx, y: y - 2)
        let width = pageWidth - margin * 2
        let rowY = y + 7
        draw(label, at: CGPoint(x: margin, y: rowY),
             font: .systemFont(ofSize: 9.5, weight: .semibold), color: ink)
        draw(RosterFormat.money(amount),
             at: CGPoint(x: margin + width * 0.84, y: rowY), width: width * 0.16,
             font: .systemFont(ofSize: 10.5, weight: .bold), color: ink, align: .right)
        return rowY + 20
    }
}
