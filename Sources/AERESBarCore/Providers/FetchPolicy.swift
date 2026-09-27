import Foundation

/// How often a provider may call its remote API.
public struct FetchPolicy: Sendable {
    /// Responses younger than this are reused; hovering the menu bar should not hit the API every time.
    public var minimumInterval: TimeInterval
    /// Pause after HTTP 429 when the server does not say how long to wait.
    public var defaultBackoff: TimeInterval
    /// Upper bound for a server-requested pause.
    public var maximumBackoff: TimeInterval

    public init(minimumInterval: TimeInterval = 60, defaultBackoff: TimeInterval = 300, maximumBackoff: TimeInterval = 1_800) {
        self.minimumInterval = minimumInterval
        self.defaultBackoff = defaultBackoff
        self.maximumBackoff = maximumBackoff
    }

    /// When to try again after a 429: the server's `Retry-After`, clamped, or the default pause.
    public func backoffDeadline(from response: HTTPResponse, now: Date) -> Date {
        guard let requested = response.retryAfter(now: now) else { return now.addingTimeInterval(defaultBackoff) }
        let wait = min(max(requested.timeIntervalSince(now), 30), maximumBackoff)
        return now.addingTimeInterval(wait)
    }
}
