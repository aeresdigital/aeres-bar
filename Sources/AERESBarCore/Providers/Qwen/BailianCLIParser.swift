import Foundation

/// Parses `bl usage coding-plan --output json`, Alibaba Model Studio's official CLI: the Qwen
/// Coding Plan's 5-hour, weekly and billing-month quotas (`per5Hour`, `perWeek`, `perBillMonth`),
/// read with the CLI's console login. The plan has no API that takes its API key.
public enum BailianCLIParser {
    public static func outcome(from data: Data) -> CommandOutcome {
        guard let root = JSON.object(data) else { return .unreadable }
        let definitions: [(key: String, id: String, title: String, seconds: Double)] = [
            ("per5Hour", "qwen.session", "Sessão (5h)", 5 * 3_600),
            ("perWeek", "qwen.weekly", "Semanal", 7 * 86_400),
            ("perBillMonth", "qwen.monthly", "Mensal (ciclo de cobrança)", 30 * 86_400),
        ]
        var windows: [UsageWindow] = []
        for definition in definitions {
            guard let quota = JSON.dict(root[definition.key]) else { continue }
            let used = JSON.double(quota["usedQuota"])
            let total = JSON.double(quota["totalQuota"])
            // `percentage` is a fraction; the counts give the same number when present.
            let fraction =
                JSON.double(quota["percentage"]).map { $0 > 1 ? $0 / 100 : $0 }
                ?? used.flatMap { used in total.flatMap { $0 > 0 ? used / $0 : nil } }
            guard let fraction else { continue }
            windows.append(
                UsageWindow(
                    id: definition.id,
                    title: definition.title,
                    subtitle: used.flatMap { used in
                        total.map { "\(Formatting.count(Int(used))) de \(Formatting.count(Int($0))) requisições" }
                    },
                    usedPercent: min(max(fraction * 100, 0), 100),
                    resetsAt: JSON.double(quota["resetTime"]).map { Date(timeIntervalSince1970: $0 / 1_000) },
                    windowSeconds: definition.seconds,
                    isPrimary: windows.isEmpty
                )
            )
        }
        guard !windows.isEmpty else {
            return root.isEmpty || root["instanceType"] != nil
                ? .noPlan("Nenhum Coding Plan ativo nesta conta do Model Studio.") : .unreadable
        }
        return .reading(KeyedReading(plan: JSON.string(root["instanceType"]).map(\.capitalized), windows: windows))
    }
}
