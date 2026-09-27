import Foundation

/// GitHub Copilot: monthly quotas (premium requests, chat, completions) from GitHub's API,
/// with the GitHub login already on this Mac. Copilot exposes no token counts.
public actor CopilotProvider: UsageProvider {
    public nonisolated let id = ProviderID.copilot

    private static let endpoint = URL(string: "https://api.github.com/copilot_internal/user")

    private let http: any HTTPClient
    private let tokenSource: any GitHubTokenSource
    private let policy: FetchPolicy
    private let now: @Sendable () -> Date
    private var state = FetchState<CopilotUsageParser.Result>()

    public init(
        http: any HTTPClient = URLSessionHTTPClient.standard,
        tokenSource: any GitHubTokenSource = LocalGitHubTokenSource(),
        policy: FetchPolicy = FetchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.tokenSource = tokenSource
        self.policy = policy
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot {
        let now = now()
        var snapshot = previous ?? ProviderSnapshot(provider: .copilot)
        snapshot.checkedAt = now

        switch await usage(now: now, reason: reason) {
        case .success(let fetch):
            snapshot.windows = fetch.value.windows
            snapshot.details = fetch.value.details
            snapshot.plan = fetch.value.plan
            snapshot.markFresh(at: fetch.at, source: "API do GitHub")
        case .failure(let issue):
            snapshot.markFailed(issue)
            Log.providers.notice("Copilot: \(issue.kind.rawValue, privacy: .public)")
        }
        return snapshot
    }

    private func usage(now: Date, reason: RefreshReason) async -> Result<(value: CopilotUsageParser.Result, at: Date), ProviderIssue> {
        if let cached = state.reusable(now: now, reason: reason, policy: policy) { return .success(cached) }
        if state.isBackingOff(at: now) {
            return .failure(ProviderIssue(.rateLimited, "O GitHub pediu uma pausa nas consultas — nova tentativa em alguns minutos."))
        }
        guard let token = tokenSource.token() else {
            return .failure(
                ProviderIssue(.notInstalled, "Nenhum login do GitHub encontrado. Instale o GitHub CLI e rode “gh auth login”.")
            )
        }
        guard let endpoint = Self.endpoint else {
            return .failure(ProviderIssue(.invalidResponse, "Endereço da API do GitHub inválido."))
        }

        var request = URLRequest(url: endpoint)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            return .failure(ProviderIssue(.network, "Sem conexão com o GitHub. Mostrando os últimos dados."))
        }
        switch response.status {
        case 200:
            guard let result = CopilotUsageParser.parse(response.body) else {
                return .failure(ProviderIssue(.invalidResponse, "O GitHub respondeu num formato inesperado."))
            }
            state.record(result, at: now)
            return .success((result, now))
        case 401:
            return .failure(ProviderIssue(.unauthorized, "O GitHub recusou o login. Rode “gh auth login” de novo."))
        case 403 where response.headers["x-ratelimit-remaining"] == "0", 429:
            state.retryAfter = policy.backoffDeadline(from: response, now: now)
            return .failure(ProviderIssue(.rateLimited, "O GitHub pediu uma pausa nas consultas — nova tentativa em alguns minutos."))
        case 403, 404:
            return .failure(ProviderIssue(.notSignedIn, "Esta conta do GitHub não tem o Copilot ativo."))
        default:
            return .failure(ProviderIssue(.invalidResponse, "O GitHub respondeu HTTP \(response.status). Mostrando os últimos dados."))
        }
    }
}
