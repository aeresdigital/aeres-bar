import Foundation

/// Parses OpenRouter's `GET /api/v1/key` and `GET /api/v1/credits`.
public enum OpenRouterParser {
    public struct KeyInfo: Equatable, Sendable {
        /// Spending cap of the key in USD, if any.
        public var limit: Double?
        public var limitRemaining: Double?
        /// `daily`, `weekly`, `monthly` or `nil` (the cap never resets).
        public var limitReset: String?
        /// All-time spend of the key.
        public var usage: Double
        public var usageDaily: Double?
        public var usageWeekly: Double?
        public var usageMonthly: Double?
        public var isFreeTier: Bool
        /// Daily requests to free models.
        public var freeRequestsUsed: Int?
        public var freeRequestsLimit: Int?
    }

    public struct Credits: Equatable, Sendable {
        public var total: Double
        public var used: Double
        public var balance: Double { total - used }
    }

    public static func parseKey(_ data: Data) -> KeyInfo? {
        guard let root = JSON.object(data), let key = JSON.dict(root["data"]) else { return nil }
        let free = JSON.dict(key["free_model_daily_requests"])
        return KeyInfo(
            limit: JSON.double(key["limit"]),
            limitRemaining: JSON.double(key["limit_remaining"]),
            limitReset: JSON.string(key["limit_reset"]),
            usage: JSON.double(key["usage"]) ?? 0,
            usageDaily: JSON.double(key["usage_daily"]),
            usageWeekly: JSON.double(key["usage_weekly"]),
            usageMonthly: JSON.double(key["usage_monthly"]),
            isFreeTier: JSON.bool(key["is_free_tier"]) ?? false,
            freeRequestsUsed: free.map { JSON.int($0["used"]) },
            freeRequestsLimit: free.map { JSON.int($0["limit"]) }
        )
    }

    public static func parseCredits(_ data: Data) -> Credits? {
        guard let root = JSON.object(data), let credits = JSON.dict(root["data"]),
            let total = JSON.double(credits["total_credits"])
        else { return nil }
        return Credits(total: total, used: JSON.double(credits["total_usage"]) ?? 0)
    }

    /// The key's spending cap and the free-model daily allowance, as usage windows.
    public static func windows(for key: KeyInfo, now: Date) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        if let limit = key.limit, limit > 0 {
            let period = Period(key.limitReset)
            let spent = key.limitRemaining.map { limit - $0 } ?? period?.spend(in: key) ?? key.usage
            windows.append(
                UsageWindow(
                    id: "openrouter.limit",
                    title: "Limite da chave" + (period.map { " · \($0.name)" } ?? ""),
                    subtitle: "\(Formatting.money(max(spent, 0), currency: "USD")) de \(Formatting.money(limit, currency: "USD"))",
                    usedPercent: min(max(spent / limit * 100, 0), 100),
                    resetsAt: period?.nextReset(after: now),
                    windowSeconds: period?.seconds,
                    isPrimary: true
                )
            )
        }
        if let used = key.freeRequestsUsed, let limit = key.freeRequestsLimit, limit > 0 {
            windows.append(
                UsageWindow(
                    id: "openrouter.free",
                    title: "Modelos gratuitos · diário",
                    subtitle: "\(Formatting.count(used)) de \(Formatting.count(limit)) requisições",
                    usedPercent: min(max(Double(used) / Double(limit) * 100, 0), 100),
                    resetsAt: Period.daily.nextReset(after: now),
                    windowSeconds: Period.daily.seconds,
                    isPrimary: windows.isEmpty
                )
            )
        }
        return windows
    }

    public static func details(for key: KeyInfo, credits: Credits?) -> [DetailRow] {
        var rows: [DetailRow] = []
        let spend = [("hoje", key.usageDaily), ("semana", key.usageWeekly), ("mês", key.usageMonthly)]
            .compactMap { label, value in value.map { "\(label) \(Formatting.money($0, currency: "USD"))" } }
        if !spend.isEmpty {
            rows.append(DetailRow(label: "Gasto", value: spend.joined(separator: " · ")))
        }
        if let credits {
            rows.append(
                DetailRow(
                    label: "Saldo",
                    value: "\(Formatting.money(credits.balance, currency: "USD")) de \(Formatting.money(credits.total, currency: "USD"))"
                )
            )
        }
        if key.limit == nil {
            rows.append(DetailRow(label: "Limite da chave", value: "sem limite"))
        }
        return rows
    }

    /// OpenRouter resets caps at midnight UTC; weeks run Monday to Sunday.
    enum Period {
        case daily, weekly, monthly

        init?(_ raw: String?) {
            switch raw?.lowercased() {
            case "daily": self = .daily
            case "weekly": self = .weekly
            case "monthly": self = .monthly
            default: return nil
            }
        }

        var name: String {
            switch self {
            case .daily: "diário"
            case .weekly: "semanal"
            case .monthly: "mensal"
            }
        }

        var seconds: Double {
            switch self {
            case .daily: 86_400
            case .weekly: 7 * 86_400
            case .monthly: 30 * 86_400
            }
        }

        func spend(in key: KeyInfo) -> Double? {
            switch self {
            case .daily: key.usageDaily
            case .weekly: key.usageWeekly
            case .monthly: key.usageMonthly
            }
        }

        func nextReset(after now: Date) -> Date? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            let components: DateComponents
            switch self {
            case .daily: components = DateComponents(hour: 0, minute: 0, second: 0)
            case .weekly: components = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
            case .monthly: components = DateComponents(day: 1, hour: 0, minute: 0, second: 0)
            }
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
        }
    }
}
