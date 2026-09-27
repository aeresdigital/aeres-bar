import Foundation

/// Parses `GET https://api.github.com/copilot_internal/user`, the endpoint Copilot's editor
/// extensions use to show the monthly quotas.
public enum CopilotUsageParser {
    public struct Result: Equatable, Sendable {
        public var plan: String?
        public var windows: [UsageWindow]
        public var details: [DetailRow]
    }

    private static let quotas: [(key: String, title: String)] = [
        ("premium_interactions", "Requisições premium"),
        ("chat", "Chat"),
        ("completions", "Autocompletar"),
    ]

    public static func parse(_ data: Data) -> Result? {
        guard let root = JSON.object(data), let snapshots = JSON.dict(root["quota_snapshots"]) else { return nil }
        let resetsAt =
            Timestamp.parse(root["quota_reset_date_utc"] as? String)
            ?? (JSON.string(root["quota_reset_date"]).flatMap { Timestamp.parse("\($0)T00:00:00Z") })

        var windows: [UsageWindow] = []
        var details: [DetailRow] = []
        for quota in quotas {
            guard let snapshot = JSON.dict(snapshots[quota.key]) else { continue }
            if JSON.bool(snapshot["unlimited"]) == true {
                details.append(DetailRow(label: quota.title, value: "ilimitado"))
                continue
            }
            let entitlement = JSON.double(snapshot["entitlement"]) ?? 0
            guard entitlement > 0 else { continue }  // e.g. premium requests on the free plan
            let remaining = JSON.double(snapshot["remaining"]) ?? JSON.double(snapshot["quota_remaining"]) ?? entitlement
            let percentRemaining = JSON.double(snapshot["percent_remaining"]) ?? remaining / entitlement * 100
            windows.append(
                UsageWindow(
                    id: "copilot.\(quota.key)",
                    title: quota.title,
                    subtitle:
                        "\(Formatting.count(Int(remaining.rounded()))) de \(Formatting.count(Int(entitlement.rounded()))) restantes no mês",
                    usedPercent: min(max(100 - percentRemaining, 0), 100),
                    resetsAt: resetsAt,
                    windowSeconds: 30 * 86_400,
                    isPrimary: windows.isEmpty
                )
            )
            let overage = JSON.int(snapshot["overage_count"])
            if overage > 0 {
                details.append(DetailRow(label: "\(quota.title) além da cota", value: Formatting.count(overage)))
            }
        }
        let plan = planName(sku: JSON.string(root["access_type_sku"]), plan: JSON.string(root["copilot_plan"]))
        guard !windows.isEmpty || !details.isEmpty || plan != nil else { return nil }
        return Result(plan: plan, windows: windows, details: details)
    }

    /// Plan from the SKU ("free_limited_copilot" → "Free", "plus_monthly_subscriber_quota" → "Pro+"),
    /// else from `copilot_plan`.
    public static func planName(sku: String?, plan: String?) -> String? {
        let sku = (sku ?? "").lowercased()
        // Order matters: the student plan's SKU also says "free".
        let rules: [(match: String, name: String)] = [
            ("educational", "Education"), ("student", "Education"),
            ("free", "Free"),
            ("plus", "Pro+"),
            ("enterprise", "Enterprise"), ("business", "Business"),
            ("pro", "Pro"), ("subscriber", "Pro"),
        ]
        if let rule = rules.first(where: { sku.contains($0.match) }) { return rule.name }
        guard let plan = plan?.trimmingCharacters(in: .whitespaces), !plan.isEmpty else { return nil }
        return plan.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
