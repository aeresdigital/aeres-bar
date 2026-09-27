import Foundation

/// Codex: limits from the ChatGPT usage API (falling back to the last limits logged by the CLI),
/// tokens from local rollouts.
public actor CodexProvider: UsageProvider {
    public nonisolated let id = ProviderID.codex

    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")

    private let home: URL
    private let http: any HTTPClient
    private let scanner: CodexLogScanner
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let policy: FetchPolicy
    private var state = FetchState<CodexUsageParser.Result>()

    public init(
        home: URL = DataLocations.codexHome,
        http: any HTTPClient = URLSessionHTTPClient.standard,
        calendar: Calendar = .current,
        policy: FetchPolicy = FetchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.home = home
        self.http = http
        self.scanner = CodexLogScanner(home: home)
        self.calendar = calendar
        self.policy = policy
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot {
        let now = now()
        var snapshot = previous ?? ProviderSnapshot(provider: .codex)
        snapshot.checkedAt = now

        guard FileManager.default.fileExists(atPath: home.path) else {
            snapshot.markFailed(ProviderIssue(.notInstalled, "Codex não encontrado neste Mac (pasta ~/.codex ausente)."))
            return snapshot
        }

        scanner.update(now: now)

        switch await limits(now: now, reason: reason) {
        case .success(let fetch):
            snapshot.windows = fetch.value.windows
            snapshot.details = fetch.value.details
            snapshot.plan = fetch.value.plan ?? snapshot.plan
            snapshot.account = fetch.value.email
            snapshot.markFresh(at: fetch.at, source: "API do ChatGPT + logs locais")
        case .failure(let issue):
            // Rollouts carry the limits as of each turn, which beats an older cache.
            if let sample = scanner.latestRateLimits, sample.time > (snapshot.limitsUpdatedAt ?? .distantPast) {
                snapshot.windows = sample.windows
                snapshot.plan = sample.plan.map(CodexUsageParser.planName) ?? snapshot.plan
                snapshot.limitsUpdatedAt = sample.time
                snapshot.source = "Logs locais do Codex"
            }
            snapshot.markFailed(issue)
            Log.providers.notice("Codex: \(issue.kind.rawValue, privacy: .public)")
        }

        let session = snapshot.windows.first { $0.windowSeconds.map { abs($0 - 18_000) < 60 } ?? false }
        let weekly = snapshot.windows.first(where: \.isWeekly)
        snapshot.tokens = scanner.summary(
            now: now,
            calendar: calendar,
            sessionStart: session?.start(now: now),
            weekStart: weekly?.start(now: now)
        )
        return snapshot
    }

    /// The last response while the policy allows reusing it, otherwise a new request.
    private func limits(now: Date, reason: RefreshReason) async -> Result<(value: CodexUsageParser.Result, at: Date), ProviderIssue> {
        if let cached = state.reusable(now: now, reason: reason, policy: policy) { return .success(cached) }
        let outcome = await fetchLimits(now: now)
        if case .success(let result) = outcome { state.record(result, at: now) }
        return outcome.map { ($0, now) }
    }

    private func fetchLimits(now: Date) async -> Result<CodexUsageParser.Result, ProviderIssue> {
        if state.isBackingOff(at: now) {
            return .failure(ProviderIssue(.rateLimited, "Muitas consultas seguidas ao ChatGPT — nova tentativa em alguns minutos."))
        }
        guard let auth = CodexAuth.load(home: home) else {
            return .failure(ProviderIssue(.notSignedIn, "Codex sem login com o ChatGPT. Rode “codex login” no Terminal."))
        }
        if let expiresAt = auth.expiresAt, expiresAt <= now {
            return .failure(
                ProviderIssue(
                    .credentialsExpired,
                    "A sessão do Codex expirou; abra o Codex para renová-la. Mostrando o último limite registrado nos logs."
                )
            )
        }
        guard let endpoint = Self.endpoint else {
            return .failure(ProviderIssue(.invalidResponse, "Endereço da API do ChatGPT inválido."))
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            return .failure(ProviderIssue(.network, "Sem conexão com o ChatGPT. Mostrando os últimos dados."))
        }
        switch response.status {
        case 200:
            guard let result = CodexUsageParser.parse(response.body, now: now) else {
                return .failure(ProviderIssue(.invalidResponse, "O ChatGPT respondeu num formato inesperado."))
            }
            return .success(result)
        case 401, 403:
            return .failure(ProviderIssue(.unauthorized, "O ChatGPT recusou a sessão do Codex. Abra o Codex para renová-la."))
        case 429:
            let until = policy.backoffDeadline(from: response, now: now)
            state.retryAfter = until
            Log.providers.notice("Codex: HTTP 429, Retry-After=\(response.headers["retry-after"] ?? "-", privacy: .public)")
            return .failure(
                ProviderIssue(
                    .rateLimited,
                    "O ChatGPT pediu uma pausa nas consultas — nova tentativa em \(Formatting.countdown(until.timeIntervalSince(now)))."
                )
            )
        default:
            return .failure(ProviderIssue(.invalidResponse, "O ChatGPT respondeu HTTP \(response.status). Mostrando os últimos dados."))
        }
    }
}
