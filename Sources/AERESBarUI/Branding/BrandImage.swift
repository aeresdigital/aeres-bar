import AERESBarCore
import AppKit
import SwiftUI

/// Renders the marks as monochrome template images for the menu bar, where the system tints
/// them to match the menu bar appearance, like its own icons.
@MainActor
public enum BrandImage {
    private static var cache: [String: NSImage] = [:]

    /// A template image whose mark fits a `pointSize` square, with 1×, 2× and 3× bitmaps.
    public static func template(for provider: ProviderID, pointSize: CGFloat = 16) -> NSImage {
        let key = "\(provider.rawValue)@\(pointSize)"
        if let cached = cache[key] { return cached }

        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size)
        for scale in [1, 2, 3] {
            if let rep = render(provider, pointSize: pointSize, scale: CGFloat(scale)) {
                image.addRepresentation(rep)
            }
        }
        image.isTemplate = true
        image.accessibilityDescription = provider.displayName
        cache[key] = image
        return image
    }

    /// Draws the mark in black on transparent, centred and scaled to fit.
    static func render(_ provider: ProviderID, pointSize: CGFloat, scale: CGFloat) -> NSBitmapImageRep? {
        let pixels = Int((pointSize * scale).rounded())
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
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
        rep.size = NSSize(width: pointSize, height: pointSize)

        let outline = BrandMark.path(for: provider)
        let bounds = outline.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let canvas = CGFloat(pixels)
        let fit = canvas / max(bounds.width, bounds.height)

        let context = graphics.cgContext
        // SVG is y-down, Core Graphics y-up: flip, then centre the mark.
        context.translateBy(x: (canvas - bounds.width * fit) / 2, y: (canvas + bounds.height * fit) / 2)
        context.scaleBy(x: fit, y: -fit)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.addPath(outline.cgPath)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath(using: .winding)
        context.flush()
        return rep
    }
}

/// The mark as a SwiftUI shape, scaled to fit its frame.
public struct BrandShape: Shape {
    public let provider: ProviderID

    public init(provider: ProviderID) {
        self.provider = provider
    }

    public func path(in rect: CGRect) -> Path {
        let source = BrandMark.path(for: provider)
        let bounds = source.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: rect.midX - bounds.midX * scale,
            ty: rect.midY - bounds.midY * scale
        )
        return source.applying(transform)
    }
}

/// The colored mark for the panel, or a single-color version.
public struct BrandLogo: View {
    public let provider: ProviderID
    public var tint: Color?

    public init(provider: ProviderID, tint: Color? = nil) {
        self.provider = provider
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let tint {
                BrandShape(provider: provider).fill(tint)
            } else {
                BrandShape(provider: provider).fill(BrandPalette.logoFill(for: provider))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(provider.displayName)
    }
}
