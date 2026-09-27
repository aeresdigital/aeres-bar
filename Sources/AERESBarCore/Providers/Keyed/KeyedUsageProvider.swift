import Foundation

/// What a service read with an API key reports, ready for the snapshot.
public struct KeyedReading: Equatable, Sendable {
    public var plan: String?
    public var windows: [UsageWindow]
    public var details: [DetailRow]

    public init(plan: String? = nil, windows: [UsageWindow] = [], details: [DetailRow] = []) {
        self.plan = plan
        self.windows = windows
        self.details = details
    }
}

/// Where and how to read a service accessed with an API key the user gives (the services with
/// no local login to reuse): OpenRouter and the Chinese model platforms.
public struct KeyedService: Sendable {
    /// A host that serves the API. Keys of these platforms only work in the region that issued
    /// them (international or mainland China), so each region is tried until one accepts the key.
    public struct Region: Sendable {
        public var name: String
        public var baseURL: String

        public init(_ name: String, _ baseURL: String) {
            self.name = name
            self.baseURL = baseURL
        }
    }

    public var provider: ProviderID
    public var account: SecretAccount
    /// The service's name in messages ("O DeepSeek pediu uma pausa…").
    public var name: String
    /// Where the numbers come from, for the panel.
    public var source: String
    public var regions: [Region]
    /// The request that must succeed, for a region's base URL and the key.
    public var request: @Sendable (_ base: URL, _ key: String) -> URLRequest
    /// Optional extras (a balance that needs another kind of key…): their failures are ignored.
    public var extras: @Sendable (_ base: URL, _ key: String) -> [URLRequest]
    /// Reads the main answer and the extras that came back (`nil` where one failed); `nil` when
    /// the main answer is not what the service should send.
    public var read: @Sendable (_ main: Data, _ extras: [Data?], _ now: Date) -> KeyedReading?
    /// Some APIs answer HTTP 200 with the error in the body.
    public var errorInBody: @Sendable (_ body: Data) -> ProviderIssue.Kind?

    public init(
        provider: ProviderID,
        account: SecretAccount,
        name: String,
        source: String,
        regions: [Region],
        request: @escaping @Sendable (_ base: URL, _ key: String) -> URLRequest,
        extras: @escaping @Sendable (_ base: URL, _ key: String) -> [URLRequest] = { _, _ in [] },
        read: @escaping @Sendable (_ main: Data, _ extras: [Data?], _ now: Date) -> KeyedReading?,
        errorInBody: @escaping @Sendable (_ body: Data) -> ProviderIssue.Kind? = { _ in nil }
    ) {
        self.provider = provider
        self.account = account
        self.name = name
        self.source = source
        self.regions = regions
        self.request = request
        self.extras = extras
        self.read = read
        self.errorInBody = errorInBody
    }

    /// `GET` with `Authorization: Bearer <key>`, JSON accepted and AERES Bar's user agent.
    public static func get(_ url: URL, key: String, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }
}

/// Reads a ``KeyedService``: owns its key's throttling state, finds the region the key belongs
/// to and turns HTTP answers into snapshot states.
public actor KeyedUsageProvider: UsageProvider {
    public nonisolated let id: ProviderID

    /// The raw answers, kept so that windows depending on the clock are recomputed every refresh.
    struct Answers: Sendable {
        var main: Data
        var extras: [Data?]
    }

    private let service: KeyedService
    private let http: any HTTPClient
    private let secrets: any SecretStore
    private let policy: FetchPolicy
    private let now: @Sendable () -> Date
    private var state = FetchState<Answers>()
    /// The key the cached answers belong to.
    private var keyInUse: String?
    /// The region that accepted the key.
    private var regionInUse: Int?

    public init(
        service: KeyedService,
        http: any HTTPClient = URLSessionHTTPClient.standard,
        secrets: any SecretStore = KeychainSecretStore(),
        policy: FetchPolicy = FetchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.id = service.provider
        self.service = service
        self.http = http
        self.secrets = secrets
        self.policy = policy
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot {
        let now = now()
        let key = secrets.secret(for: service.account)
        // Another key (or none) has other limits: forget what the previous one read.
        let keyChanged = keyInUse != nil && key != keyInUse
        if keyChanged || key == nil {
            state = FetchState()
            regionInUse = nil
        }
        keyInUse = key

        var snapshot = (keyChanged || key == nil ? nil : previous) ?? ProviderSnapshot(provider: id)
        snapshot.checkedAt = now
        guard let key else {
            snapshot.markFailed(ProviderIssue(.notInstalled, "Defina a chave da API do \(service.name) em Ajustes › Chaves de API."))
            return snapshot
        }

        switch await answers(key: key, now: now, reason: reason) {
        case .success(let fetch):
            guard let reading = service.read(fetch.value.main, fetch.value.extras, now) else {
                snapshot.markFailed(invalidFormat)
                return snapshot
            }
            snapshot.plan = reading.plan
            snapshot.windows = reading.windows
            snapshot.details = reading.details
            snapshot.markFresh(at: fetch.at, source: service.source)
        case .failure(let issue):
            snapshot.markFailed(issue)
            Log.providers.notice("\(self.service.name, privacy: .public): \(issue.kind.rawValue, privacy: .public)")
        }
        return snapshot
    }

    private var invalidFormat: ProviderIssue {
        ProviderIssue(.invalidResponse, "O \(service.name) respondeu num formato inesperado.")
    }

    private var rateLimited: ProviderIssue {
        ProviderIssue(.rateLimited, "O \(service.name) pediu uma pausa nas consultas — nova tentativa em alguns minutos.")
    }

    private func answers(key: String, now: Date, reason: RefreshReason) async -> Result<(value: Answers, at: Date), ProviderIssue> {
        if let cached = state.reusable(now: now, reason: reason, policy: policy) { return .success(cached) }
        if state.isBackingOff(at: now) { return .failure(rateLimited) }

        // The region that accepted the key before, or each one in turn.
        let order = regionInUse.map { [$0] } ?? Array(service.regions.indices)
        var refused = false
        var unreachable = false
        for index in order {
            guard let base = URL(string: service.regions[index].baseURL) else { continue }
            let response: HTTPResponse
            do {
                response = try await http.send(service.request(base, key))
            } catch {
                unreachable = true
                continue  // another region may be reachable from here
            }
            let bodyIssue = response.status == 200 ? service.errorInBody(response.body) : nil
            switch (response.status, bodyIssue) {
            case (200, nil):
                var extras: [Data?] = []
                for request in service.extras(base, key) {
                    let answer = try? await http.send(request)
                    extras.append(answer?.status == 200 ? answer?.body : nil)
                }
                let answers = Answers(main: response.body, extras: extras)
                guard service.read(answers.main, answers.extras, now) != nil else { return .failure(invalidFormat) }
                regionInUse = index
                state.record(answers, at: now)
                return .success((answers, now))
            case (401, _), (403, _), (200, .unauthorized):
                refused = true
                continue  // the key may belong to another region
            case (429, _), (200, .rateLimited):
                state.retryAfter = policy.backoffDeadline(from: response, now: now)
                return .failure(rateLimited)
            case (200, _):
                return .failure(invalidFormat)
            default:
                return .failure(
                    ProviderIssue(.invalidResponse, "O \(service.name) respondeu HTTP \(response.status). Mostrando os últimos dados.")
                )
            }
        }
        regionInUse = nil  // a revoked key or a new network: look everywhere next time
        if refused {
            return .failure(ProviderIssue(.unauthorized, "A chave do \(service.name) foi recusada — confira em Ajustes › Chaves de API."))
        }
        if unreachable {
            return .failure(ProviderIssue(.network, "Sem conexão com o \(service.name). Mostrando os últimos dados."))
        }
        return .failure(invalidFormat)
    }
}
