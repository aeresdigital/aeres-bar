import Foundation

/// Parses Kimi Code's `GET /coding/v1/usages`, the endpoint the official Kimi Code CLI calls for
/// `/usage`. It is not in Moonshot's public reference and its shape depends on the plan: older
/// plans report counts (`usage` for the week, `limits` per window), newer ones ratios per window
/// (`usages.limit_5h`, `limit_7d`, `limit_month_total`, `limit_month_code`).
public enum KimiCodeParser {
    /// A window's usage (0–100) and renewal, from either form.
    struct Level {
        var percent: Double
        var resetsAt: Date?
    }

    public static func windows(from data: Data) -> [UsageWindow]? {
        guard let root = JSON.object(data) else { return nil }
        let ratios = JSON.dict(root["usages"]) ?? [:]

        // Counts per window length: `limits` entries say how long their window is.
        var counted: [Double: Level] = [:]
        for entry in JSON.array(root["limits"]) {
            guard let seconds = seconds(of: JSON.dict(entry["window"])), let level = counts(JSON.dict(entry["detail"])) else { continue }
            counted[seconds] = level
        }
        // The top-level `usage` of the older plans is the weekly window.
        if counted[7 * 86_400] == nil, let weekly = counts(JSON.dict(root["usage"])) { counted[7 * 86_400] = weekly }

        let definitions: [(id: String, title: String, seconds: Double, ratioKey: String)] = [
            ("kimi.session", "Sessão (5h)", 5 * 3_600, "limit_5h"),
            ("kimi.weekly", "Semanal", 7 * 86_400, "limit_7d"),
            ("kimi.monthly", "Mensal", 30 * 86_400, "limit_month_total"),
        ]
        var windows: [UsageWindow] = []
        for definition in definitions {
            // The server has been seen reporting a ratio of 0 while its counts show the window
            // used up: trust whichever says more.
            let candidates = [ratio(JSON.dict(ratios[definition.ratioKey])), counted[definition.seconds]].compactMap { $0 }
            guard let level = candidates.max(by: { $0.percent < $1.percent }) else { continue }
            windows.append(
                UsageWindow(
                    id: definition.id,
                    title: definition.title,
                    usedPercent: min(max(level.percent, 0), 100),
                    resetsAt: level.resetsAt ?? candidates.lazy.compactMap(\.resetsAt).first,
                    windowSeconds: definition.seconds,
                    isPrimary: windows.isEmpty
                )
            )
        }
        return windows.isEmpty ? nil : windows
    }

    /// Kimi Code's share of the monthly membership quota, which other Kimi features also draw
    /// from (the CLI shows it as "code X%").
    public static func details(from data: Data) -> [DetailRow] {
        guard let root = JSON.object(data), let code = ratio(JSON.dict(JSON.dict(root["usages"])?["limit_month_code"])) else { return [] }
        return [DetailRow(label: "Kimi Code na cota mensal", value: Formatting.percent(code.percent))]
    }

    /// The membership level from `GET /coding/v1/me`.
    public static func planName(from data: Data) -> String? {
        JSON.object(data).flatMap { JSON.string($0["user_level_name"]) }
    }

    /// `{"used_ratio": 0.0795, "reset_time": "…"}`.
    static func ratio(_ entry: [String: Any]?) -> Level? {
        guard let entry, let value = JSON.double(entry["used_ratio"]) else { return nil }
        return Level(percent: value * 100, resetsAt: Timestamp.parse(JSON.string(entry["reset_time"])))
    }

    /// `{"limit": "100", "used" or "remaining": "…", "resetTime": "…"}`, counts as decimal strings.
    /// The limit is not shown: it has been 100 on every plan, likely a normalised scale.
    static func counts(_ detail: [String: Any]?) -> Level? {
        guard let detail, let limit = JSON.double(detail["limit"]), limit > 0,
            let used = JSON.double(detail["used"]) ?? JSON.double(detail["remaining"]).map({ limit - $0 })
        else { return nil }
        return Level(percent: used / limit * 100, resetsAt: Timestamp.parse(JSON.string(detail["resetTime"])))
    }

    /// `{"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"}` → 18 000.
    static func seconds(of window: [String: Any]?) -> Double? {
        guard let window, let duration = JSON.double(window["duration"]) else { return nil }
        switch JSON.string(window["timeUnit"]) {
        case "TIME_UNIT_SECOND": return duration
        case "TIME_UNIT_MINUTE": return duration * 60
        case "TIME_UNIT_HOUR": return duration * 3_600
        case "TIME_UNIT_DAY": return duration * 86_400
        default: return nil
        }
    }
}

/// Parses the Kimi open platform's `GET /v1/users/me/balance` (platform.kimi.ai, in dollars, and
/// platform.kimi.com, in yuan).
public enum MoonshotBalanceParser {
    public static func reading(from data: Data, currency: String) -> KeyedReading? {
        guard let root = JSON.object(data), let balance = JSON.dict(root["data"]),
            let available = JSON.double(balance["available_balance"])
        else { return nil }
        var rows = [DetailRow(label: "Saldo disponível", value: Formatting.money(available, currency: currency))]
        if let voucher = JSON.double(balance["voucher_balance"]), voucher != 0 {
            rows.append(DetailRow(label: "Cupons", value: Formatting.money(voucher, currency: currency)))
        }
        if let cash = JSON.double(balance["cash_balance"]) {
            // Negative when the account owes money; the voucher balance is then all that is left.
            rows.append(
                DetailRow(label: "Saldo em dinheiro", value: Formatting.money(cash, currency: currency) + (cash < 0 ? " (em débito)" : "")))
        }
        if available <= 0 {
            rows.append(DetailRow(label: "Aviso", value: "sem saldo: as chamadas à API falham até recarregar"))
        }
        return KeyedReading(details: rows)
    }
}

/// The Kimi Code CLI's login on disk, read-only: `<home>/credentials/kimi-code*.json` with
/// `access_token` and `expires_at` (Unix seconds). The CLI renews it itself when used; renewing it
/// here would rotate the refresh token and sign the CLI out.
public enum KimiCodeCredentials {
    public static func find(in homes: [URL], now: Date) -> KeyedService.LocalCredential? {
        var newest: (token: String, expires: Date?, modified: Date)?
        for home in homes {
            let folder = home.appendingPathComponent("credentials")
            let files =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("kimi-code") {
                guard let data = try? Data(contentsOf: file), let root = JSON.object(data), let token = JSON.string(root["access_token"])
                else { continue }
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                guard modified >= (newest?.modified ?? .distantPast) else { continue }
                newest = (token, JSON.double(root["expires_at"]).map { Date(timeIntervalSince1970: $0) }, modified)
            }
        }
        guard let newest else { return nil }
        if let expires = newest.expires, expires <= now {
            return .expired(
                message: "O login do Kimi Code expirou. Use o Kimi Code CLI uma vez (ou rode /login) e o AERES Bar volta a ler.")
        }
        return .token(newest.token)
    }
}
