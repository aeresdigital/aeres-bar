import Foundation
import Testing

@testable import AERESBarCore

@Suite("Provedor Claude Code")
struct ClaudeProviderTests {
    let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
    let noLogs = [URL(fileURLWithPath: "/nonexistent/projects")]

    private func credentials(expiringIn seconds: TimeInterval = 3_600) -> ClaudeCredentials {
        ClaudeCredentials(
            accessToken: "tok", expiresAt: clock.now.addingTimeInterval(seconds), subscriptionType: "max",
            rateLimitTier: "default_claude_max_5x")
    }

    @Test("Lê os limites e envia os cabeçalhos certos")
    func success() async throws {
        let http = MockHTTPClient(status: 200, body: try Fixture.data("claude-usage.json"))
        let provider = ClaudeProvider(
            http: http, credentialSource: StubCredentialSource(credentials()), logRoots: noLogs, now: clock.provider)

        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.issue == nil)
        #expect(snapshot.plan == "Max 5x")
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.limitsUpdatedAt == clock.now)
        #expect(snapshot.tokens != nil)

        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test("Reaproveita a resposta recente em vez de consultar de novo")
    func reusesRecentResponse() async throws {
        let http = MockHTTPClient(status: 200, body: try Fixture.data("claude-usage.json"))
        let provider = ClaudeProvider(
            http: http,
            credentialSource: StubCredentialSource(credentials()),
            logRoots: noLogs,
            policy: FetchPolicy(minimumInterval: 60),
            now: clock.provider
        )
        _ = await provider.snapshot(previous: nil)
        clock.advance(by: 30)
        let second = await provider.snapshot(previous: nil)
        #expect(http.requests.count == 1)
        #expect(second.status == .ok)
        #expect(second.limitsUpdatedAt == clock.now.addingTimeInterval(-30))
        clock.advance(by: 31)
        _ = await provider.snapshot(previous: second)
        #expect(http.requests.count == 2)
    }

    @Test("Por padrão, consulta a Anthropic no máximo a cada 3 minutos")
    func defaultPolicyIsConservative() async throws {
        #expect(ClaudeProvider.defaultPolicy.minimumInterval == 180)
        let http = MockHTTPClient(status: 200, body: try Fixture.data("claude-usage.json"))
        let provider = ClaudeProvider(
            http: http, credentialSource: StubCredentialSource(credentials()), logRoots: noLogs, now: clock.provider)
        _ = await provider.snapshot(previous: nil)
        clock.advance(by: 170)
        _ = await provider.snapshot(previous: nil)
        #expect(http.requests.count == 1)
        clock.advance(by: 11)
        _ = await provider.snapshot(previous: nil)
        #expect(http.requests.count == 2)
    }

    @Test("O botão Atualizar consulta a Anthropic mesmo dentro dos 3 minutos, mas não a cada clique")
    func manualRefresh() async throws {
        let http = MockHTTPClient(status: 200, body: try Fixture.data("claude-usage.json"))
        let provider = ClaudeProvider(
            http: http, credentialSource: StubCredentialSource(credentials()), logRoots: noLogs, now: clock.provider)
        _ = await provider.snapshot(previous: nil)
        clock.advance(by: 10)
        _ = await provider.snapshot(previous: nil, reason: .manual)
        #expect(http.requests.count == 1)  // younger than 15 s: reused even on a click
        clock.advance(by: 10)
        _ = await provider.snapshot(previous: nil)
        #expect(http.requests.count == 1)
        _ = await provider.snapshot(previous: nil, reason: .manual)
        #expect(http.requests.count == 2)
    }

    @Test("Credencial expirada: não chama a rede e mantém os últimos limites")
    func expiredCredentials() async throws {
        let http = MockHTTPClient(status: 200, body: try Fixture.data("claude-usage.json"))
        let source = StubCredentialSource(credentials(expiringIn: -60))
        let provider = ClaudeProvider(http: http, credentialSource: source, logRoots: noLogs, now: clock.provider)
        let previous = ProviderSnapshot(
            provider: .claude,
            status: .ok,
            windows: [UsageWindow(id: "session", title: "Sessão (5h)", usedPercent: 40)],
            limitsUpdatedAt: clock.now.addingTimeInterval(-600)
        )

        let snapshot = await provider.snapshot(previous: previous)
        #expect(http.requests.isEmpty)
        #expect(snapshot.status == .stale)
        #expect(snapshot.issue == .credentialsExpired)
        #expect(snapshot.windows.first?.usedPercent == 40)
    }

    @Test("401 descarta a credencial e relê o Chaves na próxima vez")
    func unauthorized() async throws {
        let http = MockHTTPClient(status: 401)
        let source = StubCredentialSource(credentials())
        let provider = ClaudeProvider(http: http, credentialSource: source, logRoots: noLogs, now: clock.provider)

        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.issue == .unauthorized)
        #expect(snapshot.status == .error)
        #expect(source.loads == 1)

        http.respond { _ in HTTPResponse(status: 200, body: (try? Fixture.data("claude-usage.json")) ?? Data()) }
        let recovered = await provider.snapshot(previous: snapshot)
        #expect(source.loads == 2)
        #expect(recovered.status == .ok)
    }

    @Test("429 respeita o Retry-After")
    func rateLimited() async throws {
        let http = MockHTTPClient(status: 429, headers: ["Retry-After": "120"])
        let provider = ClaudeProvider(
            http: http, credentialSource: StubCredentialSource(credentials()), logRoots: noLogs, now: clock.provider)

        let first = await provider.snapshot(previous: nil)
        #expect(first.issue == .rateLimited)
        #expect(first.message?.contains("2min") == true)

        clock.advance(by: 60)
        _ = await provider.snapshot(previous: first)
        #expect(http.requests.count == 1)

        clock.advance(by: 61)
        http.respond { _ in HTTPResponse(status: 200, body: (try? Fixture.data("claude-usage.json")) ?? Data()) }
        let recovered = await provider.snapshot(previous: first)
        #expect(http.requests.count == 2)
        #expect(recovered.status == .ok)
    }

    @Test("Falhas de rede e respostas inválidas", arguments: [500, 200])
    func failures(status: Int) async throws {
        let http = MockHTTPClient { _ in
            if status == 500 { throw TestError.offline }
            return HTTPResponse(status: 200, body: Data("<html>".utf8))
        }
        let provider = ClaudeProvider(
            http: http, credentialSource: StubCredentialSource(credentials()), logRoots: noLogs, now: clock.provider)
        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.issue == (status == 500 ? .network : .invalidResponse))
        #expect(snapshot.status == .error)
    }

    @Test("Sem login e sem logs: Claude Code não instalado")
    func notInstalled() async {
        let provider = ClaudeProvider(
            http: MockHTTPClient(status: 200), credentialSource: StubCredentialSource(nil), logRoots: noLogs, now: clock.provider)
        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.status == .notInstalled)
        #expect(snapshot.issue == .notInstalled)
    }

    @Test("Sem login mas com logs: mostra tokens e pede login")
    func notSignedInWithLogs() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try folder.write("{}\n", to: "projects/p/s.jsonl")
        let provider = ClaudeProvider(
            http: MockHTTPClient(status: 200),
            credentialSource: StubCredentialSource(nil),
            logRoots: [folder.url.appendingPathComponent("projects")],
            now: clock.provider
        )
        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.issue == .notSignedIn)
        #expect(snapshot.status == .error)
    }
}

@Suite("Provedor Codex")
struct CodexProviderTests {
    let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))

    private func home(withAuth: Bool) throws -> TemporaryDirectory {
        let folder = try TemporaryDirectory()
        if withAuth {
            // Token expiring in 2033: {"exp": 2000000000}
            try folder.write(
                #"{"tokens":{"access_token":"eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDB9.sig","account_id":"acct"}}"#,
                to: "auth.json"
            )
        }
        return folder
    }

    @Test("Lê os limites pela API")
    func success() async throws {
        let folder = try home(withAuth: true)
        defer { folder.remove() }
        let http = MockHTTPClient(status: 200, body: try Fixture.data("codex-usage.json"))
        let provider = CodexProvider(home: folder.url, http: http, now: clock.provider)

        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.plan == "Pro Lite")
        #expect(snapshot.windows.first?.notStarted == true)
        let request = try #require(http.requests.first)
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct")
    }

    @Test("Sem API, usa o último limite registrado nos rollouts")
    func fallsBackToLogs() async throws {
        let folder = try home(withAuth: true)
        defer { folder.remove() }
        let logged = clock.now.addingTimeInterval(-300).formatted(.iso8601)
        try folder.write(
            #"{"timestamp":"\#(logged)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":55.0,"window_minutes":10080,"resets_at":1790400000},"plan_type":"prolite"}}}"#
                + "\n",
            to: "sessions/2026/09/22/rollout-x.jsonl"
        )
        let provider = CodexProvider(home: folder.url, http: MockHTTPClient { _ in throw TestError.offline }, now: clock.provider)

        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.issue == .network)
        #expect(snapshot.status == .stale)
        #expect(snapshot.windows.first?.usedPercent == 55)
        #expect(snapshot.plan == "Pro Lite")
        #expect(snapshot.source == "Logs locais do Codex")
    }

    @Test("Sem login")
    func notSignedIn() async throws {
        let folder = try home(withAuth: false)
        defer { folder.remove() }
        let http = MockHTTPClient(status: 200)
        let snapshot = await CodexProvider(home: folder.url, http: http, now: clock.provider).snapshot(previous: nil)
        #expect(snapshot.issue == .notSignedIn)
        #expect(http.requests.isEmpty)
    }

    @Test("Codex não instalado")
    func notInstalled() async {
        let provider = CodexProvider(
            home: URL(fileURLWithPath: "/nonexistent/.codex"), http: MockHTTPClient(status: 200), now: clock.provider)
        #expect(await provider.snapshot(previous: nil).status == .notInstalled)
    }

    @Test("401 e 429", arguments: [401, 429])
    func httpErrors(status: Int) async throws {
        let folder = try home(withAuth: true)
        defer { folder.remove() }
        let snapshot = await CodexProvider(home: folder.url, http: MockHTTPClient(status: status), now: clock.provider).snapshot(
            previous: nil)
        #expect(snapshot.issue == (status == 401 ? .unauthorized : .rateLimited))
    }
}

@Suite("Provedor Antigravity")
struct AntigravityProviderTests {
    let installed = AntigravityInstallation(
        applicationCandidates: [URL(fileURLWithPath: "/")], dataDirectory: URL(fileURLWithPath: "/nonexistent"))

    private func locator(ps: String) throws -> LanguageServerLocator {
        LanguageServerLocator(
            runner: ScriptedCommandRunner(outputs: [
                "/bin/ps": CommandOutput(status: 0, stdout: Data(ps.utf8)),
                "/usr/sbin/lsof": CommandOutput(status: 0, stdout: try Fixture.data("lsof-output.txt")),
            ])
        )
    }

    @Test("Descobre a porta, autentica com o CSRF e lê o resumo de cotas")
    func success() async throws {
        let status = try Fixture.data("antigravity-user-status.json")
        let summary = try Fixture.data("antigravity-quota-summary.json")
        let http = MockHTTPClient { request in
            // Only the HTTPS listener on 65000 answers, like the real agent app.
            guard request.url?.port == 65000, request.url?.scheme == "https" else { throw TestError.offline }
            #expect(request.value(forHTTPHeaderField: "X-Codeium-Csrf-Token") == "11111111-2222-3333-4444-555555555555")
            let method = request.url?.lastPathComponent
            return HTTPResponse(status: 200, body: method == "GetUserStatus" ? status : summary)
        }
        let ps = try Fixture.text("ps-output.txt").components(separatedBy: "\n").filter { !$0.contains("2044") }.joined(separator: "\n")
        let provider = AntigravityProvider(http: http, locator: try locator(ps: ps), installation: installed)

        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.plan == "Starter Quota")
        #expect(snapshot.windows.map(\.id) == ["ag.gemini-weekly", "ag.3p-weekly"])
        #expect(snapshot.models.count == 5)

        // The endpoint is remembered: the next refresh goes straight to it.
        let before = http.requests.count
        _ = await provider.snapshot(previous: snapshot)
        #expect(http.requests.count == before + 2)
    }

    @Test("Sem o resumo, agrupa as cotas por modelo")
    func fallsBackToModels() async throws {
        let status = try Fixture.data("antigravity-user-status.json")
        let http = MockHTTPClient { request in
            request.url?.lastPathComponent == "GetUserStatus"
                ? HTTPResponse(status: 200, body: status) : HTTPResponse(status: 404, body: Data())
        }
        let provider = AntigravityProvider(http: http, locator: try locator(ps: try Fixture.text("ps-output.txt")), installation: installed)
        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.windows.count == 3)
    }

    @Test("Antigravity fechado mantém a última leitura")
    func closed() async throws {
        let provider = AntigravityProvider(
            http: MockHTTPClient(status: 200), locator: try locator(ps: "  1 /sbin/launchd\n"), installation: installed)
        let previous = ProviderSnapshot(
            provider: .antigravity, status: .ok, windows: [UsageWindow(id: "w", title: "x", usedPercent: 10)], limitsUpdatedAt: Date())
        let snapshot = await provider.snapshot(previous: previous)
        #expect(snapshot.issue == .sourceUnavailable)
        #expect(snapshot.status == .stale)
        #expect(snapshot.windows.count == 1)
    }

    @Test("Servidor que não responde")
    func unreachable() async throws {
        let provider = AntigravityProvider(
            http: MockHTTPClient { _ in throw TestError.offline },
            locator: try locator(ps: try Fixture.text("ps-output.txt")),
            installation: installed
        )
        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.issue == .network)
        #expect(snapshot.status == .error)
    }

    @Test("Não instalado")
    func notInstalled() async {
        let missing = AntigravityInstallation(applicationCandidates: [], dataDirectory: URL(fileURLWithPath: "/nonexistent"))
        #expect(!missing.isInstalled)
        #expect(missing.applicationURL == nil)
        let snapshot = await AntigravityProvider(http: MockHTTPClient(status: 200), installation: missing).snapshot(previous: nil)
        #expect(snapshot.status == .notInstalled)
    }
}

@Suite("Política de consultas")
struct FetchPolicyTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Retry-After em segundos, em data HTTP ou ausente")
    func retryAfter() throws {
        #expect(HTTPResponse(status: 429, body: Data(), headers: ["Retry-After": "90"]).retryAfter(now: now) == now.addingTimeInterval(90))
        let date = try #require(
            HTTPResponse(status: 429, body: Data(), headers: ["retry-after": "Sun, 27 Sep 2026 04:47:13 GMT"]).retryAfter(now: now))
        #expect(date == iso("2026-09-27T04:47:13Z"))
        #expect(HTTPResponse(status: 429, body: Data()).retryAfter(now: now) == nil)
    }

    @Test("A pausa é limitada entre 30 s e o máximo")
    func backoffBounds() {
        let policy = FetchPolicy(minimumInterval: 60, defaultBackoff: 300, maximumBackoff: 1_800)
        #expect(policy.backoffDeadline(from: HTTPResponse(status: 429, body: Data()), now: now) == now.addingTimeInterval(300))
        #expect(
            policy.backoffDeadline(from: HTTPResponse(status: 429, body: Data(), headers: ["Retry-After": "5"]), now: now)
                == now.addingTimeInterval(30))
        #expect(
            policy.backoffDeadline(from: HTTPResponse(status: 429, body: Data(), headers: ["Retry-After": "99999"]), now: now)
                == now.addingTimeInterval(1_800))
    }

    @Test("Leitura manual só reaproveita respostas de menos de 15 s")
    func manualReuse() {
        let policy = FetchPolicy(minimumInterval: 60, manualMinimumInterval: 15)
        let fetched = now.addingTimeInterval(-20)
        #expect(policy.canReuse(fetchedAt: fetched, now: now, reason: .automatic))
        #expect(!policy.canReuse(fetchedAt: fetched, now: now, reason: .manual))
        #expect(policy.canReuse(fetchedAt: now.addingTimeInterval(-10), now: now, reason: .manual))
    }
}

@Suite("Provedor GitHub Copilot")
struct CopilotProviderTests {
    let clock = TestClock()

    private func provider(_ http: MockHTTPClient, token: String? = "gho_test") -> CopilotProvider {
        CopilotProvider(http: http, tokenSource: StubGitHubTokenSource(value: token), now: clock.provider)
    }

    @Test("Lê as cotas com o login do GitHub")
    func success() async throws {
        let http = MockHTTPClient(status: 200, body: try Fixture.data("copilot-user-free.json"))
        let snapshot = await provider(http).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.plan == "Free")
        #expect(snapshot.windows.map(\.id) == ["copilot.chat", "copilot.completions"])
        #expect(snapshot.source == "API do GitHub")
        #expect(snapshot.limitsUpdatedAt == clock.now)
        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/copilot_internal/user")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "token gho_test")
    }

    @Test("Sem login do GitHub: fica como não configurado, sem chamar a rede")
    func noToken() async {
        let http = MockHTTPClient(status: 200)
        let snapshot = await provider(http, token: nil).snapshot(previous: nil)
        #expect(snapshot.status == .notInstalled)
        #expect(http.requests.isEmpty)
    }

    @Test(
        "Respostas de erro do GitHub",
        arguments: [
            (401, [:], ProviderIssue.Kind.unauthorized),
            (403, ["X-RateLimit-Remaining": "0"], .rateLimited),
            (429, [:], .rateLimited),
            (403, [:], .notSignedIn),
            (404, [:], .notSignedIn),
            (502, [:], .invalidResponse),
        ] as [(Int, [String: String], ProviderIssue.Kind)]
    )
    func errors(status: Int, headers: [String: String], expected: ProviderIssue.Kind) async {
        let snapshot = await provider(MockHTTPClient(status: status, headers: headers)).snapshot(previous: nil)
        #expect(snapshot.issue == expected)
        #expect(snapshot.status == .error)
    }

    @Test("Falha de rede e resposta ilegível")
    func failures() async {
        #expect(await provider(MockHTTPClient { _ in throw TestError.offline }).snapshot(previous: nil).issue == .network)
        #expect(await provider(MockHTTPClient(status: 200, body: Data("<html>".utf8))).snapshot(previous: nil).issue == .invalidResponse)
    }

    @Test("Pausa pedida pelo GitHub vale até para o botão Atualizar")
    func backoff() async throws {
        let http = MockHTTPClient(status: 429, headers: ["Retry-After": "120"])
        let copilot = provider(http)
        _ = await copilot.snapshot(previous: nil)
        clock.advance(by: 60)
        #expect(await copilot.snapshot(previous: nil, reason: .manual).issue == .rateLimited)
        #expect(http.requests.count == 1)

        clock.advance(by: 61)
        http.respond { _ in HTTPResponse(status: 200, body: (try? Fixture.data("copilot-user-pro.json")) ?? Data()) }
        #expect(await copilot.snapshot(previous: nil).status == .ok)
        #expect(http.requests.count == 2)
    }

    @Test("Leituras automáticas reaproveitam a resposta por um minuto")
    func reuse() async throws {
        let http = MockHTTPClient(status: 200, body: try Fixture.data("copilot-user-pro.json"))
        let copilot = provider(http)
        _ = await copilot.snapshot(previous: nil)
        clock.advance(by: 59)
        _ = await copilot.snapshot(previous: nil)
        #expect(http.requests.count == 1)
        clock.advance(by: 2)
        _ = await copilot.snapshot(previous: nil)
        #expect(http.requests.count == 2)
    }
}

@Suite("Provedor Ollama")
struct OllamaProviderTests {
    let clock = TestClock()
    static let server = URL(string: "http://127.0.0.1:11434") ?? URL(fileURLWithPath: "/")

    /// The local server's `/api/version` and `/api/ps`, or a refused connection.
    private func localServer(running: Bool) -> MockHTTPClient {
        MockHTTPClient { request in
            guard running else { throw TestError.offline }
            switch request.url?.path {
            case "/api/version": return HTTPResponse(status: 200, body: Data(#"{"version": "0.13.2"}"#.utf8))
            case "/api/ps": return HTTPResponse(status: 200, body: (try? Fixture.data("ollama-ps.json")) ?? Data())
            default: return HTTPResponse(status: 404, body: Data())
            }
        }
    }

    private func provider(
        cloud: MockHTTPClient = MockHTTPClient(status: 500),
        running: Bool,
        secrets: MemorySecretStore = MemorySecretStore(),
        installed: Bool = true
    ) -> OllamaProvider {
        OllamaProvider(
            cloudHTTP: cloud,
            localHTTP: localServer(running: running),
            secrets: secrets,
            server: Self.server,
            installations: installed ? [URL(fileURLWithPath: "/")] : [],
            now: clock.provider
        )
    }

    @Test("Com a chave: limites do Ollama Cloud e status do servidor local")
    func cloudAndLocal() async throws {
        let cloud = MockHTTPClient(status: 200, body: try Fixture.data("ollama-usage.json"))
        let snapshot = await provider(cloud: cloud, running: true, secrets: MemorySecretStore([.ollama: "ollama-test-key"]))
            .snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.windows.map(\.id) == ["ollama.session", "ollama.weekly"])
        #expect(snapshot.source == "Ollama Cloud + servidor local")
        #expect(snapshot.details.first == DetailRow(label: "Servidor local", value: "v0.13.2 · em execução"))
        #expect(snapshot.details.last?.value.contains("qwen3-coder:30b") == true)
        let request = try #require(cloud.requests.first)
        #expect(request.url?.absoluteString == "https://ollama.com/api/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ollama-test-key")
    }

    @Test("Sem a chave, com o servidor local: sem limites e com a dica de onde pôr a chave")
    func localOnly() async {
        let cloud = MockHTTPClient(status: 200)
        let snapshot = await provider(cloud: cloud, running: true).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.message?.contains("Chaves de API") == true)
        #expect(snapshot.source == "Servidor local do Ollama")
        #expect(cloud.requests.isEmpty)
    }

    @Test("Sem a chave e com o servidor parado")
    func serverStopped() async {
        let snapshot = await provider(running: false).snapshot(previous: nil)
        #expect(snapshot.issue == .sourceUnavailable)
        #expect(snapshot.status == .error)
    }

    @Test("Nem instalado nem com chave")
    func notInstalled() async {
        #expect(await provider(running: false, installed: false).snapshot(previous: nil).status == .notInstalled)
    }

    @Test("Só a chave, sem o app instalado: lê o Ollama Cloud")
    func cloudOnly() async throws {
        let cloud = MockHTTPClient(status: 200, body: try Fixture.data("ollama-usage.json"))
        let snapshot = await provider(
            cloud: cloud, running: false, secrets: MemorySecretStore([.ollama: "ollama-test-key"]), installed: false
        )
        .snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.source == "Ollama Cloud")
        #expect(snapshot.details.isEmpty)
    }

    @Test(
        "Erros do Ollama Cloud",
        arguments: [
            (401, ProviderIssue.Kind.unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .invalidResponse), (0, .network),
        ]
    )
    func errors(status: Int, expected: ProviderIssue.Kind) async {
        let cloud = MockHTTPClient { _ in
            guard status > 0 else { throw TestError.offline }
            return HTTPResponse(status: status, body: Data())
        }
        let snapshot = await provider(cloud: cloud, running: false, secrets: MemorySecretStore([.ollama: "ollama-test-key"]))
            .snapshot(previous: nil)
        #expect(snapshot.issue == expected)
    }

    @Test("Trocar a chave descarta o que a chave anterior leu")
    func keyChange() async throws {
        let secrets = MemorySecretStore([.ollama: "first-key-123"])
        let cloud = MockHTTPClient(status: 200, body: try Fixture.data("ollama-usage.json"))
        let ollama = provider(cloud: cloud, running: false, secrets: secrets)
        let first = await ollama.snapshot(previous: nil)
        #expect(first.status == .ok)

        try secrets.setSecret("second-key-456", for: .ollama)
        cloud.respond { _ in HTTPResponse(status: 401, body: Data()) }
        let second = await ollama.snapshot(previous: first)
        #expect(cloud.requests.count == 2)  // not served from the first key's cache
        #expect(cloud.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer second-key-456")
        #expect(second.issue == .unauthorized)
        #expect(second.windows.isEmpty)  // nor showing the first key's limits
    }
}

@Suite("Provedor OpenRouter")
struct OpenRouterProviderTests {
    let clock = TestClock()

    private func provider(
        _ http: MockHTTPClient, secrets: MemorySecretStore = MemorySecretStore([.openRouter: "sk-or-v1-test"])
    )
        -> KeyedUsageProvider
    {
        KeyedUsageProvider(service: .openRouter, http: http, secrets: secrets, now: clock.provider)
    }

    @Test("Lê a chave e o saldo, com os cabeçalhos certos")
    func success() async throws {
        let key = try Fixture.data("openrouter-key.json")
        let credits = try Fixture.data("openrouter-credits.json")
        let http = MockHTTPClient { request in
            HTTPResponse(status: 200, body: request.url?.lastPathComponent == "credits" ? credits : key)
        }
        let snapshot = await provider(http).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.plan == nil)
        #expect(snapshot.windows.map(\.id) == ["openrouter.limit", "openrouter.free"])
        #expect(snapshot.details.map(\.label) == ["Gasto", "Saldo"])
        #expect(
            http.requests.map { $0.url?.absoluteString } == ["https://openrouter.ai/api/v1/key", "https://openrouter.ai/api/v1/credits"])
        let request = try #require(http.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-test")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "AERES Bar")
    }

    @Test("Chave comum: o saldo exige chave de gerenciamento e fica de fora")
    func creditsForbidden() async throws {
        let key = try Fixture.data("openrouter-key-free.json")
        let http = MockHTTPClient { request in
            request.url?.lastPathComponent == "credits" ? HTTPResponse(status: 403, body: Data()) : HTTPResponse(status: 200, body: key)
        }
        let snapshot = await provider(http).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.plan == "Gratuito")
        #expect(!snapshot.details.contains { $0.label == "Saldo" })
    }

    @Test("Sem chave não consulta nada; remover a chave apaga a leitura anterior")
    func keyRemoved() async throws {
        let secrets = MemorySecretStore([.openRouter: "sk-or-v1-test"])
        let http = MockHTTPClient(status: 200, body: try Fixture.data("openrouter-key.json"))
        let openRouter = provider(http, secrets: secrets)
        let first = await openRouter.snapshot(previous: nil)
        #expect(!first.windows.isEmpty)

        try secrets.deleteSecret(for: .openRouter)
        let second = await openRouter.snapshot(previous: first)
        #expect(second.status == .notInstalled)
        #expect(second.windows.isEmpty)
        #expect(http.requests.count == 2)  // key and credits, for the first read only
    }

    @Test(
        "Erros do OpenRouter",
        arguments: [
            (401, ProviderIssue.Kind.unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .invalidResponse), (0, .network),
        ]
    )
    func errors(status: Int, expected: ProviderIssue.Kind) async {
        let http = MockHTTPClient { _ in
            guard status > 0 else { throw TestError.offline }
            return HTTPResponse(status: status, body: Data("{}".utf8))
        }
        #expect(await provider(http).snapshot(previous: nil).issue == expected)
    }

    @Test("Resposta ilegível")
    func invalidResponse() async {
        #expect(await provider(MockHTTPClient(status: 200, body: Data("<html>".utf8))).snapshot(previous: nil).issue == .invalidResponse)
    }
}
