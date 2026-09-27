// Desenha o ícone do app num .iconset; o Makefile converte para Resources/AppIcon.icns.
//   swift scripts/make_icon.swift <saída.iconset>
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("erro: \(message)\n".utf8))
    exit(1)
}

/// A dark squircle with three meters in the providers' colors (Claude, Codex, Antigravity).
func render(pixels: Int) -> Data {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ),
        let graphics = NSGraphicsContext(bitmapImageRep: rep)
    else { fail("não foi possível criar o bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // Apple's icon grid: an 824-point squircle centred on a 1024 canvas.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x1B1B22).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x2C2C36), color(0x121217)])?.draw(in: body, angle: -90)

    let meters: [(top: NSColor, bottom: NSColor, level: CGFloat)] = [
        (color(0xF0A07F), color(0xD97757), 0.78),
        (color(0x8FA4F9), color(0x444BF7), 0.52),
        (color(0x7FB0FF), color(0x4285F4), 0.66),
    ]
    let width: CGFloat = 132
    let gap: CGFloat = 70
    let track: CGFloat = 520
    let base: CGFloat = 252
    var x = 512 - (width * 3 + gap * 2) / 2
    for meter in meters {
        color(0xFFFFFF, 0.07).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: base, width: width, height: track), xRadius: width / 2, yRadius: width / 2).fill()
        let fill = NSBezierPath(
            roundedRect: NSRect(x: x, y: base, width: width, height: track * meter.level), xRadius: width / 2, yRadius: width / 2)
        NSGradient(starting: meter.bottom, ending: meter.top)?.draw(in: fill, angle: 90)
        x += width + gap
    }
    NSGradient(colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)])?
        .draw(in: NSBezierPath(roundedRect: NSRect(x: 100, y: 560, width: 824, height: 364), xRadius: 186, yRadius: 186), angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("não foi possível gerar o PNG") }
    return png
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
do {
    try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    let sizes: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, pixels) in sizes {
        try render(pixels: pixels).write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
    }
} catch {
    fail(error.localizedDescription)
}
