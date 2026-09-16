import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF)/255,
            green: CGFloat((hex >> 8) & 0xFF)/255,
            blue: CGFloat(hex & 0xFF)/255, alpha: a)
}

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = rootURL.appendingPathComponent("docs/branding/rosterra-icon-master.png")
guard let source = NSImage(contentsOf: sourceURL),
      let artwork = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Missing branding source at \(sourceURL.path)")
}

func drawArt(_ ctx: CGContext) {
    ctx.interpolationQuality = .high
    ctx.draw(artwork, in: CGRect(x: 0, y: 0, width: S, height: S))
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
let logoURL = rootURL.appendingPathComponent("Rosterra/Resources/Assets.xcassets/AppLogo.imageset/AppIcon-1024.png")
render(size: 1024, macStyle: false, to: logoURL)
print("Exported iOS icon, macOS icons, and shared AppLogo.")
