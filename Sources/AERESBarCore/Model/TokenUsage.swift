import Foundation

/// Token totals for a period, split the way providers bill them.
public struct TokenCounts: Codable, Equatable, Sendable {
    /// Input tokens that were not served from the prompt cache.
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    /// Number of model responses.
    public var requests: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, requests: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.requests = requests
    }

    public var total: Int { input + output + cacheRead + cacheWrite }

    public mutating func add(_ other: TokenCounts) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite += other.cacheWrite
        requests += other.requests
    }
}

/// Token usage read from local logs, over the periods the panel shows.
public struct TokenSummary: Codable, Equatable, Sendable {
    /// Tokens inside the running short (5-hour) window, when the provider has one.
    public var session: TokenCounts?
    public var today: TokenCounts
    public var week: TokenCounts
    /// `true` when `week` covers the last 7 days rather than the provider's own weekly window.
    public var weekIsRolling: Bool
    public var lastActivity: Date?

    public init(
        session: TokenCounts? = nil,
        today: TokenCounts = TokenCounts(),
        week: TokenCounts = TokenCounts(),
        weekIsRolling: Bool = true,
        lastActivity: Date? = nil
    ) {
        self.session = session
        self.today = today
        self.week = week
        self.weekIsRolling = weekIsRolling
        self.lastActivity = lastActivity
    }

    /// Whether any period has tokens at all.
    public var isEmpty: Bool {
        today.total == 0 && week.total == 0 && (session?.total ?? 0) == 0
    }
}
