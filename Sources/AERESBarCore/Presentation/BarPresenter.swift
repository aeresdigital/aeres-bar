import Foundation

/// Which number each menu bar item shows.
public enum BarMetric: String, CaseIterable, Codable, Sendable {
    /// The window closest to its limit (default): answers "how close am I to being blocked?".
    case mostCritical
    /// The provider's main (shortest) window.
    case primary
    /// The weekly window.
    case weekly
    /// Tokens used today, from local logs.
    case tokensToday

    public var title: String {
        switch self {
        case .mostCritical: "Limite mais crítico"
        case .primary: "Janela principal (sessão)"
        case .weekly: "Limite semanal"
        case .tokensToday: "Tokens de hoje"
        }
    }
}

/// How alarming a usage level is.
public enum AlertLevel: Equatable, Sendable {
    /// 80% or more.
    case warning
    /// 95% or more.
    case critical

    public init?(usedPercent: Double) {
        if usedPercent >= 95 {
            self = .critical
        } else if usedPercent >= 80 {
            self = .warning
        } else {
            return nil
        }
    }
}

/// What a menu bar item displays.
public struct BarValue: Equatable, Sendable {
    public var text: String
    /// Effective usage of the window that drives the alert level.
    public var usedPercent: Double?
    public var window: UsageWindow?
    public var hasData: Bool

    public var alert: AlertLevel? { usedPercent.flatMap(AlertLevel.init(usedPercent:)) }
}

/// Decides what each menu bar item says.
public enum BarPresenter {
    public struct Config: Equatable, Sendable {
        public var metric: BarMetric
        public var showRemaining: Bool
        public var showCountdown: Bool

        public init(metric: BarMetric = .mostCritical, showRemaining: Bool = false, showCountdown: Bool = false) {
            self.metric = metric
            self.showRemaining = showRemaining
            self.showCountdown = showCountdown
        }
    }

    /// The window with the highest effective usage (the first one on ties).
    public static func mostCritical(_ windows: [UsageWindow], now: Date) -> UsageWindow? {
        windows.max { $0.effectiveUsed(at: now) < $1.effectiveUsed(at: now) }
    }

    /// The window `metric` refers to.
    public static func window(for snapshot: ProviderSnapshot, metric: BarMetric, now: Date) -> UsageWindow? {
        let windows = snapshot.windows
        switch metric {
        case .primary:
            return windows.first(where: \.isPrimary) ?? windows.first
        case .weekly:
            return mostCritical(windows.filter(\.isWeekly), now: now) ?? mostCritical(windows, now: now)
        case .mostCritical, .tokensToday:
            return mostCritical(windows, now: now)
        }
    }

    public static func value(for snapshot: ProviderSnapshot?, config: Config, now: Date) -> BarValue {
        guard let snapshot else { return BarValue(text: "…", hasData: false) }
        let window = window(for: snapshot, metric: config.metric, now: now)
        let used = window?.effectiveUsed(at: now)

        if config.metric == .tokensToday, let tokens = snapshot.tokens {
            return BarValue(text: Formatting.tokens(tokens.today.total), usedPercent: used, window: window, hasData: true)
        }
        guard let window, let used else {
            return BarValue(text: snapshot.status == .loading ? "…" : "–", hasData: false)
        }

        var text = Formatting.percent(config.showRemaining ? 100 - used : used)
        if config.showCountdown, !window.notStarted, let reset = window.resetsAt, reset > now {
            text += " · " + Formatting.compactCountdown(reset.timeIntervalSince(now))
        }
        return BarValue(text: text, usedPercent: used, window: window, hasData: true)
    }

    /// VoiceOver description of a menu bar item.
    public static func accessibilityLabel(for provider: ProviderID, value: BarValue, now: Date) -> String {
        guard value.hasData, let window = value.window else { return "\(provider.displayName): sem dados" }
        var text = "\(provider.displayName): \(window.title), \(Formatting.percent(window.effectiveUsed(at: now))) usado"
        if !window.notStarted, let reset = window.resetsAt, reset > now {
            text += ", renova em \(Formatting.countdown(reset.timeIntervalSince(now)))"
        }
        return text
    }
}

/// How the single menu bar item draws its icon.
public enum BarIconStyle: String, CaseIterable, Codable, Sendable {
    /// One small bar per provider, filled up to its usage.
    case meters
    /// The logo of the provider closest to its limit.
    case criticalLogo

    public var title: String {
        switch self {
        case .meters: "Medidores de todos os provedores"
        case .criticalLogo: "Logo do provedor mais crítico"
        }
    }
}

/// What the single menu bar item shows for all providers together.
public struct OverallBarValue: Equatable, Sendable {
    /// One provider's position in the meter icon.
    public struct Level: Equatable, Sendable {
        public var provider: ProviderID
        /// Effective usage of the provider's driving window; `nil` while there is nothing to show.
        public var usedPercent: Double?
    }

    public var text: String
    public var levels: [Level]
    /// The provider closest to a limit.
    public var critical: ProviderID?
    public var usedPercent: Double?
    public var hasData: Bool

    public var alert: AlertLevel? { usedPercent.flatMap(AlertLevel.init(usedPercent:)) }
}

extension BarPresenter {
    /// Combines every enabled provider into the single menu bar item: the number comes from the
    /// provider closest to a limit (or today's tokens summed), the meter from each provider's level.
    public static func overall(
        for snapshots: [ProviderID: ProviderSnapshot],
        providers: [ProviderID],
        config: Config,
        now: Date
    ) -> OverallBarValue {
        var levels: [OverallBarValue.Level] = []
        var critical: (provider: ProviderID, value: BarValue)?
        var tokensToday = 0
        var hasTokens = false
        var loading = false

        for provider in providers {
            let snapshot = snapshots[provider]
            if snapshot == nil || snapshot?.status == .loading { loading = true }
            if let tokens = snapshot?.tokens {
                tokensToday += tokens.today.total
                hasTokens = true
            }
            // Tools that are absent, or that report no limits, stay out of the meter.
            guard let snapshot, snapshot.status != .notInstalled, !snapshot.windows.isEmpty || snapshot.status == .loading else {
                continue
            }
            let value = value(for: snapshot, config: config, now: now)
            levels.append(OverallBarValue.Level(provider: provider, usedPercent: value.usedPercent))
            if let used = value.usedPercent, used > (critical?.value.usedPercent ?? -1) {
                critical = (provider, value)
            }
        }

        let text: String
        if config.metric == .tokensToday, hasTokens {
            text = Formatting.tokens(tokensToday)
        } else if let critical, config.metric != .tokensToday {
            text = critical.value.text
        } else if let critical {
            text = Formatting.percent(config.showRemaining ? 100 - (critical.value.usedPercent ?? 0) : critical.value.usedPercent ?? 0)
        } else {
            text = loading ? "…" : "–"
        }
        return OverallBarValue(
            text: text,
            levels: levels,
            critical: critical?.provider,
            usedPercent: critical?.value.usedPercent,
            hasData: critical != nil || (config.metric == .tokensToday && hasTokens)
        )
    }

    /// VoiceOver description of the single menu bar item.
    public static func accessibilityLabel(for overall: OverallBarValue) -> String {
        guard !overall.levels.isEmpty else { return "\(AppInfo.name): sem dados" }
        let parts = overall.levels.map { level in
            "\(level.provider.shortName) \(level.usedPercent.map(Formatting.percent) ?? "sem dados")"
        }
        return "\(AppInfo.name): " + parts.joined(separator: ", ")
    }
}
