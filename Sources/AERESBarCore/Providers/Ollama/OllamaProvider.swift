import Foundation

/// Ollama: cloud limits (5-hour session and weekly) from ollama.com with the user's API key,
/// plus the local server's status and loaded models. Local models have no limits.
public actor OllamaProvider: UsageProvider {
    public nonisolated let id = ProviderID.ollama

    private static let cloudEndpoint = URL(string: "https://ollama.com/api/usage")

    private let cloudHTTP: any HTTPClient
    private let localHTTP: any HTTPClient
    private let secrets: any SecretStore
    private let server: URL
    private let installations: [URL]
    private let policy: FetchPolicy
    private let now: @Sendable () -> Date
    private var state = FetchState<[UsageWindow]>()
    /// The key the cached response belongs to.
    private var keyInUse: String?

    public init(
        cloudHTTP: any HTTPClient = URLSessionHTTPClient.standard,
        localHTTP: any HTTPClient = URLSessionHTTPClient.loopback,
        secrets: any SecretStore = KeychainSecretStore(),
        server: URL = DataLocations.ollamaServer,
        installations: [URL] = DataLocations.ollamaInstallations,
        policy: FetchPolicy = FetchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cloudHTTP = cloudHTTP
        self.localHTTP = localHTTP
        self.secrets = secrets
        self.server = server
        self.installations = installations
        self.policy = policy
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot {
        let now = now()
        let key = secrets.secret(for: .ollama)
        // Another key (or none) has other limits: forget what the previous one read.
        let keyChanged = keyInUse != nil && key != keyInUse
        if keyChanged || key == nil { state = FetchState() }
        keyInUse = key

        var snapshot = (keyChanged || key == nil ? nil : previous) ?? ProviderSnapshot(provider: .ollama)
        snapshot.checkedAt = now
        let local = await localStatus()
        let installed = key != nil || local != nil || installations.contains { FileManager.default.fileExists(atPath: $0.path) }
        guard installed else {
            snapshot.markFailed(
                ProviderIssue(
                    .notInstalled, "Ollama não encontrado. Para acompanhar o Ollama Cloud, defina a chave em Ajustes › Chaves de API.")
            )
            return snapshot
        }

        snapshot.details = local.map(Self.details(for:)) ?? []
        guard let key else {
            // Local only: no limits to show, but the server status is worth it.
            if local != nil {
                snapshot.markFresh(at: now, source: "Servidor local do Ollama")
                snapshot.message =
                    "Modelos locais não têm limite. Para ver os limites do Ollama Cloud, defina a chave em Ajustes › Chaves de API."
            } else {
                snapshot.markFailed(
                    ProviderIssue(
                        .sourceUnavailable,
                        "O servidor do Ollama está parado. Abra o Ollama ou defina a chave do Ollama Cloud em Ajustes › Chaves de API."
                    )
                )
            }
            return snapshot
        }

        switch await cloudUsage(key: key, now: now, reason: reason) {
        case .success(let fetch):
            snapshot.windows = fetch.value
            snapshot.markFresh(at: fetch.at, source: local == nil ? "Ollama Cloud" : "Ollama Cloud + servidor local")
        case .failure(let issue):
            snapshot.markFailed(issue)
            Log.providers.notice("Ollama: \(issue.kind.rawValue, privacy: .public)")
        }
        return snapshot
    }

    /// Version and loaded models, or `nil` when the local server is not running.
    private func localStatus() async -> (version: String, models: [OllamaParser.LoadedModel])? {
        guard let versionData = try? await get(server.appendingPathComponent("api/version")),
            let version = OllamaParser.parseVersion(versionData)
        else { return nil }
        let models = (try? await get(server.appendingPathComponent("api/ps"))).flatMap(OllamaParser.parseLoadedModels) ?? []
        return (version, models)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let response = try await localHTTP.send(request)
        guard response.status == 200 else { throw URLError(.badServerResponse) }
        return response.body
    }

    private static func details(for local: (version: String, models: [OllamaParser.LoadedModel])) -> [DetailRow] {
        var rows = [DetailRow(label: "Servidor local", value: "v\(local.version) · em execução")]
        if local.models.isEmpty {
            rows.append(DetailRow(label: "Modelos carregados", value: "nenhum"))
        } else {
            let names = local.models.map {
                "\($0.name) (\(ByteCountFormatter.string(fromByteCount: Int64($0.sizeBytes), countStyle: .memory)))"
            }
            rows.append(DetailRow(label: "Modelos carregados", value: names.joined(separator: " · ")))
        }
        return rows
    }

    private func cloudUsage(key: String, now: Date, reason: RefreshReason) async -> Result<(value: [UsageWindow], at: Date), ProviderIssue>
    {
        if let cached = state.reusable(now: now, reason: reason, policy: policy) { return .success(cached) }
        if state.isBackingOff(at: now) {
            return .failure(ProviderIssue(.rateLimited, "O Ollama Cloud pediu uma pausa nas consultas — nova tentativa em alguns minutos."))
        }
        guard let endpoint = Self.cloudEndpoint else {
            return .failure(ProviderIssue(.invalidResponse, "Endereço do Ollama Cloud inválido."))
        }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        let response: HTTPResponse
        do {
            response = try await cloudHTTP.send(request)
        } catch {
            return .failure(ProviderIssue(.network, "Sem conexão com o Ollama Cloud. Mostrando os últimos dados."))
        }
        switch response.status {
        case 200:
            guard let windows = OllamaParser.parseCloudUsage(response.body) else {
                return .failure(ProviderIssue(.invalidResponse, "O Ollama Cloud respondeu num formato inesperado."))
            }
            state.record(windows, at: now)
            return .success((windows, now))
        case 401, 403:
            return .failure(ProviderIssue(.unauthorized, "A chave do Ollama Cloud foi recusada — confira em Ajustes › Chaves de API."))
        case 429:
            state.retryAfter = policy.backoffDeadline(from: response, now: now)
            return .failure(ProviderIssue(.rateLimited, "O Ollama Cloud pediu uma pausa nas consultas — nova tentativa em alguns minutos."))
        default:
            return .failure(
                ProviderIssue(.invalidResponse, "O Ollama Cloud respondeu HTTP \(response.status). Mostrando os últimos dados."))
        }
    }
}
