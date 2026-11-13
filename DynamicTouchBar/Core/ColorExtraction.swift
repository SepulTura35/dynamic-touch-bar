import AppKit

nonisolated enum ColorExtraction {
    /// A vivid, legible tint sampled from artwork — used for the ambient glow, waveform and
    /// progress fill. Downsamples to 12×12 and weights saturated pixels more heavily so a
    /// mostly-grey cover with a red logo yields red, not grey.
    static func tint(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 12
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var r = 0.0, g = 0.0, b = 0.0, totalWeight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[index]) / 255
            let pg = Double(pixels[index + 1]) / 255
            let pb = Double(pixels[index + 2]) / 255
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            let weight = 0.05 + saturation * saturation * maxC
            r += pr * weight; g += pg * weight; b += pb * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        let color = NSColor(srgbRed: r / totalWeight, green: g / totalWeight, blue: b / totalWeight, alpha: 1)
        return legible(color)
    }

    /// Lifts brightness/saturation into a range that reads well on a black OLED.
    static func legible(_ color: NSColor) -> NSColor {
        guard let hsb = color.usingColorSpace(.sRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        hsb.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let saturation = s < 0.12 ? s : min(max(s, 0.45), 0.85)
        return NSColor(hue: h, saturation: saturation, brightness: max(v, 0.82), alpha: 1)
    }
}
