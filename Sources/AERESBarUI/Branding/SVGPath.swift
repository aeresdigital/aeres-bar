import CoreGraphics
import Foundation

/// Parses SVG path data (the `d` attribute) into a `CGPath`, in SVG coordinates (y grows downwards).
///
/// Supports every path command — `M L H V C S Q T A Z`, absolute and relative — implicit command
/// repetition and the compact number syntax used by minified SVGs (`.5-.25`, `01` arc flags).
enum SVGPath {
    enum ParseError: Error, Equatable {
        case expectedNumber(offset: Int)
        case expectedFlag(offset: Int)
        case expectedCommand(offset: Int)
    }

    static func parse(_ data: String) throws -> CGPath {
        var scanner = Scanner(bytes: Array(data.utf8))
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: UInt8?

        while !scanner.isAtEnd {
            if let next = scanner.command() {
                command = next
            } else if command == nil {
                throw ParseError.expectedCommand(offset: scanner.index)
            }
            guard let active = command else { throw ParseError.expectedCommand(offset: scanner.index) }
            let relative = active >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            var cubicControl: CGPoint?
            var quadControl: CGPoint?

            switch active | 0x20 {  // lowercase
            case UInt8(ascii: "m"):
                let point = try scanner.point() + origin
                path.move(to: point)
                current = point
                subpathStart = point
                // Further coordinate pairs after a moveto are linetos.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "l"):
                current = try scanner.point() + origin
                path.addLine(to: current)
            case UInt8(ascii: "h"):
                current = CGPoint(x: try scanner.number() + origin.x, y: current.y)
                path.addLine(to: current)
            case UInt8(ascii: "v"):
                current = CGPoint(x: current.x, y: try scanner.number() + origin.y)
                path.addLine(to: current)
            case UInt8(ascii: "c"):
                let control1 = try scanner.point() + origin
                let control2 = try scanner.point() + origin
                current = try scanner.point() + origin
                path.addCurve(to: current, control1: control1, control2: control2)
                cubicControl = control2
            case UInt8(ascii: "s"):
                let control1 = lastCubicControl.map { current.reflecting($0) } ?? current
                let control2 = try scanner.point() + origin
                current = try scanner.point() + origin
                path.addCurve(to: current, control1: control1, control2: control2)
                cubicControl = control2
            case UInt8(ascii: "q"):
                let control = try scanner.point() + origin
                current = try scanner.point() + origin
                path.addQuadCurve(to: current, control: control)
                quadControl = control
            case UInt8(ascii: "t"):
                let control = lastQuadControl.map { current.reflecting($0) } ?? current
                current = try scanner.point() + origin
                path.addQuadCurve(to: current, control: control)
                quadControl = control
            case UInt8(ascii: "a"):
                let rx = try scanner.number()
                let ry = try scanner.number()
                let rotation = try scanner.number()
                let largeArc = try scanner.flag()
                let sweep = try scanner.flag()
                let end = try scanner.point() + origin
                addArc(
                    to: path, from: current, to: end, radii: CGSize(width: rx, height: ry), rotation: rotation, largeArc: largeArc,
                    sweep: sweep)
                current = end
            case UInt8(ascii: "z"):
                path.closeSubpath()
                current = subpathStart
                command = nil  // numbers may not follow a closepath without a new command
            default:
                throw ParseError.expectedCommand(offset: scanner.index)
            }
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
        }
        return path
    }

    /// Converts an SVG elliptical arc to cubic Béziers (SVG 1.1, appendix F.6).
    private static func addArc(
        to path: CGMutablePath,
        from start: CGPoint,
        to end: CGPoint,
        radii: CGSize,
        rotation degrees: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        guard start != end else { return }
        var rx = abs(radii.width)
        var ry = abs(radii.height)
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }
        let phi = degrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        // Scale up radii that are too small to reach the end point.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }

        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coefficient = (largeArc == sweep ? -1 : 1) * (max(0, numerator / denominator)).squareRoot()
        let cxPrime = coefficient * (rx * y1 / ry)
        let cyPrime = coefficient * (-ry * x1 / rx)
        let center = CGPoint(
            x: cosPhi * cxPrime - sinPhi * cyPrime + (start.x + end.x) / 2,
            y: sinPhi * cxPrime + cosPhi * cyPrime + (start.y + end.y) / 2
        )

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1 - cxPrime) / rx, (y1 - cyPrime) / ry)
        var delta = angle((x1 - cxPrime) / rx, (y1 - cyPrime) / ry, (-x1 - cxPrime) / rx, (-y1 - cyPrime) / ry)
        if !sweep && delta > 0 {
            delta -= 2 * .pi
        } else if sweep && delta < 0 {
            delta += 2 * .pi
        }

        // One cubic per quarter turn keeps the approximation error negligible.
        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(segments)
        let handle = 4 / 3 * tan(step / 4)

        func map(_ ux: CGFloat, _ uy: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + rx * ux * cosPhi - ry * uy * sinPhi,
                y: center.y + rx * ux * sinPhi + ry * uy * cosPhi
            )
        }
        for segment in 0..<segments {
            let from = theta1 + CGFloat(segment) * step
            let to = from + step
            let control1 = map(cos(from) - handle * sin(from), sin(from) + handle * cos(from))
            let control2 = map(cos(to) + handle * sin(to), sin(to) - handle * cos(to))
            let point = segment == segments - 1 ? end : map(cos(to), sin(to))
            path.addCurve(to: point, control1: control1, control2: control2)
        }
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool {
            mutating get {
                skipSeparators()
                return index >= bytes.count
            }
        }

        /// Consumes and returns a command letter, if one is next.
        mutating func command() -> UInt8? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            let isLetter =
                (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            // "e"/"E" only ever appear inside numbers, which are consumed whole.
            guard isLetter, byte | 0x20 != UInt8(ascii: "e") else { return nil }
            index += 1
            return byte
        }

        mutating func point() throws -> CGPoint {
            CGPoint(x: try number(), y: try number())
        }

        mutating func number() throws -> CGFloat {
            skipSeparators()
            let start = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
            var sawDigit = false
            var sawDot = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                    sawDigit = true
                } else if byte == UInt8(ascii: ".") && !sawDot {
                    sawDot = true
                } else {
                    break
                }
                index += 1
            }
            if sawDigit, index < bytes.count, bytes[index] | 0x20 == UInt8(ascii: "e") {
                var cursor = index + 1
                if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "-") || bytes[cursor] == UInt8(ascii: "+") { cursor += 1 }
                if cursor < bytes.count, bytes[cursor] >= UInt8(ascii: "0"), bytes[cursor] <= UInt8(ascii: "9") {
                    index = cursor
                    while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") { index += 1 }
                }
            }
            guard sawDigit, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw ParseError.expectedNumber(offset: start)
            }
            return CGFloat(value)
        }

        /// Arc flags are a single "0" or "1" and may be written without separators ("01").
        mutating func flag() throws -> Bool {
            skipSeparators()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "0") || bytes[index] == UInt8(ascii: "1") else {
                throw ParseError.expectedFlag(offset: index)
            }
            defer { index += 1 }
            return bytes[index] == UInt8(ascii: "1")
        }

        private mutating func skipSeparators() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D, UInt8(ascii: ","): index += 1
                default: return
                }
            }
        }
    }
}

extension CGPoint {
    fileprivate static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    /// Reflection of `point` about `self` (smooth curve continuation).
    fileprivate func reflecting(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 2 * x - point.x, y: 2 * y - point.y)
    }
}
