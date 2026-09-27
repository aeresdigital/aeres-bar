import AppKit

/// The single menu bar item's icon: one small bar per provider, filled up to its usage.
/// Drawn as a template image, so the system tints it like its own icons; the empty track is
/// drawn translucent and survives the tinting.
@MainActor
public enum MeterImage {
    private static var cache: [String: NSImage] = [:]

    /// `levels` holds each provider's usage (0–100), or `nil` for a provider with nothing to show yet.
    public static func template(levels: [Double?], pointSize: CGFloat = 16) -> NSImage {
        let key = levels.map { $0.map { String(Int($0.rounded())) } ?? "-" }.joined(separator: ",") + "@\(pointSize)"
        if let cached = cache[key] { return cached }
        if cache.count > 128 { cache.removeAll() }

        let image = NSImage(size: NSSize(width: width(for: levels.count, pointSize: pointSize), height: pointSize))
        for scale in [1, 2, 3] {
            if let rep = render(levels: levels, pointSize: pointSize, scale: CGFloat(scale)) {
                image.addRepresentation(rep)
            }
        }
        image.isTemplate = true
        image.accessibilityDescription = "Uso dos provedores"
        cache[key] = image
        return image
    }

    /// Bars stay at least 1.5 pt wide and 1 pt apart: past six providers the image grows wider
    /// instead of squeezing them.
    static func width(for count: Int, pointSize: CGFloat) -> CGFloat {
        let needed = CGFloat(count) * 1.5 + CGFloat(max(count - 1, 0)) + 2
        return max(pointSize, needed.rounded(.up))
    }

    static func render(levels: [Double?], pointSize: CGFloat, scale: CGFloat) -> NSBitmapImageRep? {
        let pointWidth = width(for: levels.count, pointSize: pointSize)
        let pixels = Int((pointSize * scale).rounded())
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((pointWidth * scale).rounded()),
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let graphics = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: pointWidth, height: pointSize)

        // With nothing to show yet, draw three empty tracks so the item keeps its shape.
        let bars: [Double?] = levels.isEmpty ? [nil, nil, nil] : levels
        let count = CGFloat(bars.count)
        let gap: CGFloat = bars.count > 4 ? 1 : 1.5
        let width = min(4, max(1.5, (pointWidth - 2 - gap * (count - 1)) / count))
        let bottom: CGFloat = 1.5
        let height = pointSize - 3
        var x = (pointWidth - (width * count + gap * (count - 1))) / 2

        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        for level in bars {
            let track = CGRect(x: x, y: bottom, width: width, height: height)
            context.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)
            context.addPath(CGPath(roundedRect: track, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
            context.fillPath()
            if let level {
                let filled = max(width, height * CGFloat(min(max(level, 0), 100)) / 100)
                context.setFillColor(NSColor.black.cgColor)
                context.addPath(
                    CGPath(
                        roundedRect: CGRect(x: x, y: bottom, width: width, height: filled),
                        cornerWidth: width / 2,
                        cornerHeight: width / 2,
                        transform: nil
                    )
                )
                context.fillPath()
            }
            x += width + gap
        }
        context.flush()
        return rep
    }
}
