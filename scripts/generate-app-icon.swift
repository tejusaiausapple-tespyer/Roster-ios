import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF)/255,
            green: CGFloat((hex >> 8) & 0xFF)/255,
            blue: CGFloat(hex & 0xFF)/255, alpha: a)
}

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func drawArt(_ ctx: CGContext) {
    // Background: deep indigo diagonal gradient
    let bg = CGGradient(colorsSpace: space,
        colors: [color(0x150E3D), color(0x2E1A8F), color(0x4338CA)] as CFArray,
        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

    // Soft radial glow upper-left
    let glow = CGGradient(colorsSpace: space,
        colors: [color(0x818CF8, 0.55), color(0x818CF8, 0)] as CFArray,
        locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 280, y: 800), startRadius: 0,
                           endCenter: CGPoint(x: 280, y: 800), endRadius: 700, options: [])

    // Shift bars: (x, y, width, gradient colors)
    let barH: CGFloat = 158
    let bars: [(CGFloat, CGFloat, CGFloat, UInt32, UInt32)] = [
        (150, 668, 460, 0x34D399, 0x0EA5A4),   // mint/teal
        (300, 433, 574, 0x38BDF8, 0x2563EB),   // sky/blue
        (208, 198, 400, 0xFBBF24, 0xF97316),   // amber/orange
    ]

    for (x, y, w, c1, c2) in bars {
        let rect = CGRect(x: x, y: y, width: w, height: barH)
        let path = CGPath(roundedRect: rect, cornerWidth: barH/2, cornerHeight: barH/2, transform: nil)

        // shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: color(0x000000, 0.38))
        ctx.addPath(path)
        ctx.setFillColor(color(c2))
        ctx.fillPath()
        ctx.restoreGState()

        // gradient fill
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let g = CGGradient(colorsSpace: space, colors: [color(c1), color(c2)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        // glossy top highlight
        let hl = CGGradient(colorsSpace: space,
            colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(hl, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.minX, y: rect.midY), options: [])
        ctx.restoreGState()

        // staff avatar dot at the leading end
        let pad: CGFloat = 22
        let d = barH - pad*2
        let dot = CGRect(x: rect.minX + pad, y: rect.minY + pad, width: d, height: d)
        ctx.setFillColor(color(0xFFFFFF, 0.94))
        ctx.fillEllipse(in: dot)
        // tiny person glyph inside dot (head + shoulders) in bar's dark color
        ctx.setFillColor(color(c2))
        let cx = dot.midX, cy = dot.midY
        let headR = d * 0.16
        ctx.fillEllipse(in: CGRect(x: cx - headR, y: cy + d*0.06, width: headR*2, height: headR*2))
        let shW = d * 0.52, shH = d * 0.30
        let sh = CGPath(roundedRect: CGRect(x: cx - shW/2, y: cy - d*0.34, width: shW, height: shH),
                        cornerWidth: shH/2, cornerHeight: shH/2, transform: nil)
        ctx.addPath(sh); ctx.fillPath()
    }

    // Small clock badge, bottom-right
    let clockR: CGFloat = 118
    let clockC = CGPoint(x: 810, y: 172)
    let clockRect = CGRect(x: clockC.x - clockR, y: clockC.y - clockR, width: clockR*2, height: clockR*2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 38, color: color(0x000000, 0.40))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: clockRect)
    ctx.restoreGState()
    // face ring
    ctx.setStrokeColor(color(0x4338CA))
    ctx.setLineWidth(16)
    ctx.strokeEllipse(in: clockRect.insetBy(dx: 10, dy: 10))
    // hands (roughly 10:10)
    ctx.setStrokeColor(color(0x2E1A8F))
    ctx.setLineCap(.round)
    ctx.setLineWidth(18)
    ctx.move(to: clockC)
    ctx.addLine(to: CGPoint(x: clockC.x - clockR*0.38, y: clockC.y + clockR*0.30))
    ctx.strokePath()
    ctx.setLineWidth(14)
    ctx.move(to: clockC)
    ctx.addLine(to: CGPoint(x: clockC.x + clockR*0.42, y: clockC.y + clockR*0.44))
    ctx.strokePath()
    // center pin
    ctx.setFillColor(color(0x2E1A8F))
    ctx.fillEllipse(in: CGRect(x: clockC.x - 14, y: clockC.y - 14, width: 28, height: 28))
}

func render(size: Int, macStyle: Bool, to url: URL) {
    // The iOS marketing icon must be fully opaque (no alpha channel) or the App
    // Store rejects the upload. macOS icons keep alpha for the squircle margin.
    let alphaInfo: CGImageAlphaInfo = macStyle ? .premultipliedLast : .noneSkipLast
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: alphaInfo.rawValue)!
    let s = CGFloat(size)
    if macStyle {
        // Apple macOS style: squircle-ish rounded rect with ~10% margin, drop shadow
        let inset = s * 0.098
        let rect = CGRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2)
        let radius = rect.width * 0.225
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s*0.012), blur: s*0.03, color: color(0x000000, 0.30))
        ctx.addPath(path); ctx.setFillColor(color(0x150E3D)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / S, y: rect.height / S)
        drawArt(ctx)
        ctx.restoreGState()
    } else {
        ctx.scaleBy(x: s / S, y: s / S)
        drawArt(ctx)
    }
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
render(size: 1024, macStyle: false, to: outDir.appendingPathComponent("AppIcon-1024.png"))
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        render(size: px, macStyle: true,
               to: outDir.appendingPathComponent("mac-\(pt)\(scale == 2 ? "@2x" : "").png"))
    }
}
print("done")
