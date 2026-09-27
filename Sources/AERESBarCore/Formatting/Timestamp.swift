import Foundation

/// Fast parser for the RFC 3339 timestamps found in provider APIs and logs
/// ("2026-09-27T02:52:34.699Z", "2026-09-27T08:10:00.036849+00:00", "…+0530").
///
/// Log scanning parses tens of thousands of timestamps on first launch, which is why this
/// avoids `ISO8601DateFormatter` and its handling quirks with 6-digit fractions.
public enum Timestamp {
    public static func parse(_ string: String?) -> Date? {
        guard var string, !string.isEmpty else { return nil }
        return string.withUTF8 { parse(UnsafeRawBufferPointer($0)) }
    }

    public static func parse(_ bytes: UnsafeRawBufferPointer) -> Date? {
        let count = bytes.count
        guard count >= 19 else { return nil }

        func digits(_ start: Int, _ length: Int) -> Int? {
            guard start >= 0, start + length <= count else { return nil }
            var value = 0
            for index in start..<(start + length) {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }

        guard let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2),
            let hour = digits(11, 2), let minute = digits(14, 2), let second = digits(17, 2),
            (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61
        else { return nil }

        var parts = tm()
        parts.tm_year = Int32(year - 1900)
        parts.tm_mon = Int32(month - 1)
        parts.tm_mday = Int32(day)
        parts.tm_hour = Int32(hour)
        parts.tm_min = Int32(minute)
        parts.tm_sec = Int32(second)
        var epoch = Double(timegm(&parts))

        var index = 19
        if index < count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            while index < count, bytes[index] >= 48, bytes[index] <= 57 {
                epoch += Double(bytes[index] - 48) * scale
                scale /= 10
                index += 1
            }
        }
        if index < count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
            let sign: Double = bytes[index] == UInt8(ascii: "+") ? 1 : -1
            if let offsetHours = digits(index + 1, 2) {
                // "+05:30" or "+0530"
                let offsetMinutes = digits(index + 4, 2) ?? digits(index + 3, 2) ?? 0
                epoch -= sign * Double(offsetHours * 3_600 + offsetMinutes * 60)
            }
        }
        return Date(timeIntervalSince1970: epoch)
    }
}
