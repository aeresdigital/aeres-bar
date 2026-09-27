import Foundation

/// Helpers for loosely typed `JSONSerialization` output. Provider APIs change shape often,
/// so parsers read what they need and ignore the rest instead of failing on a strict schema.
enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    static func int(_ value: Any?) -> Int {
        double(value).map { Int($0) } ?? 0
    }

    static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    /// Non-empty string or `nil`.
    static func string(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    static func dict(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }
}

enum JWT {
    /// Reads the `exp` claim without verifying the signature: it only tells us when to stop trying.
    static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !base64.count.isMultiple(of: 4) { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
            let claims = JSON.object(data),
            let exp = JSON.double(claims["exp"])
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
