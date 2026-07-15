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
