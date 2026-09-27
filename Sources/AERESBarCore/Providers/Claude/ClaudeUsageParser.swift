import Foundation

/// Parses `GET https://api.anthropic.com/api/oauth/usage` — the data behind `/usage` in Claude Code.
public enum ClaudeUsageParser {
    public struct Result: Equatable, Sendable {
        public var windows: [UsageWindow]
        public var details: [DetailRow]
    }

    static let sessionSeconds: Double = 5 * 3_600
    static let weekSeconds: Double = 7 * 86_400

    public static func parse(_ data: Data) -> Result? {
        guard let root = JSON.object(data) else { return nil }
        var windows = windowsFromLimits(JSON.array(root["limits"]))
        if windows.isEmpty { windows = legacyWindows(root) }
        guard !windows.isEmpty else { return nil }
        return Result(windows: windows, details: details(root))
    }

    /// "max" + "default_claude_max_5x" → "Max 5x".
    public static func planName(subscription: String?, tier: String?) -> String? {
        let tier = (tier ?? "").lowercased()
        if tier.contains("max_20x") { return "Max 20x" }
        if tier.contains("max_5x") { return "Max 5x" }
        guard let subscription, !subscription.isEmpty else { return nil }
        switch subscription.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return subscription.capitalized
        }
    }

    /// Current responses list every limit (session, weekly, weekly per model) in `limits`.
    private static func windowsFromLimits(_ limits: [[String: Any]]) -> [UsageWindow] {
        limits.compactMap { limit -> UsageWindow? in
            guard let kind = JSON.string(limit["kind"]) else { return nil }
            let percent = JSON.double(limit["percent"]) ?? JSON.double(limit["utilization"]) ?? 0
            let resetsAt = resetTime(limit["resets_at"])
            let scope = scopeName(JSON.dict(limit["scope"]))

            var window = UsageWindow(id: kind, title: "", usedPercent: percent, resetsAt: resetsAt)
            switch kind {
            case "session":
                window.title = "Sessão (5h)"
                window.windowSeconds = sessionSeconds
                window.isPrimary = true
            case "weekly_all":
                window.title = "Semanal · todos os modelos"
                window.windowSeconds = weekSeconds
            case "weekly_scoped":
                window.id = "weekly_scoped.\(scope ?? "scope")"
                window.title = "Semanal · \(scope ?? "escopo")"
                window.windowSeconds = weekSeconds
            default:
                window.id = scope.map { "\(kind).\($0)" } ?? kind
                window.title = humanize(kind) + (scope.map { " · \($0)" } ?? "")
                switch JSON.string(limit["group"]) {
                case "weekly": window.windowSeconds = weekSeconds
                case "session": window.windowSeconds = sessionSeconds
                default: break
                }
            }
            window.notStarted = percent == 0 && resetsAt == nil
            return window
        }
    }

    /// Older responses had one key per window.
    private static func legacyWindows(_ root: [String: Any]) -> [UsageWindow] {
        let keys: [(key: String, id: String, title: String, seconds: Double, primary: Bool)] = [
            ("five_hour", "session", "Sessão (5h)", sessionSeconds, true),
            ("seven_day", "weekly_all", "Semanal · todos os modelos", weekSeconds, false),
            ("seven_day_opus", "weekly_opus", "Semanal · Opus", weekSeconds, false),
            ("seven_day_sonnet", "weekly_sonnet", "Semanal · Sonnet", weekSeconds, false),
        ]
        return keys.compactMap { entry -> UsageWindow? in
            guard let object = JSON.dict(root[entry.key]), let used = JSON.double(object["utilization"]) else { return nil }
            let resetsAt = resetTime(object["resets_at"])
            return UsageWindow(
                id: entry.id,
                title: entry.title,
                usedPercent: used,
                resetsAt: resetsAt,
                windowSeconds: entry.seconds,
                notStarted: used == 0 && resetsAt == nil,
                isPrimary: entry.primary
            )
        }
    }

    private static func details(_ root: [String: Any]) -> [DetailRow] {
        var rows: [DetailRow] = []

        let breakdown = JSON.array(JSON.dict(root["seven_day_breakdown"])?["rows"])
            .compactMap { row -> (name: String, percent: Double)? in
                guard let name = JSON.string(row["display_name"]), let percent = JSON.double(row["percent"]), percent > 0 else {
                    return nil
                }
                return (name == "Other" ? "Outros" : name, percent)
            }
            .sorted { $0.percent > $1.percent }
        if !breakdown.isEmpty {
            let value = breakdown.map { "\($0.name) \(Formatting.percent($0.percent))" }.joined(separator: " · ")
            rows.append(DetailRow(label: "Semana por produto", value: value))
        }

        if let extra = JSON.dict(root["extra_usage"]) {
            if JSON.bool(extra["is_enabled"]) == true {
                // Credits come in minor units (e.g. cents).
                let divisor = pow(10, Double(JSON.int(extra["decimal_places"])))
                let currency = JSON.string(extra["currency"]) ?? "USD"
                var value = Formatting.money((JSON.double(extra["used_credits"]) ?? 0) / divisor, currency: currency)
                if let limit = JSON.double(extra["monthly_limit"]) {
                    value += " de \(Formatting.money(limit / divisor, currency: currency)) no mês"
                }
                rows.append(DetailRow(label: "Uso extra", value: value))
            } else {
                rows.append(DetailRow(label: "Uso extra", value: "desativado"))
            }
        }
        return rows
    }

    /// Resets fall on whole minutes, but the API adds request-time jitter (e.g. 08:09:59.97).
    private static func resetTime(_ value: Any?) -> Date? {
        guard let date = Timestamp.parse(value as? String) else { return nil }
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    private static func scopeName(_ scope: [String: Any]?) -> String? {
        guard let scope else { return nil }
        if let model = JSON.dict(scope["model"]), let name = JSON.string(model["display_name"]) ?? JSON.string(model["id"]) {
            return name
        }
        if let surface = JSON.dict(scope["surface"]) {
            return JSON.string(surface["display_name"]) ?? JSON.string(surface["id"])
        }
        return JSON.string(scope["surface"])
    }

    private static func humanize(_ kind: String) -> String {
        let words = kind.split(separator: "_").map(String.init)
        guard let first = words.first else { return kind }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }
}
