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
