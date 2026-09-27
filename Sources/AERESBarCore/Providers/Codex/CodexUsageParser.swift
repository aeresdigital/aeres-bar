import Foundation

/// Parses `GET https://chatgpt.com/backend-api/wham/usage` and the `rate_limits` logged in Codex rollouts.
public enum CodexUsageParser {
    public struct Result: Equatable, Sendable {
        public var plan: String?
        public var email: String?
        public var windows: [UsageWindow]
        public var details: [DetailRow]
    }

    public static func parse(_ data: Data, now: Date) -> Result? {
        guard let root = JSON.object(data) else { return nil }
        var result = Result(
            plan: JSON.string(root["plan_type"]).map(planName),
            email: JSON.string(root["email"]),
            windows: [],
            details: []
        )

        if let limit = JSON.dict(root["rate_limit"]) {
            result.windows += windows(fromLimit: limit, idPrefix: "codex", titlePrefix: nil, now: now, markPrimary: true)
            if JSON.bool(limit["limit_reached"]) == true {
                result.details.append(DetailRow(label: "Situação", value: "limite atingido"))
            }
        }
        if let review = JSON.dict(root["code_review_rate_limit"]) {
            result.windows += windows(fromLimit: review, idPrefix: "codex.review", titlePrefix: "Code review", now: now, markPrimary: false)
        }
        for (index, extra) in JSON.array(root["additional_rate_limits"]).enumerated() {
            let name = JSON.string(extra["limit_name"]) ?? JSON.string(extra["name"]) ?? "Limite extra \(index + 1)"
            let limit = JSON.dict(extra["rate_limit"]) ?? extra
            result.windows += windows(fromLimit: limit, idPrefix: "codex.extra\(index)", titlePrefix: name, now: now, markPrimary: false)
        }

        if let credits = JSON.dict(root["credits"]) {
            if JSON.bool(credits["unlimited"]) == true {
                result.details.append(DetailRow(label: "Créditos", value: "ilimitados"))
            } else if JSON.bool(credits["has_credits"]) == true, let balance = JSON.double(credits["balance"]) {
                result.details.append(DetailRow(label: "Créditos", value: String(format: "%.2f", balance)))
            }
        }
        return result.windows.isEmpty && result.plan == nil ? nil : result
    }

    /// `rate_limits` as logged in `token_count` events of `~/.codex/sessions/**/rollout-*.jsonl`.
    public static func windows(fromLog rateLimits: [String: Any], loggedAt time: Date) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for (key, isPrimary) in [("primary", true), ("secondary", false)] {
            guard let object = JSON.dict(rateLimits[key]), let used = JSON.double(object["used_percent"]) else { continue }
            let seconds = JSON.double(object["window_minutes"]).map { $0 * 60 }
            var resetsAt = JSON.double(object["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            if resetsAt == nil, let inSeconds = JSON.double(object["resets_in_seconds"]) {
                resetsAt = time.addingTimeInterval(inSeconds)
            }
            windows.append(
                UsageWindow(
                    id: "codex.\(key)",
                    title: windowTitle(seconds: seconds),
                    usedPercent: used,
                    resetsAt: resetsAt,
                    windowSeconds: seconds,
                    isPrimary: isPrimary
                )
            )
        }
        return windows
    }

    public static func windowTitle(seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "Limite de uso" }
        let hours = seconds / 3_600
        if abs(hours - 5) < 0.1 { return "Sessão (5h)" }
        if abs(hours - 24) < 0.1 { return "Diário" }
        if abs(hours - 168) < 1 { return "Semanal" }
        if hours >= 672 { return "Mensal" }
        if hours < 48 { return "Janela de \(Int(hours.rounded()))h" }
        return "Janela de \(Int((hours / 24).rounded())) dias"
    }

    /// "prolite" → "Pro Lite".
    public static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "prolite", "pro_lite": return "Pro Lite"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "free": return "Free"
        case "go": return "Go"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default:
            return raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }

    private static func windows(
        fromLimit limit: [String: Any],
        idPrefix: String,
        titlePrefix: String?,
        now: Date,
        markPrimary: Bool
    ) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for (key, suffix) in [("primary_window", "primary"), ("secondary_window", "secondary")] {
            guard let object = JSON.dict(limit[key]), let used = JSON.double(object["used_percent"]) else { continue }
            let seconds = JSON.double(object["limit_window_seconds"])
            let resetAfter = JSON.double(object["reset_after_seconds"])
            var resetsAt = JSON.double(object["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            if resetsAt == nil, let resetAfter { resetsAt = now.addingTimeInterval(resetAfter) }
            // An untouched window reports a full-length countdown that restarts on every read.
            var notStarted = false
            if used == 0, let resetAfter, let seconds { notStarted = resetAfter >= seconds - 5 }
            let base = windowTitle(seconds: seconds)
            windows.append(
                UsageWindow(
                    id: "\(idPrefix).\(suffix)",
                    title: titlePrefix.map { "\($0) · \(base.lowercased())" } ?? base,
                    usedPercent: used,
                    resetsAt: resetsAt,
                    windowSeconds: seconds,
                    notStarted: notStarted,
                    isPrimary: markPrimary && suffix == "primary"
                )
            )
        }
        return windows
    }
}
