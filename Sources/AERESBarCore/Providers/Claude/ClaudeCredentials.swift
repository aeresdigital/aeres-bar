import Foundation

/// The OAuth login Claude Code keeps for claude.ai subscriptions.
public struct ClaudeCredentials: Equatable, Sendable {
    public var accessToken: String
    public var expiresAt: Date?
    public var subscriptionType: String?
    public var rateLimitTier: String?

    public init(accessToken: String, expiresAt: Date? = nil, subscriptionType: String? = nil, rateLimitTier: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// Treats tokens within 30 s of expiry as expired, so a request never races the deadline.
    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(30)
    }

    /// Parses Claude Code's credential JSON (`{"claudeAiOauth": {...}}`).
    public static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let root = JSON.object(data),
            let oauth = JSON.dict(root["claudeAiOauth"]),
            let token = JSON.string(oauth["accessToken"])
        else { return nil }
        return ClaudeCredentials(
            accessToken: token,
            expiresAt: JSON.double(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1_000) },
            subscriptionType: JSON.string(oauth["subscriptionType"]),
            rateLimitTier: JSON.string(oauth["rateLimitTier"])
        )
    }
}

/// Supplies Claude Code's current credentials.
public protocol ClaudeCredentialSource: Sendable {
    func load() -> ClaudeCredentials?
}

/// Reads the Keychain item "Claude Code-credentials" through `/usr/bin/security`, falling back
/// to `~/.claude/.credentials.json`. Claude Code creates the item with the `security` tool, so
/// reading it the same way does not trigger a Keychain prompt. Tokens are never logged or stored.
public struct KeychainClaudeCredentialSource: ClaudeCredentialSource {
    private let runner: any CommandRunner
    private let fallbackFile: URL

    public init(runner: any CommandRunner = ProcessCommandRunner(), fallbackFile: URL = DataLocations.claudeCredentialsFile) {
        self.runner = runner
        self.fallbackFile = fallbackFile
    }

    public func load() -> ClaudeCredentials? {
        if let output = runner.run(
            "/usr/bin/security",
            ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
            timeout: 8
        ),
            output.status == 0,
            let credentials = ClaudeCredentials.parse(output.stdout)
        {
            return credentials
        }
        guard let data = try? Data(contentsOf: fallbackFile) else { return nil }
        return ClaudeCredentials.parse(data)
    }
}
