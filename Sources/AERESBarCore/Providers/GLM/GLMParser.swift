import Foundation

/// Parses the GLM Coding Plan quota of Z.ai (api.z.ai) and Zhipu (open.bigmodel.cn):
/// `GET /api/monitor/usage/quota/limit`, the endpoint of Z.ai's own usage plugin and of its ZCode
/// app. It is not in the public reference, and errors come back as HTTP 200 with the code in the
/// body.
public enum GLMParser {
    public static func reading(from data: Data, now: Date) -> KeyedReading? {
        guard let root = JSON.object(data), JSON.bool(root["success"]) != false, let payload = JSON.dict(root["data"]) else { return nil }
        var session: UsageWindow?
        var weekly: UsageWindow?
        var tools: UsageWindow?
        var details: [DetailRow] = []

        // Entries are told apart by (type, unit, number), not by their order.
        for limit in JSON.array(payload["limits"]) {
            let type = JSON.string(limit["type"]) ?? ""
            let unit = JSON.int(limit["unit"])
            let total = JSON.double(limit["usage"])
            let used = JSON.double(limit["currentValue"])
            // `percentage` is a whole, floored number: the counts are more precise when present.
            let percent = total.flatMap { total in used.map { total > 0 ? $0 / total * 100 : 0 } } ?? JSON.double(limit["percentage"]) ?? 0
            let resetsAt = JSON.double(limit["nextResetTime"]).map { Date(timeIntervalSince1970: $0 / 1_000) }
            let subtitle = total.flatMap { total in used.map { "\(Formatting.count(Int($0))) de \(Formatting.count(Int(total)))" } }

            switch (type, unit, JSON.int(limit["number"])) {
            case ("TOKENS_LIMIT", 3, 5), ("CREDIT_LIMIT", 3, 5):
                // Resets far beyond 5 hours have been seen; they are not believable.
                let believable = resetsAt.flatMap { $0.timeIntervalSince(now) <= 5 * 3_600 + 60 ? $0 : nil }
                session = UsageWindow(
                    id: "glm.session",
                    title: "Sessão (5h)",
                    subtitle: type == "CREDIT_LIMIT" ? subtitle.map { "\($0) créditos" } : nil,
                    usedPercent: percent,
                    resetsAt: believable,
                    windowSeconds: 5 * 3_600,
                    // Without a reset time, the window starts with the next request.
                    notStarted: resetsAt == nil && percent == 0,
                    isPrimary: true
                )
            case ("TOKENS_LIMIT", 6, _), ("CREDIT_LIMIT", 6, _):
                weekly = UsageWindow(
                    id: "glm.weekly",
                    title: "Semanal",
                    subtitle: type == "CREDIT_LIMIT" ? subtitle.map { "\($0) créditos" } : nil,
                    usedPercent: percent,
                    resetsAt: resetsAt,
                    windowSeconds: 7 * 86_400
                )
            case ("TIME_LIMIT", _, _):
                tools = UsageWindow(
                    id: "glm.tools",
                    title: "Ferramentas MCP · mensal",
                    subtitle: subtitle.map { "\($0) chamadas" },
                    usedPercent: percent,
                    resetsAt: resetsAt,
                    windowSeconds: 30 * 86_400
                )
                let calls = JSON.array(limit["usageDetails"]).compactMap { detail -> String? in
                    guard let code = JSON.string(detail["modelCode"]) else { return nil }
                    return "\(toolName(code)) \(Formatting.count(JSON.int(detail["usage"])))"
                }
                if !calls.isEmpty { details.append(DetailRow(label: "Chamadas de ferramentas", value: calls.joined(separator: " · "))) }
            default:
                continue
            }
        }

        var windows = [session, weekly, tools].compactMap { $0 }
        guard !windows.isEmpty else { return nil }
        if session == nil { windows[0].isPrimary = true }
        let plan = JSON.string(payload["level"]).map(\.capitalized)
        return KeyedReading(plan: plan, windows: windows, details: details)
    }

    /// The error a failed answer carries in its body (`{"code": 401, "success": false, …}`).
    public static func bodyIssue(_ data: Data) -> ProviderIssue? {
        guard let root = JSON.object(data) else { return nil }
        let code = JSON.double(root["code"]).map { Int($0) }
        let failed = JSON.bool(root["success"]) == false || code.map { $0 != 200 && $0 != 0 } == true
        guard failed else { return nil }
        let message = JSON.string(root["msg"]) ?? ""
        switch code {
        case 401, 1000, 1001, 1002, 1003, 1004:
            return ProviderIssue(.unauthorized, "A chave do GLM foi recusada — confira em Ajustes › Chaves de API.")
        case 429, 1302, 1303, 1305:
            return ProviderIssue(.rateLimited, "O GLM pediu uma pausa nas consultas — nova tentativa em alguns minutos.")
        case 500 where message.localizedCaseInsensitiveContains("coding plan"):
            return ProviderIssue(.notSignedIn, "Esta chave não tem um GLM Coding Plan ativo.")
        default:
            return ProviderIssue(.invalidResponse, "O GLM recusou a consulta (código \(code.map(String.init) ?? "desconhecido")).")
        }
    }

    /// The MCP tools the plan counts.
    static func toolName(_ code: String) -> String {
        switch code {
        case "search-prime": "busca"
        case "web-reader": "leitura de páginas"
        case "zread": "Zread"
        default: code
        }
    }
}

/// GLM keys already on this Mac, read-only: Claude Code set up with the coding plan, or Z.ai's
/// Coding Tool Helper (`~/.chelper/config.yaml`).
public enum GLMCredentials {
    static let hosts: Set<String> = ["api.z.ai", "open.bigmodel.cn", "bigmodel.cn"]

    public static func find(claudeSettings: [URL], helperConfig: URL) -> KeyedService.LocalCredential? {
        if let token = ClaudeCodeSettings.token(forHosts: hosts, in: claudeSettings) { return .token(token) }
        if let text = try? String(contentsOf: helperConfig, encoding: .utf8), let key = helperKey(in: text) { return .token(key) }
        return nil
    }

    /// `api_key: …` at the top level of the helper's YAML.
    static func helperKey(in yaml: String) -> String? {
        for line in yaml.split(separator: "\n") where line.hasPrefix("api_key:") {
            let value = line.dropFirst("api_key:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }
}
