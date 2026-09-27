import Foundation

/// Parses MiniMax's Token Plan (formerly Coding Plan) quota: `GET /v1/token_plan/remains`, one
/// entry per model lane in `model_remains`. Errors come back as HTTP 200 with `base_resp`.
public enum MiniMaxParser {
    public static func reading(from data: Data) -> KeyedReading? {
        guard let root = JSON.object(data), status(of: root) == 0 else { return nil }
        let lanes = JSON.array(root["model_remains"])
        // Text models share one pool: "general" on current plans, "MiniMax-M*" on older ones.
        guard let main = lanes.first(where: isText) ?? lanes.first else { return nil }

        var windows: [UsageWindow] = []
        if let session = window(
            main, prefix: "current_interval", start: "start_time", end: "end_time", id: "minimax.session", title: "Sessão (5h)",
            fallbackSeconds: 5 * 3_600)
        {
            windows.append(session)
        }
        if let weekly = window(
            main, prefix: "current_weekly", start: "weekly_start_time", end: "weekly_end_time", id: "minimax.weekly", title: "Semanal",
            fallbackSeconds: 7 * 86_400)
        {
            windows.append(weekly)
        }
        guard !windows.isEmpty else { return nil }
        windows[0].isPrimary = true

        // Other lanes (video has a daily window) are details.
        let details = lanes.filter { !isText($0) }.compactMap { lane -> DetailRow? in
            guard let name = JSON.string(lane["model_name"]), let used = usedPercent(lane, prefix: "current_interval") else { return nil }
            return DetailRow(label: name == "video" ? "Vídeo" : name, value: "\(Formatting.percent(used)) usado")
        }
        return KeyedReading(windows: windows, details: details)
    }

    /// The error a failed answer carries in `base_resp`.
    public static func bodyIssue(_ data: Data) -> ProviderIssue? {
        guard let root = JSON.object(data), let code = status(of: root), code != 0 else { return nil }
        switch code {
        case 1004, 2049:
            return ProviderIssue(.unauthorized, "A chave do MiniMax foi recusada — confira em Ajustes › Chaves de API.")
        case 1002:
            return ProviderIssue(.rateLimited, "O MiniMax pediu uma pausa nas consultas — nova tentativa em alguns minutos.")
        default:
            return ProviderIssue(.invalidResponse, "O MiniMax recusou a consulta (código \(code)).")
        }
    }

    static func status(of root: [String: Any]) -> Int? {
        JSON.dict(root["base_resp"]).flatMap { JSON.double($0["status_code"]) }.map { Int($0) }
    }

    static func isText(_ lane: [String: Any]) -> Bool {
        let name = JSON.string(lane["model_name"]) ?? ""
        return name == "general" || name.hasPrefix("MiniMax-M")
    }

    /// Used share of a lane's window. `…_remaining_percent` is the remaining share and wins when
    /// present; without it, the older plans' `…_usage_count` counts what is left, not what was used.
    static func usedPercent(_ lane: [String: Any], prefix: String) -> Double? {
        if let remaining = JSON.double(lane["\(prefix)_remaining_percent"]) { return min(max(100 - remaining, 0), 100) }
        switch JSON.int(lane["\(prefix)_status"]) {
        case 2: return 100  // exhausted
        case 3: return nil  // unlimited, or not part of the plan
        default: break
        }
        guard let total = JSON.double(lane["\(prefix)_total_count"]), total > 0, let left = JSON.double(lane["\(prefix)_usage_count"])
        else { return nil }
        return min(max((total - left) / total * 100, 0), 100)
    }

    private static func window(
        _ lane: [String: Any], prefix: String, start: String, end: String, id: String, title: String, fallbackSeconds: Double
    ) -> UsageWindow? {
        guard let used = usedPercent(lane, prefix: prefix) else { return nil }
        let startsAt = JSON.double(lane[start]).map { Date(timeIntervalSince1970: $0 / 1_000) }
        let endsAt = JSON.double(lane[end]).map { Date(timeIntervalSince1970: $0 / 1_000) }
        // Windows are fixed blocks in China's time zone; the last one of the day lasts 4 hours.
        let seconds =
            startsAt.flatMap { start in endsAt.map { $0.timeIntervalSince(start) } }.flatMap { $0 > 0 ? $0 : nil } ?? fallbackSeconds
        var subtitle: String?
        if JSON.double(lane["\(prefix)_remaining_percent"]) == nil, let total = JSON.double(lane["\(prefix)_total_count"]), total > 0 {
            subtitle = "\(Formatting.count(JSON.int(lane["\(prefix)_usage_count"]))) de \(Formatting.count(Int(total))) restantes"
        }
        return UsageWindow(id: id, title: title, subtitle: subtitle, usedPercent: used, resetsAt: endsAt, windowSeconds: seconds)
    }
}

/// MiniMax keys already on this Mac, read-only: Claude Code set up with the Token Plan, or the
/// official MiniMax CLI (`~/.mmx/config.json`, `api_key` or its OAuth `access_token`).
public enum MiniMaxCredentials {
    static let hosts: Set<String> = ["api.minimax.io", "api.minimaxi.com", "api.minimax.cn"]

    public static func find(claudeSettings: [URL], cliConfig: URL, now: Date) -> KeyedService.LocalCredential? {
        if let token = ClaudeCodeSettings.token(forHosts: hosts, in: claudeSettings) { return .token(token) }
        guard let data = try? Data(contentsOf: cliConfig), let root = JSON.object(data) else { return nil }
        if let key = JSON.string(root["api_key"]) { return .token(key) }
        guard let oauth = JSON.dict(root["oauth"]), let token = JSON.string(oauth["access_token"]) else { return nil }
        if let expiry = JSON.double(oauth["expires_at"]) {
            // Seconds or milliseconds: nothing expires before 2001 or after 5138.
            let expires = Date(timeIntervalSince1970: expiry > 100_000_000_000 ? expiry / 1_000 : expiry)
            if expires <= now {
                return .expired(message: "O login do MiniMax CLI expirou. Use o mmx uma vez e o AERES Bar volta a ler.")
            }
        }
        return .token(token)
    }
}
