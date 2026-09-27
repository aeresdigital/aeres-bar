import Foundation

/// How trustworthy the numbers in a snapshot are.
public enum SnapshotStatus: String, Codable, Sendable {
    /// Nothing read yet.
    case loading
    /// Limits read from the provider in the last refresh.
    case ok
    /// The last refresh failed; showing what was read before.
    case stale
    /// The last refresh failed and there is nothing to show.
    case error
    /// The tool is not on this Mac.
    case notInstalled
}

/// A label/value line in the panel (plan extras, usage split, credits…).
public struct DetailRow: Codable, Equatable, Identifiable, Sendable {
    public var label: String
    public var value: String
    public var id: String { label }

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Per-model quota, as Antigravity reports it.
public struct ModelQuota: Codable, Equatable, Identifiable, Sendable {
    public var label: String
    /// `nil` when the model reports no quota at all.
    public var remainingFraction: Double?
    public var resetsAt: Date?
    public var id: String { label }

    public init(label: String, remainingFraction: Double?, resetsAt: Date?) {
        self.label = label
        self.remainingFraction = remainingFraction
        self.resetsAt = resetsAt
    }
}

/// Everything known about one provider at a point in time.
public struct ProviderSnapshot: Codable, Equatable, Sendable {
    public var provider: ProviderID
    public var status: SnapshotStatus
    /// What went wrong in the last refresh, if anything.
    public var issue: ProviderIssue.Kind?
    /// User-facing explanation of `issue`.
    public var message: String?
    public var plan: String?
    public var account: String?
    public var windows: [UsageWindow]
    public var tokens: TokenSummary?
    public var details: [DetailRow]
    public var models: [ModelQuota]
    /// Last time the limits were read from the provider.
    public var limitsUpdatedAt: Date?
    /// Last refresh attempt, successful or not.
    public var checkedAt: Date?
    /// Where the numbers came from, for the panel footer.
    public var source: String?

    public init(
        provider: ProviderID,
        status: SnapshotStatus = .loading,
        issue: ProviderIssue.Kind? = nil,
        message: String? = nil,
        plan: String? = nil,
        account: String? = nil,
        windows: [UsageWindow] = [],
        tokens: TokenSummary? = nil,
        details: [DetailRow] = [],
        models: [ModelQuota] = [],
        limitsUpdatedAt: Date? = nil,
        checkedAt: Date? = nil,
        source: String? = nil
    ) {
        self.provider = provider
        self.status = status
        self.issue = issue
        self.message = message
        self.plan = plan
        self.account = account
        self.windows = windows
        self.tokens = tokens
        self.details = details
        self.models = models
        self.limitsUpdatedAt = limitsUpdatedAt
        self.checkedAt = checkedAt
        self.source = source
    }

    /// Records a successful read of the limits.
    public mutating func markFresh(at date: Date, source: String) {
        status = .ok
        issue = nil
        message = nil
        limitsUpdatedAt = date
        self.source = source
    }

    /// Records a failed refresh, keeping previously read limits visible.
    public mutating func markFailed(_ failure: ProviderIssue) {
        issue = failure.kind
        message = failure.message
        if failure.kind == .notInstalled {
            status = .notInstalled
        } else {
            status = limitsUpdatedAt == nil ? .error : .stale
        }
    }
}
