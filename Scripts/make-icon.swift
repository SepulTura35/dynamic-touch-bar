// Generates the app icon set: swift Scripts/make-icon.swift <AppIcon.appiconset dir>
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    // macOS icon grid: 824/1024 body with ~22% corner radius.
    let inset = s * 100 / 1024, body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle); ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.20, green: 0.21, blue: 0.24, alpha: 1), CGColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Touch Bar strip
    let strip = CGRect(x: body.minX + body.width * 0.09, y: body.midY - body.height * 0.075, width: body.width * 0.82, height: body.height * 0.15)
    ctx.addPath(CGPath(roundedRect: strip, cornerWidth: strip.height * 0.28, cornerHeight: strip.height * 0.28, transform: nil))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    // Glow + capsule
    let capsule = CGRect(x: strip.midX - strip.width * 0.27, y: strip.midY - strip.height * 0.36, width: strip.width * 0.54, height: strip.height * 0.72)
    let glow = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 0.55), CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.translateBy(x: capsule.midX, y: capsule.midY); ctx.scaleBy(x: 1, y: 0.32)
    ctx.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: capsule.width * 0.75, options: [])
    ctx.restoreGState()
    let capsulePath = CGPath(roundedRect: capsule, cornerWidth: capsule.height / 2, cornerHeight: capsule.height / 2, transform: nil)
    ctx.saveGState(); ctx.addPath(capsulePath); ctx.clip()
    let cg = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.17, green: 0.17, blue: 0.19, alpha: 1), CGColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(cg, start: CGPoint(x: 0, y: capsule.maxY), end: CGPoint(x: 0, y: capsule.minY), options: [])
    ctx.restoreGState()
    // Artwork dot + waveform
    let art = CGRect(x: capsule.minX + capsule.height * 0.18, y: capsule.minY + capsule.height * 0.18, width: capsule.height * 0.64, height: capsule.height * 0.64)
    let artGrad = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 1, green: 0.42, blue: 0.45, alpha: 1), CGColor(srgbRed: 0.55, green: 0.3, blue: 1, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.saveGState(); ctx.addPath(CGPath(roundedRect: art, cornerWidth: art.width * 0.28, cornerHeight: art.width * 0.28, transform: nil)); ctx.clip()
    ctx.drawLinearGradient(artGrad, start: CGPoint(x: art.minX, y: art.maxY), end: CGPoint(x: art.maxX, y: art.minY), options: [])
    ctx.restoreGState()
    let heights: [CGFloat] = [0.35, 0.7, 0.5, 0.85]
    let barW = capsule.height * 0.09, gap = barW * 0.8
    var x = capsule.maxX - capsule.height * 0.3 - CGFloat(heights.count) * (barW + gap)
    ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.7, blue: 1, alpha: 1))
    for h in heights {
        let bh = capsule.height * 0.6 * h
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: capsule.midY - bh / 2, width: barW, height: bh), cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.fillPath(); x += barW + gap
    }
    ctx.restoreGState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
var images: [String] = []
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try! render(pt * scale).write(to: dir.appendingPathComponent(name))
        images.append("{ \"filename\" : \"\(name)\", \"idiom\" : \"mac\", \"scale\" : \"\(scale)x\", \"size\" : \"\(pt)x\(pt)\" }")
    }
}
let json = "{\n  \"images\" : [\n    " + images.joined(separator: ",\n    ") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons")
