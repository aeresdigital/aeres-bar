import Foundation

/// Parses `arkcli usage plan --format json`, Volcengine's official CLI: `items` (one per
/// subscription: Coding Plan, Agent Plan, their team editions) with `periods` (`5h` or `session`,
/// `weekly`, `monthly`), each with the used `percent` and `reset_at` in RFC 3339.
public enum ArkCLIParser {
    public static func outcome(from data: Data) -> CommandOutcome {
        guard let root = JSON.object(data), root["items"] != nil else { return .unreadable }
        let subscribed = JSON.array(root["items"]).filter { JSON.bool($0["subscribed"]) == true && !JSON.array($0["periods"]).isEmpty }
        guard !subscribed.isEmpty else {
            return .noPlan("Nenhum Coding Plan ou Agent Plan ativo nesta conta do Volcengine.")
        }
        var windows: [UsageWindow] = []
        for item in subscribed {
            let product = productName(JSON.string(item["product"]) ?? "")
            for period in JSON.array(item["periods"]) {
                guard let label = JSON.string(period["label"]), let kind = kind(of: label), let percent = JSON.double(period["percent"])
                else { continue }
                windows.append(
                    UsageWindow(
                        id: "doubao.\(JSON.string(item["product"]) ?? "plan").\(label)",
                        title: subscribed.count > 1 ? "\(product) · \(kind.title)" : kind.title,
                        usedPercent: min(max(percent, 0), 100),
                        resetsAt: Timestamp.parse(JSON.string(period["reset_at"])),
                        windowSeconds: kind.seconds,
                        isPrimary: windows.isEmpty
                    )
                )
            }
        }
        guard !windows.isEmpty else { return .unreadable }
        let first = subscribed[0]
        let plan = [productName(JSON.string(first["product"]) ?? ""), JSON.string(first["tier"]).map(\.capitalized)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return .reading(KeyedReading(plan: plan.isEmpty ? nil : plan, windows: windows))
    }

    static func kind(of label: String) -> (title: String, seconds: Double)? {
        switch label {
        case "5h", "session": ("Sessão (5h)", 5 * 3_600)
        case "weekly": ("Semanal", 7 * 86_400)
        case "monthly": ("Mensal", 30 * 86_400)
        default: nil
        }
    }

    static func productName(_ product: String) -> String {
        switch product {
        case "coding-plan": "Coding Plan"
        case "coding-plan-team": "Coding Plan (equipe)"
        case "agent-plan": "Agent Plan"
        case "agent-plan-team": "Agent Plan (equipe)"
        default: product
        }
    }
}
