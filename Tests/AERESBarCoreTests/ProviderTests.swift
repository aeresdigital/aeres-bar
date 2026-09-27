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
            http: http, credentialSource: StubCredentialSource(credentials()), logRoots: noLogs, now: clock.provider)
        _ = await provider.snapshot(previous: nil)
        clock.advance(by: 30)
        let second = await provider.snapshot(previous: nil)
        #expect(http.requests.count == 1)
        #expect(second.status == .ok)
        clock.advance(by: 31)
        _ = await provider.snapshot(previous: second)
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
}
