import Foundation

/// One rate-limit window reported by a provider, such as the 5-hour session or the weekly cap.
public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    /// Stable identifier within a provider (e.g. `session`, `weekly_all`).
    public var id: String
    /// User-facing name, e.g. "Sessão (5h)".
    public var title: String
    /// Optional second line, e.g. which models share the bucket.
    public var subtitle: String?
    /// Share of the window already consumed, from 0 to 100.
    public var usedPercent: Double
    /// When the window renews, if the provider says.
    public var resetsAt: Date?
    /// Length of the window in seconds, when known.
    public var windowSeconds: Double?
    /// The provider reports an untouched window whose clock only starts on the next request;
    /// its `resetsAt` moves with every read and must not be shown as a countdown.
    public var notStarted: Bool
    /// The provider's main (shortest) window.
    public var isPrimary: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        usedPercent: Double,
        resetsAt: Date? = nil,
        windowSeconds: Double? = nil,
        notStarted: Bool = false,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
        self.notStarted = notStarted
        self.isPrimary = isPrimary
    }

    /// Whether the renewal time has already passed.
    public func hasReset(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// Usage as it stands at `now`: a window past its renewal time is back to zero,
    /// even if we could not read the provider since.
    public func effectiveUsed(at now: Date) -> Double {
        hasReset(at: now) ? 0 : min(max(usedPercent, 0), 100)
    }

    /// Windows of six days or more count as weekly.
    public var isWeekly: Bool { (windowSeconds ?? 0) >= 6 * 86_400 }

    /// When the running window began, if it is running.
    public func start(now: Date) -> Date? {
        guard !notStarted, let resetsAt, resetsAt > now, let windowSeconds else { return nil }
        return resetsAt.addingTimeInterval(-windowSeconds)
    }
}
