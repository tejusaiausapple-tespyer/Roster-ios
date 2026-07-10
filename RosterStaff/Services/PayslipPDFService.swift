import UIKit

/// Renders a payslip as an A4 PDF, Australian payroll layout: company block
/// (logo, name, address, ABN), employee block, hours/earnings table, tax,
/// super and net summary, employer-super footnote.
///
/// The SAME renderer produces the manager's live preview and every export, so
/// the preview always matches the downloaded/printed document exactly.
enum PayslipPDFService {
    // A4 at 72dpi.
    private static let pageWidth: CGFloat = 595.2
    private static let pageHeight: CGFloat = 841.8
    private static let margin: CGFloat = 48

    private static let ink = UIColor(red: 0.09, green: 0.10, blue: 0.15, alpha: 1)
    private static let secondary = UIColor(red: 0.42, green: 0.44, blue: 0.50, alpha: 1)
    private static let brand = UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1) // indigo
    private static let rule = UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
    private static let rowTint = UIColor(red: 0.96, green: 0.965, blue: 0.98, alpha: 1)

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

            // ── Header: logo + company block, PAYSLIP title on the right
            if let logo = UIImage(named: "AppLogo") {
                let logoRect = CGRect(x: margin, y: y, width: 44, height: 44)
                let path = UIBezierPath(roundedRect: logoRect, cornerRadius: 10)
                ctx.cgContext.saveGState()
                path.addClip()
                logo.draw(in: logoRect)
                ctx.cgContext.restoreGState()
            }
            draw(settings.companyName, at: CGPoint(x: margin + 56, y: y),
                 font: .systemFont(ofSize: 17, weight: .bold), color: ink)
            var companyLineY = y + 22
            let addressLine = settings.businessAddress.isEmpty
                ? AppSettings.composedAddress(street: settings.businessStreet,
                                              suburb: settings.businessSuburb,
                                              state: settings.businessState)
                : settings.businessAddress
            if !addressLine.isEmpty {
                draw(addressLine, at: CGPoint(x: margin + 56, y: companyLineY),
                     font: .systemFont(ofSize: 9), color: secondary)
                companyLineY += 12
            }
            if !settings.abn.isEmpty {
                draw("ABN \(RosterFormat.abn(settings.abn))", at: CGPoint(x: margin + 56, y: companyLineY),
                     font: .systemFont(ofSize: 9), color: secondary)
            }
            draw("PAYSLIP", at: CGPoint(x: pageWidth - margin - 120, y: y), width: 120,
                 font: .systemFont(ofSize: 20, weight: .heavy), color: brand, align: .right)
            let statusText = slip.status.label.uppercased()
            draw(statusText, at: CGPoint(x: pageWidth - margin - 120, y: y + 26), width: 120,
                 font: .systemFont(ofSize: 9, weight: .bold),
                 color: slip.status == .submitted ? brand : secondary, align: .right)
            y += 64
            hairline(ctx, y: y); y += 18

            // ── Employee + period block (two columns)
            let leftPairs: [(String, String)] = [
                ("Employee", slip.staffName),
                ("Employee ID", String(slip.staffId.prefix(12))),
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
            var rowY = y
            for (label, value) in leftPairs {
                drawPair(label: label, value: value, x: margin, y: rowY, width: colWidth - 12)
                rowY += 16
            }
            rowY = y
            for (label, value) in rightPairs {
                drawPair(label: label, value: value, x: margin + colWidth, y: rowY, width: colWidth)
                rowY += 16
            }
            y = rowY + 14
            hairline(ctx, y: y); y += 18

            // ── Earnings table
            draw("EARNINGS", at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 10, weight: .bold), color: brand)
            y += 18
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
            for (index, row) in rows.enumerated() {
                y = tableRow(ctx, y: y, row: row, shaded: index.isMultiple(of: 2))
            }
            y = totalRow(ctx, y: y, label: "GROSS EARNINGS", amount: totals.gross)
            y += 20

            // ── Tax & deductions
            draw("TAX & DEDUCTIONS", at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 10, weight: .bold), color: brand)
            y += 18
            var deductionRows: [(String, String, String, String)] = [
                ("PAYG withholding", "—", "—", RosterFormat.money(totals.tax)),
            ]
            if slip.salarySacrifice > 0 {
                deductionRows.append(("Salary sacrifice", "—", "—", RosterFormat.money(slip.salarySacrifice)))
            }
            if slip.otherDeductions > 0 {
                let label = slip.deductionNotes.isEmpty ? "Other deductions" : "Other — \(slip.deductionNotes)"
                deductionRows.append((label, "—", "—", RosterFormat.money(slip.otherDeductions)))
            }
            for (index, row) in deductionRows.enumerated() {
                y = tableRow(ctx, y: y, row: row, shaded: index.isMultiple(of: 2))
            }
            y = totalRow(ctx, y: y, label: "TOTAL TAX & DEDUCTIONS", amount: totals.tax + totals.deductions)
            y += 20

            // ── Superannuation
            draw("SUPERANNUATION", at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 10, weight: .bold), color: brand)
            y += 18
            y = tableRow(ctx, y: y, row: (
                "Employer contribution (SG \(String(format: "%g", slip.superRate))%)",
                "—", "—", RosterFormat.money(totals.superAmount)), shaded: true)
            y += 20

            // ── Net pay banner
            let bannerRect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 42)
            let banner = UIBezierPath(roundedRect: bannerRect, cornerRadius: 8)
            brand.setFill()
            banner.fill()
            draw("NET PAY", at: CGPoint(x: margin + 16, y: y + 13),
                 font: .systemFont(ofSize: 12, weight: .bold), color: .white)
            draw(RosterFormat.money(totals.net),
                 at: CGPoint(x: pageWidth - margin - 216, y: y + 11), width: 200,
                 font: .systemFont(ofSize: 16, weight: .heavy), color: .white, align: .right)
            y += 62

            // ── Notes
            if !slip.notes.isEmpty {
                draw("Notes: \(slip.notes)", at: CGPoint(x: margin, y: y),
                     width: pageWidth - margin * 2, font: .systemFont(ofSize: 9), color: secondary)
                y += 28
            }

            // ── Footer (pinned)
            let footerY = pageHeight - margin - 30
            hairline(ctx, y: footerY - 8)
            draw("Superannuation is paid by the employer to the employee's nominated fund and is not included in net pay. This payslip is issued in accordance with the Fair Work Act 2009 record-keeping requirements.",
                 at: CGPoint(x: margin, y: footerY),
                 width: pageWidth - margin * 2, font: .systemFont(ofSize: 8), color: secondary)
            draw("Generated by \(settings.companyName) · \(RosterFormat.dateTime(Date()))",
                 at: CGPoint(x: margin, y: footerY + 22),
                 width: pageWidth - margin * 2, font: .systemFont(ofSize: 8), color: secondary)
        }
    }

    private static func awardLabel(_ slip: Payslip) -> String {
        slip.awardCode.isEmpty ? slip.awardName : "\(slip.awardName) (\(slip.awardCode))"
    }

    // MARK: Drawing primitives

    private static func draw(_ text: String, at point: CGPoint, width: CGFloat = 320,
                             font: UIFont, color: UIColor, align: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            in: CGRect(x: point.x, y: point.y, width: width, height: 200),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private static func drawPair(label: String, value: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        draw(label, at: CGPoint(x: x, y: y), width: 110,
             font: .systemFont(ofSize: 9), color: secondary)
        draw(value, at: CGPoint(x: x + 110, y: y), width: width - 110,
             font: .systemFont(ofSize: 9, weight: .semibold), color: ink)
    }

    private static func hairline(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat) {
        ctx.cgContext.setStrokeColor(rule.cgColor)
        ctx.cgContext.setLineWidth(0.7)
        ctx.cgContext.move(to: CGPoint(x: margin, y: y))
        ctx.cgContext.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        ctx.cgContext.strokePath()
    }

    private static let columns: [(String, CGFloat)] = [
        ("Description", 0), ("Hours/Units", 0.52), ("Rate", 0.68), ("Amount", 0.84)
    ]

    private static func tableHeader(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        let width = pageWidth - margin * 2
        for (title, offset) in columns {
            let isFirst = offset == 0
            draw(title, at: CGPoint(x: margin + width * offset, y: y),
                 width: width * 0.16, font: .systemFont(ofSize: 8, weight: .bold),
                 color: secondary, align: isFirst ? .left : .right)
        }
        let bottom = y + 14
        hairline(ctx, y: bottom)
        return bottom + 4
    }

    private static func tableRow(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat,
                                 row: (String, String, String, String), shaded: Bool) -> CGFloat {
        let width = pageWidth - margin * 2
        if shaded {
            rowTint.setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y - 3, width: width, height: 18)).fill()
        }
        let values = [row.0, row.1, row.2, row.3]
        for (index, (_, offset)) in columns.enumerated() {
            let isFirst = index == 0
            draw(values[index],
                 at: CGPoint(x: margin + width * offset, y: y),
                 width: isFirst ? width * 0.5 : width * 0.16,
                 font: .systemFont(ofSize: 9, weight: isFirst ? .regular : .medium),
                 color: ink, align: isFirst ? .left : .right)
        }
        return y + 18
    }

    private static func totalRow(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat,
                                 label: String, amount: Double) -> CGFloat {
        hairline(ctx, y: y)
        let width = pageWidth - margin * 2
        let rowY = y + 6
        draw(label, at: CGPoint(x: margin, y: rowY),
             font: .systemFont(ofSize: 9, weight: .bold), color: ink)
        draw(RosterFormat.money(amount),
             at: CGPoint(x: margin + width * 0.84, y: rowY), width: width * 0.16,
             font: .systemFont(ofSize: 10, weight: .bold), color: ink, align: .right)
        return rowY + 18
    }
}
