import Foundation

/// Claude Code: limits from Anthropic's OAuth usage API, tokens from local transcripts.
public actor ClaudeProvider: UsageProvider {
    public nonisolated let id = ProviderID.claude

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")

    private let http: any HTTPClient
    private let credentialSource: any ClaudeCredentialSource
    private let scanner: ClaudeLogScanner
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let policy: FetchPolicy
    private var credentials: ClaudeCredentials?
    private var retryAfter: Date?
    private var lastFetch: (result: ClaudeUsageParser.Result, at: Date)?

    public init(
        http: any HTTPClient = URLSessionHTTPClient.standard,
        credentialSource: any ClaudeCredentialSource = KeychainClaudeCredentialSource(),
        logRoots: [URL] = DataLocations.claudeProjectRoots,
        calendar: Calendar = .current,
        policy: FetchPolicy = FetchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.credentialSource = credentialSource
        self.scanner = ClaudeLogScanner(roots: logRoots)
        self.calendar = calendar
        self.policy = policy
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?) async -> ProviderSnapshot {
        let now = now()
        var snapshot = previous ?? ProviderSnapshot(provider: .claude)
        snapshot.checkedAt = now

        switch await limits(now: now) {
        case .success(let fetch):
            snapshot.windows = fetch.result.windows
            snapshot.details = fetch.result.details
            snapshot.markFresh(at: fetch.at, source: "API da Anthropic + logs locais")
        case .failure(let issue):
            // Without a login but with transcripts, tokens are still worth showing.
            let adjusted = issue.kind == .notInstalled && scanner.hasLogs ? ProviderIssue(.notSignedIn, issue.message) : issue
            snapshot.markFailed(adjusted)
            Log.providers.notice("Claude: \(adjusted.kind.rawValue, privacy: .public)")
        }
        if let credentials {
            snapshot.plan = ClaudeUsageParser.planName(subscription: credentials.subscriptionType, tier: credentials.rateLimitTier)
        }

        scanner.update(now: now)
        let session = snapshot.windows.first { $0.id == "session" }
        let weekly = snapshot.windows.first { $0.id == "weekly_all" } ?? snapshot.windows.first(where: \.isWeekly)
        snapshot.tokens = scanner.summary(
            now: now,
            calendar: calendar,
            sessionStart: session?.start(now: now),
            weekStart: weekly?.start(now: now)
        )
        return snapshot
    }

    /// The last response while it is recent, otherwise a new request.
    private func limits(now: Date) async -> Result<(result: ClaudeUsageParser.Result, at: Date), ProviderIssue> {
        if let lastFetch, now.timeIntervalSince(lastFetch.at) < policy.minimumInterval {
            return .success(lastFetch)
        }
        let outcome = await fetchLimits(now: now)
        if case .success(let result) = outcome { lastFetch = (result, now) }
        return outcome.map { ($0, now) }
    }

    private func fetchLimits(now: Date) async -> Result<ClaudeUsageParser.Result, ProviderIssue> {
        if let retryAfter, retryAfter > now {
            return .failure(ProviderIssue(.rateLimited, "Muitas consultas seguidas à Anthropic — nova tentativa em alguns minutos."))
        }
        // Claude Code rotates its token; re-read it whenever ours is missing or expired.
        if credentials?.isExpired(at: now) ?? true {
            credentials = credentialSource.load()
        }
        guard let credentials else {
            return .failure(ProviderIssue(.notInstalled, "Login do Claude Code não encontrado. Rode “claude” no Terminal e faça login."))
        }
        guard !credentials.isExpired(at: now) else {
            return .failure(
                ProviderIssue(
                    .credentialsExpired,
                    "A credencial do Claude Code expirou (ela é renovada sempre que você usa o Claude Code). Mostrando os últimos limites lidos."
                )
            )
        }
        guard let endpoint = Self.endpoint else {
            return .failure(ProviderIssue(.invalidResponse, "Endereço da API da Anthropic inválido."))
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            return .failure(ProviderIssue(.network, "Sem conexão com a Anthropic. Mostrando os últimos dados."))
        }
        switch response.status {
        case 200:
            guard let result = ClaudeUsageParser.parse(response.body) else {
                return .failure(ProviderIssue(.invalidResponse, "A Anthropic respondeu num formato inesperado."))
            }
            return .success(result)
        case 401, 403:
            self.credentials = nil
            return .failure(
                ProviderIssue(.unauthorized, "A Anthropic recusou a credencial do Claude Code. Use o Claude Code para renová-la."))
        case 429:
            let until = policy.backoffDeadline(from: response, now: now)
            retryAfter = until
            return .failure(
                ProviderIssue(
                    .rateLimited,
                    "A Anthropic pediu uma pausa nas consultas — nova tentativa em \(Formatting.countdown(until.timeIntervalSince(now)))."
                )
            )
        default:
            return .failure(ProviderIssue(.invalidResponse, "A Anthropic respondeu HTTP \(response.status). Mostrando os últimos dados."))
        }
    }
}
