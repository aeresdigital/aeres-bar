import Foundation

/// OpenRouter: the API key's spending cap, free-model allowance, spend and (with a management key)
/// the credit balance.
public actor OpenRouterProvider: UsageProvider {
    public nonisolated let id = ProviderID.openrouter

    private static let keyEndpoint = URL(string: "https://openrouter.ai/api/v1/key")
    private static let creditsEndpoint = URL(string: "https://openrouter.ai/api/v1/credits")

    private let http: any HTTPClient
    private let secrets: any SecretStore
    private let policy: FetchPolicy
    private let now: @Sendable () -> Date
    private var state = FetchState<(key: OpenRouterParser.KeyInfo, credits: OpenRouterParser.Credits?)>()
    /// The key the cached response belongs to.
    private var keyInUse: String?

    public init(
        http: any HTTPClient = URLSessionHTTPClient.standard,
        secrets: any SecretStore = KeychainSecretStore(),
        policy: FetchPolicy = FetchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.secrets = secrets
        self.policy = policy
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot {
        let now = now()
        let apiKey = secrets.secret(for: .openRouter)
        // Another key (or none) has other limits: forget what the previous one read.
        let keyChanged = keyInUse != nil && apiKey != keyInUse
        if keyChanged || apiKey == nil { state = FetchState() }
        keyInUse = apiKey

        var snapshot = (keyChanged || apiKey == nil ? nil : previous) ?? ProviderSnapshot(provider: .openrouter)
        snapshot.checkedAt = now
        guard let apiKey else {
            snapshot.markFailed(ProviderIssue(.notInstalled, "Defina a chave da API do OpenRouter em Ajustes › Chaves de API."))
            return snapshot
        }
        switch await usage(apiKey: apiKey, now: now, reason: reason) {
        case .success(let fetch):
            snapshot.windows = OpenRouterParser.windows(for: fetch.value.key, now: now)
            snapshot.details = OpenRouterParser.details(for: fetch.value.key, credits: fetch.value.credits)
            snapshot.plan = fetch.value.key.isFreeTier ? "Gratuito" : nil
            snapshot.markFresh(at: fetch.at, source: "API do OpenRouter")
        case .failure(let issue):
            snapshot.markFailed(issue)
            Log.providers.notice("OpenRouter: \(issue.kind.rawValue, privacy: .public)")
        }
        return snapshot
    }

    private func usage(
        apiKey: String,
        now: Date,
        reason: RefreshReason
    ) async -> Result<(value: (key: OpenRouterParser.KeyInfo, credits: OpenRouterParser.Credits?), at: Date), ProviderIssue> {
        if let cached = state.reusable(now: now, reason: reason, policy: policy) { return .success(cached) }
        if state.isBackingOff(at: now) {
            return .failure(ProviderIssue(.rateLimited, "O OpenRouter pediu uma pausa nas consultas — nova tentativa em alguns minutos."))
        }
        guard let keyEndpoint = Self.keyEndpoint else {
            return .failure(ProviderIssue(.invalidResponse, "Endereço da API do OpenRouter inválido."))
        }

        let response: HTTPResponse
        do {
            response = try await http.send(request(keyEndpoint, apiKey: apiKey))
        } catch {
            return .failure(ProviderIssue(.network, "Sem conexão com o OpenRouter. Mostrando os últimos dados."))
        }
        switch response.status {
        case 200:
            guard let key = OpenRouterParser.parseKey(response.body) else {
                return .failure(ProviderIssue(.invalidResponse, "O OpenRouter respondeu num formato inesperado."))
            }
            // The balance needs a management key; with a regular key this simply fails and is skipped.
            var credits: OpenRouterParser.Credits?
            if let creditsEndpoint = Self.creditsEndpoint,
                let answer = try? await http.send(request(creditsEndpoint, apiKey: apiKey)), answer.status == 200
            {
                credits = OpenRouterParser.parseCredits(answer.body)
            }
            state.record((key, credits), at: now)
            return .success(((key, credits), now))
        case 401, 403:
            return .failure(ProviderIssue(.unauthorized, "A chave do OpenRouter foi recusada — confira em Ajustes › Chaves de API."))
        case 429:
            state.retryAfter = policy.backoffDeadline(from: response, now: now)
            return .failure(ProviderIssue(.rateLimited, "O OpenRouter pediu uma pausa nas consultas — nova tentativa em alguns minutos."))
        default:
            return .failure(ProviderIssue(.invalidResponse, "O OpenRouter respondeu HTTP \(response.status). Mostrando os últimos dados."))
        }
    }

    private func request(_ url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.name, forHTTPHeaderField: "X-Title")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
