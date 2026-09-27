import Foundation

/// Where Antigravity is installed, if anywhere.
public struct AntigravityInstallation: Sendable {
    public var applicationCandidates: [URL]
    public var dataDirectory: URL

    public init(
        applicationCandidates: [URL] = DataLocations.antigravityApplications,
        dataDirectory: URL = DataLocations.antigravityData
    ) {
        self.applicationCandidates = applicationCandidates
        self.dataDirectory = dataDirectory
    }

    public var applicationURL: URL? {
        applicationCandidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public var isInstalled: Bool {
        applicationURL != nil || FileManager.default.fileExists(atPath: dataDirectory.path)
    }
}

/// Antigravity: quotas from the language server it runs on 127.0.0.1 while open.
/// Antigravity exposes no token counts.
public actor AntigravityProvider: UsageProvider {
    public nonisolated let id = ProviderID.antigravity

    struct Endpoint: Equatable {
        var pid: Int32
        var port: Int
        var scheme: String
        var csrfToken: String
    }

    private static let service = "exa.language_server_pb.LanguageServerService"
    private static let requestBody = Data(#"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}"#.utf8)

    private let http: any HTTPClient
    private let locator: LanguageServerLocator
    private let installation: AntigravityInstallation
    private let now: @Sendable () -> Date
    private var endpoint: Endpoint?

    public init(
        http: any HTTPClient = URLSessionHTTPClient.loopback,
        locator: LanguageServerLocator = LanguageServerLocator(),
        installation: AntigravityInstallation = AntigravityInstallation(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.locator = locator
        self.installation = installation
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?) async -> ProviderSnapshot {
        let now = now()
        var snapshot = previous ?? ProviderSnapshot(provider: .antigravity)
        snapshot.checkedAt = now

        switch await fetch() {
        case .success(let (status, windows)):
            snapshot.windows = windows
            snapshot.models = status?.models ?? []
            snapshot.plan = status?.plan ?? snapshot.plan
            snapshot.account = status?.email
            snapshot.details = []
            snapshot.markFresh(at: now, source: "Language server local do Antigravity")
        case .failure(let issue):
            snapshot.markFailed(issue)
            Log.providers.notice("Antigravity: \(issue.kind.rawValue, privacy: .public)")
        }
        return snapshot
    }

    private func fetch() async -> Result<(AntigravityParser.UserStatus?, [UsageWindow]), ProviderIssue> {
        guard installation.isInstalled else {
            return .failure(ProviderIssue(.notInstalled, "Antigravity não encontrado neste Mac."))
        }
        let servers = locator.runningServers()
        guard !servers.isEmpty else {
            endpoint = nil
            return .failure(ProviderIssue(.sourceUnavailable, "O Antigravity está fechado — abra-o para atualizar as cotas."))
        }
        guard let connection = await connect(to: servers) else {
            return .failure(ProviderIssue(.network, "Não foi possível falar com o Antigravity em execução."))
        }
        let (endpoint, statusData) = connection
        self.endpoint = endpoint

        let status = AntigravityParser.parseUserStatus(statusData)
        var windows: [UsageWindow]?
        if let summary = try? await call(endpoint, "RetrieveUserQuotaSummary") {
            windows = AntigravityParser.parseQuotaSummary(summary)
        }
        if windows == nil, let models = status?.models {
            windows = AntigravityParser.windows(fromModels: models)
        }
        guard let windows, !windows.isEmpty else {
            return .failure(ProviderIssue(.invalidResponse, "O Antigravity não informou cotas."))
        }
        return .success((status, windows))
    }

    /// Reuses the last working endpoint, otherwise probes each candidate port (HTTPS first).
    private func connect(to servers: [LanguageServerProcess]) async -> (Endpoint, Data)? {
        if let endpoint, servers.contains(where: { $0.pid == endpoint.pid && $0.csrfToken == endpoint.csrfToken }),
            let data = try? await call(endpoint, "GetUserStatus")
        {
            return (endpoint, data)
        }
        for server in servers {
            for port in locator.candidatePorts(for: server) {
                for scheme in ["https", "http"] {
                    let candidate = Endpoint(pid: server.pid, port: port, scheme: scheme, csrfToken: server.csrfToken)
                    if let data = try? await call(candidate, "GetUserStatus"), AntigravityParser.parseUserStatus(data) != nil {
                        return (candidate, data)
                    }
                }
            }
        }
        return nil
    }

    private func call(_ endpoint: Endpoint, _ method: String) async throws -> Data {
        guard let url = URL(string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)/\(Self.service)/\(method)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Self.requestBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(endpoint.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.timeoutInterval = 4
        let response = try await http.send(request)
        guard response.status == 200 else { throw URLError(.badServerResponse) }
        return response.body
    }
}
