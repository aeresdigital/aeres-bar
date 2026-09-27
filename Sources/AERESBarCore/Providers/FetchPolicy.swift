import Foundation

/// How often a provider may call its remote API.
public struct FetchPolicy: Sendable {
    /// Responses younger than this are reused on automatic refreshes; hovering the menu bar
    /// should not hit the API every time.
    public var minimumInterval: TimeInterval
    /// A manual refresh ("Atualizar") skips the reuse, but not for responses younger than this,
    /// so repeated clicks cannot flood the API.
    public var manualMinimumInterval: TimeInterval
    /// Pause after HTTP 429 when the server does not say how long to wait.
    public var defaultBackoff: TimeInterval
    /// Upper bound for a server-requested pause.
    public var maximumBackoff: TimeInterval

    public init(
        minimumInterval: TimeInterval = 60,
        manualMinimumInterval: TimeInterval = 15,
        defaultBackoff: TimeInterval = 300,
        maximumBackoff: TimeInterval = 1_800
    ) {
        self.minimumInterval = minimumInterval
        self.manualMinimumInterval = manualMinimumInterval
        self.defaultBackoff = defaultBackoff
        self.maximumBackoff = maximumBackoff
    }

    /// Whether a response fetched at `fetchedAt` may be reused for a refresh of this kind.
    public func canReuse(fetchedAt: Date, now: Date, reason: RefreshReason) -> Bool {
        now.timeIntervalSince(fetchedAt) < (reason == .manual ? manualMinimumInterval : minimumInterval)
    }

    /// When to try again after a 429: the server's `Retry-After`, clamped, or the default pause.
    public func backoffDeadline(from response: HTTPResponse, now: Date) -> Date {
        guard let requested = response.retryAfter(now: now) else { return now.addingTimeInterval(defaultBackoff) }
        let wait = min(max(requested.timeIntervalSince(now), 30), maximumBackoff)
        return now.addingTimeInterval(wait)
    }
}

/// Throttling state of one remote API, owned by a provider actor: the last good response and
/// any server-requested pause.
struct FetchState<Value> {
    private(set) var last: (value: Value, at: Date)?
    var retryAfter: Date?

    /// The last response, if the policy allows reusing it now.
    func reusable(now: Date, reason: RefreshReason, policy: FetchPolicy) -> (value: Value, at: Date)? {
        guard let last, policy.canReuse(fetchedAt: last.at, now: now, reason: reason) else { return nil }
        return last
    }

    func isBackingOff(at now: Date) -> Bool {
        (retryAfter ?? .distantPast) > now
    }

    mutating func record(_ value: Value, at date: Date) {
        last = (value, date)
    }
}
