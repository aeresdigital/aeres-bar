import Foundation

/// Parses the JSON (Connect protocol) replies of Antigravity's local language server.
/// Proto3 JSON omits zero values, so a quota without `remainingFraction` is exhausted.
public enum AntigravityParser {
    public struct UserStatus: Equatable, Sendable {
        public var plan: String?
        public var email: String?
        public var models: [ModelQuota]
    }

    /// `LanguageServerService/GetUserStatus`.
    public static func parseUserStatus(_ data: Data) -> UserStatus? {
        guard let root = JSON.object(data), let status = JSON.dict(root["userStatus"]) else { return nil }
        let tier = JSON.string(JSON.dict(status["userTier"])?["name"])
        let planInfo = JSON.dict(JSON.dict(status["planStatus"])?["planInfo"])
        let configs = JSON.array(JSON.dict(status["cascadeModelConfigData"])?["clientModelConfigs"])
        let models = configs.compactMap { config -> ModelQuota? in
            guard let label = JSON.string(config["label"]) else { return nil }
            let quota = JSON.dict(config["quotaInfo"])
            return ModelQuota(
                label: label,
                remainingFraction: quota.map { JSON.double($0["remainingFraction"]) ?? 0 },
                resetsAt: Timestamp.parse(quota?["resetTime"] as? String)
            )
        }
        return UserStatus(plan: planName(tier ?? JSON.string(planInfo?["planName"])), email: JSON.string(status["email"]), models: models)
    }

    /// `LanguageServerService/RetrieveUserQuotaSummary`: groups of models sharing a quota bucket.
    public static func parseQuotaSummary(_ data: Data) -> [UsageWindow]? {
        guard let root = JSON.object(data) else { return nil }
        let response = JSON.dict(root["response"]) ?? root
        var windows: [UsageWindow] = []
        for group in JSON.array(response["groups"]) {
            let groupName = translateGroup(JSON.string(group["displayName"]) ?? "Modelos")
            let members = JSON.string(group["description"]).map(cleanDescription)
            for bucket in JSON.array(group["buckets"]) {
                let remaining = min(max(JSON.double(bucket["remainingFraction"]) ?? 0, 0), 1)
                let window = JSON.string(bucket["window"])
                let windowLabel = windowName(window)
                windows.append(
                    UsageWindow(
                        id: "ag.\(JSON.string(bucket["bucketId"]) ?? "\(groupName).\(window ?? "")")",
                        title: windowLabel.isEmpty ? groupName : "\(groupName) · \(windowLabel)",
                        subtitle: members,
                        usedPercent: (1 - remaining) * 100,
                        resetsAt: Timestamp.parse(bucket["resetTime"] as? String),
                        windowSeconds: windowSeconds(window),
                        // A full bucket reports "now + window" as its reset: the clock hasn't started.
                        notStarted: remaining >= 0.9999,
                        isPrimary: windows.isEmpty
                    )
                )
            }
        }
        return windows.isEmpty ? nil : windows
    }

    /// Fallback when the summary RPC is unavailable: models with identical quota state form one row.
    public static func windows(fromModels models: [ModelQuota]) -> [UsageWindow] {
        var groups: [(key: String, models: [ModelQuota])] = []
        for model in models {
            guard let fraction = model.remainingFraction else { continue }
            let key = "\(Int((fraction * 1_000).rounded()))|\(Int((model.resetsAt?.timeIntervalSince1970 ?? 0) / 300))"
            if let index = groups.firstIndex(where: { $0.key == key }) {
                groups[index].models.append(model)
            } else {
                groups.append((key, [model]))
            }
        }
        return groups.enumerated().compactMap { index, group in
            guard let first = group.models.first else { return nil }
            let remaining = min(max(first.remainingFraction ?? 0, 0), 1)
            let title: String
            if groups.count == 1 {
                title = "Todos os modelos"
            } else if group.models.count == 1 {
                title = first.label
            } else {
                title = "\(first.label) e +\(group.models.count - 1)"
            }
            return UsageWindow(
                id: "ag.models.\(index)",
                title: title,
                subtitle: group.models.count > 1 ? group.models.map(\.label).joined(separator: ", ") : nil,
                usedPercent: (1 - remaining) * 100,
                resetsAt: first.resetsAt,
                notStarted: remaining >= 0.9999,
                isPrimary: index == 0
            )
        }
    }

    /// "Antigravity Starter Quota" → "Starter Quota" (the provider is already named in the header).
    private static func planName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.replacingOccurrences(of: "Antigravity ", with: "", options: [.anchored, .caseInsensitive])
        return trimmed.isEmpty ? raw : trimmed
    }

    private static func translateGroup(_ name: String) -> String {
        switch name.lowercased() {
        case "gemini models": "Modelos Gemini"
        case "claude and gpt models": "Claude e GPT"
        default: name
        }
    }

    /// "Models within this group: Gemini Flash, Gemini Pro" → "Gemini Flash, Gemini Pro".
    private static func cleanDescription(_ text: String) -> String {
        guard let colon = text.range(of: ":") else { return text }
        return text[colon.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    private static func windowName(_ window: String?) -> String {
        switch window?.lowercased() {
        case "weekly": "semanal"
        case "daily": "diário"
        case "monthly": "mensal"
        case "five_hour", "5h", "hourly_5": "5h"
        case .some(let other): other
        case .none: ""
        }
    }

    private static func windowSeconds(_ window: String?) -> Double? {
        switch window?.lowercased() {
        case "weekly": 7 * 86_400
        case "daily": 86_400
        case "monthly": 30 * 86_400
        case "five_hour", "5h", "hourly_5": 5 * 3_600
        default: nil
        }
    }
}
