import Foundation

/// Parses DeepSeek's `GET /user/balance`: a prepaid balance per currency, with no usage windows
/// (DeepSeek has no usage API).
public enum DeepSeekParser {
    public static func reading(from data: Data) -> KeyedReading? {
        guard let root = JSON.object(data) else { return nil }
        let infos = JSON.array(root["balance_infos"])
        var rows: [DetailRow] = []
        for info in infos {
            guard let currency = JSON.string(info["currency"]), let total = JSON.double(info["total_balance"]) else { continue }
            var value = Formatting.money(total, currency: currency)
            // Granted credit is spent before the money topped up.
            if let granted = JSON.double(info["granted_balance"]), granted > 0 {
                let toppedUp = JSON.double(info["topped_up_balance"]) ?? total - granted
                value +=
                    " (\(Formatting.money(toppedUp, currency: currency)) recarregado + \(Formatting.money(granted, currency: currency)) de bônus)"
            }
            rows.append(DetailRow(label: infos.count > 1 ? "Saldo em \(currency)" : "Saldo", value: value))
        }
        guard !rows.isEmpty else { return nil }
        if JSON.bool(root["is_available"]) == false {
            rows.append(DetailRow(label: "Aviso", value: "saldo insuficiente: as chamadas à API falham até recarregar"))
        }
        return KeyedReading(details: rows)
    }
}

/// DeepSeek keys already on this Mac, read-only, where DeepSeek's own guides put them: Claude
/// Code pointed at `api.deepseek.com`, or a `[model_providers.*]` of Codex's `config.toml` with
/// that base URL (`experimental_bearer_token`).
public enum DeepSeekCredentials {
    static let hosts: Set<String> = ["api.deepseek.com"]

    public static func find(claudeSettings: [URL], codexConfig: URL) -> KeyedService.LocalCredential? {
        if let token = ClaudeCodeSettings.token(forHosts: hosts, in: claudeSettings) { return .token(token) }
        if let text = try? String(contentsOf: codexConfig, encoding: .utf8), let token = codexToken(in: text) { return .token(token) }
        return nil
    }

    /// The bearer token of the Codex model provider whose `base_url` is DeepSeek's.
    static func codexToken(in toml: String) -> String? {
        var inProvider = false
        var baseURL: String?
        var token: String?
        func match() -> String? {
            guard let baseURL, let host = URLComponents(string: baseURL)?.host?.lowercased(), hosts.contains(host) else { return nil }
            return token
        }
        for rawLine in toml.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if inProvider, let found = match() { return found }
                inProvider = line.hasPrefix("[model_providers.")
                baseURL = nil
                token = nil
                continue
            }
            guard inProvider, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if key == "base_url" { baseURL = value }
            if key == "experimental_bearer_token", !value.isEmpty { token = value }
        }
        return inProvider ? match() : nil
    }
}
