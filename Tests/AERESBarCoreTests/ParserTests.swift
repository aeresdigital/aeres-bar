import Foundation
import Testing

@testable import AERESBarCore

@Suite("API de uso da Anthropic")
struct ClaudeParserTests {
    @Test("Lê o array `limits`, incluindo o semanal por modelo")
    func limitsArray() throws {
        let result = try #require(ClaudeUsageParser.parse(try Fixture.data("claude-usage.json")))
        #expect(result.windows.map(\.id) == ["session", "weekly_all", "weekly_scoped.Fable"])
        #expect(result.windows.map(\.title) == ["Sessão (5h)", "Semanal · todos os modelos", "Semanal · Fable"])
        #expect(result.windows.map(\.usedPercent) == [10, 73, 16])
        #expect(result.windows[0].isPrimary)
        #expect(result.windows[0].windowSeconds == ClaudeUsageParser.sessionSeconds)
        #expect(result.windows[1].isWeekly)
        // 03:09:59.97 is the jittered form of 03:10.
        #expect(result.windows[0].resetsAt == iso("2026-09-27T03:10:00Z"))
        #expect(result.windows[1].resetsAt == iso("2026-09-30T16:00:00Z"))
        #expect(
            result.details == [
                DetailRow(label: "Semana por produto", value: "Claude Code 96% · Cowork 3% · Outros 1%"),
                DetailRow(label: "Uso extra", value: "desativado"),
            ])
    }

    @Test("Formato antigo, sem `limits`")
    func legacy() throws {
        let result = try #require(ClaudeUsageParser.parse(try Fixture.data("claude-usage-legacy.json")))
        #expect(result.windows.map(\.id) == ["session", "weekly_all", "weekly_opus"])
        #expect(result.windows[0].usedPercent == 42.5)
        #expect(result.windows[2].notStarted)
        let extra = try #require(result.details.first { $0.label == "Uso extra" })
        #expect(extra.value.contains("12,50"))
        #expect(extra.value.contains("50,00"))
    }

    @Test("Respostas inválidas")
    func invalid() {
        #expect(ClaudeUsageParser.parse(Data("not json".utf8)) == nil)
        #expect(ClaudeUsageParser.parse(Data("{}".utf8)) == nil)
    }

    @Test(
        "Nome do plano",
        arguments: [
            ("max", "default_claude_max_5x", "Max 5x"), ("max", "default_claude_max_20x", "Max 20x"),
            ("max", nil, "Max"), ("pro", nil, "Pro"), ("team", nil, "Team"), ("enterprise", nil, "Enterprise"), ("edu", nil, "Edu"),
        ])
    func planNames(subscription: String, tier: String?, expected: String) {
        #expect(ClaudeUsageParser.planName(subscription: subscription, tier: tier) == expected)
    }

    @Test("Credencial do Claude Code")
    func credentials() throws {
        let json =
            #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1790479800787,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}"#
        let credentials = try #require(ClaudeCredentials.parse(Data(json.utf8)))
        #expect(credentials.accessToken == "tok")
        #expect(credentials.subscriptionType == "max")
        let expiry = try #require(credentials.expiresAt)
        #expect(abs(expiry.timeIntervalSince1970 - 1_790_479_800.787) < 0.001)
        #expect(!credentials.isExpired(at: expiry.addingTimeInterval(-60)))
        #expect(credentials.isExpired(at: expiry.addingTimeInterval(-10)))
        #expect(ClaudeCredentials.parse(Data(#"{"mcpOAuth":{}}"#.utf8)) == nil)
    }

    @Test("Fonte de credenciais: Chaves e arquivo reserva")
    func credentialSource() throws {
        let keychainJSON = #"{"claudeAiOauth":{"accessToken":"from-keychain"}}"#
        let keychain = ScriptedCommandRunner(outputs: ["/usr/bin/security": CommandOutput(status: 0, stdout: Data(keychainJSON.utf8))])
        #expect(
            KeychainClaudeCredentialSource(runner: keychain, fallbackFile: URL(fileURLWithPath: "/nonexistent")).load()?.accessToken
                == "from-keychain")

        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = try folder.write(#"{"claudeAiOauth":{"accessToken":"from-file"}}"#, to: ".credentials.json")
        let missing = ScriptedCommandRunner(outputs: ["/usr/bin/security": CommandOutput(status: 44, stdout: Data())])
        #expect(KeychainClaudeCredentialSource(runner: missing, fallbackFile: file).load()?.accessToken == "from-file")
        #expect(KeychainClaudeCredentialSource(runner: missing, fallbackFile: folder.url.appendingPathComponent("none")).load() == nil)
    }
}

@Suite("API de uso do ChatGPT (Codex)")
struct CodexParserTests {
    @Test("Janela semanal ainda não iniciada")
    func untouchedWeekly() throws {
        let result = try #require(CodexUsageParser.parse(try Fixture.data("codex-usage.json"), now: Date()))
        #expect(result.plan == "Pro Lite")
        #expect(result.email == "dev@example.com")
        #expect(result.windows.count == 1)
        let weekly = try #require(result.windows.first)
        #expect(weekly.title == "Semanal")
        #expect(weekly.notStarted)
        #expect(weekly.isPrimary)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_791_082_449))
        #expect(result.details.isEmpty)
    }

    @Test("Sessão, semanal, code review e créditos")
    func activeAccount() throws {
        let now = Date(timeIntervalSince1970: 1_789_990_000)
        let result = try #require(CodexUsageParser.parse(try Fixture.data("codex-usage-active.json"), now: now))
        #expect(result.windows.map(\.title) == ["Sessão (5h)", "Semanal", "Code review · semanal"])
        #expect(!result.windows[0].notStarted)
        #expect(result.windows[1].resetsAt == now.addingTimeInterval(90_000))
        #expect(result.details == [DetailRow(label: "Situação", value: "limite atingido"), DetailRow(label: "Créditos", value: "12.50")])
    }

    @Test("Limites registrados nos rollouts")
    func rolloutLimits() {
        let logged = Date(timeIntervalSince1970: 1_790_000_000)
        let limits: [String: Any] = [
            "primary": ["used_percent": 91.0, "window_minutes": 10_080, "resets_at": 1_790_468_673],
            "secondary": ["used_percent": 5.0, "window_minutes": 300, "resets_in_seconds": 600],
        ]
        let windows = CodexUsageParser.windows(fromLog: limits, loggedAt: logged)
        #expect(windows.map(\.title) == ["Semanal", "Sessão (5h)"])
        #expect(windows[0].usedPercent == 91)
        #expect(windows[1].resetsAt == logged.addingTimeInterval(600))
    }

    @Test(
        "Títulos das janelas",
        arguments: [
            (nil, "Limite de uso"), (18_000.0, "Sessão (5h)"), (86_400.0, "Diário"), (604_800.0, "Semanal"),
            (2_592_000.0, "Mensal"), (7_200.0, "Janela de 2h"), (259_200.0, "Janela de 3 dias"),
        ])
    func windowTitles(seconds: Double?, expected: String) {
        #expect(CodexUsageParser.windowTitle(seconds: seconds) == expected)
    }

    @Test("Nomes de plano", arguments: [("prolite", "Pro Lite"), ("plus", "Plus"), ("team", "Team"), ("some_new_plan", "Some New Plan")])
    func planNames(raw: String, expected: String) {
        #expect(CodexUsageParser.planName(raw) == expected)
    }

    @Test("Login do Codex e validade do JWT")
    func auth() throws {
        // Payload: {"exp": 2000000000}
        let token = "eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDB9.sig"
        #expect(JWT.expiry(token) == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(JWT.expiry("garbage") == nil)
        let json = #"{"auth_mode":"chatgpt","tokens":{"access_token":"\#(token)","account_id":"acct"}}"#
        let auth = try #require(CodexAuth.parse(Data(json.utf8)))
        #expect(auth.accountID == "acct")
        #expect(auth.expiresAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(CodexAuth.parse(Data(#"{"OPENAI_API_KEY":"sk-x"}"#.utf8)) == nil)
    }
}

@Suite("Language server do Antigravity")
struct AntigravityParserTests {
    @Test("Resumo de cotas por grupo")
    func quotaSummary() throws {
        let windows = try #require(AntigravityParser.parseQuotaSummary(try Fixture.data("antigravity-quota-summary.json")))
        #expect(windows.map(\.title) == ["Modelos Gemini · semanal", "Claude e GPT · semanal"])
        #expect(abs(windows[0].usedPercent - 65) < 0.001)
        #expect(windows[0].subtitle == "Gemini Flash, Gemini Pro")
        #expect(windows[0].isWeekly)
        #expect(windows[0].isPrimary)
        // Proto3 JSON drops zero values: a bucket without remainingFraction is empty.
        #expect(windows[1].usedPercent == 100)
        #expect(!windows[1].notStarted)
        #expect(AntigravityParser.parseQuotaSummary(Data(#"{"response":{"groups":[]}}"#.utf8)) == nil)
    }

    @Test("Status do usuário e agrupamento por modelo")
    func userStatus() throws {
        let status = try #require(AntigravityParser.parseUserStatus(try Fixture.data("antigravity-user-status.json")))
        #expect(status.plan == "Starter Quota")
        #expect(status.email == "dev@example.com")
        #expect(status.models.count == 5)
        #expect(status.models[3].remainingFraction == 0)
        #expect(status.models[4].remainingFraction == nil)

        let windows = AntigravityParser.windows(fromModels: status.models)
        #expect(windows.map(\.title) == ["Gemini 3.8 Flash (High) e +1", "Claude Opus 4.6 (Thinking)", "GPT-OSS 120B (Medium)"])
        #expect(windows[0].notStarted)
        #expect(abs(windows[1].usedPercent - 80) < 0.001)
        #expect(windows[2].usedPercent == 100)
        #expect(AntigravityParser.windows(fromModels: [status.models[0]]).first?.title == "Todos os modelos")
    }

    @Test("Descoberta do processo pelo `ps`")
    func processList() throws {
        let servers = LanguageServerLocator.parseProcessList(try Fixture.text("ps-output.txt"))
        #expect(
            servers == [
                LanguageServerProcess(pid: 1962, csrfToken: "11111111-2222-3333-4444-555555555555", declaredPorts: []),
                LanguageServerProcess(pid: 2044, csrfToken: "abcdef", declaredPorts: [53210]),
            ])
    }

    @Test("Portas em escuta pelo `lsof`")
    func listeningPorts() throws {
        #expect(LanguageServerLocator.parseListeningPorts(try Fixture.text("lsof-output.txt")) == [64999, 65000])
        let locator = LanguageServerLocator(
            runner: ScriptedCommandRunner(outputs: ["/usr/sbin/lsof": CommandOutput(status: 0, stdout: try Fixture.data("lsof-output.txt"))]
            )
        )
        let server = LanguageServerProcess(pid: 1962, csrfToken: "x", declaredPorts: [65000, 1234])
        #expect(locator.candidatePorts(for: server) == [65000, 1234, 64999])
    }

    @Test("Argumentos de linha de comando")
    func arguments() {
        let command = "/x/language_server --https_server_port 0 --csrf_token abc-123 --app_data_dir antigravity"
        #expect(LanguageServerLocator.argument("csrf_token", in: command) == "abc-123")
        #expect(LanguageServerLocator.argument("https_server_port", in: command) == "0")
        #expect(LanguageServerLocator.argument("server_port", in: command) == nil)
        #expect(LanguageServerLocator.argument("csrf_token", in: "x --csrf_token=zz --y") == "zz")
    }
}

@Suite("API do GitHub Copilot")
struct CopilotUsageParserTests {
    @Test("Plano Pro: requisições premium com excedente; chat e autocompletar ilimitados")
    func pro() throws {
        let result = try #require(CopilotUsageParser.parse(try Fixture.data("copilot-user-pro.json")))
        #expect(result.plan == "Pro")
        let premium = try #require(result.windows.first)
        #expect(result.windows.count == 1)
        #expect(premium.id == "copilot.premium_interactions")
        #expect(premium.title == "Requisições premium")
        #expect(premium.subtitle == "164 de 300 restantes no mês")
        #expect(abs(premium.usedPercent - 45.33) < 0.001)
        #expect(premium.isPrimary)
        #expect(premium.resetsAt == iso("2026-10-01T00:00:00Z"))
        #expect(premium.windowSeconds == Double(30 * 86_400))
        #expect(
            result.details == [
                DetailRow(label: "Requisições premium além da cota", value: "12"),
                DetailRow(label: "Chat", value: "ilimitado"),
                DetailRow(label: "Autocompletar", value: "ilimitado"),
            ])
    }

    @Test("Plano Free: chat e autocompletar com cota; premium sem direito fica de fora")
    func free() throws {
        let result = try #require(CopilotUsageParser.parse(try Fixture.data("copilot-user-free.json")))
        #expect(result.plan == "Free")
        #expect(result.windows.map(\.id) == ["copilot.chat", "copilot.completions"])
        #expect(result.windows.map(\.usedPercent) == [81.5, 27.5])
        #expect(result.windows.map(\.isPrimary) == [true, false])
        #expect(result.windows.last?.subtitle == "1.450 de 2.000 restantes no mês")
        #expect(result.details.isEmpty)
    }

    @Test("Sem percentual, calcula pelo restante; sem data UTC, usa a data do reset")
    func derivedValues() throws {
        let json = """
            {"access_type_sku": "copilot_pro", "quota_reset_date": "2026-11-01",
             "quota_snapshots": {"premium_interactions": {"entitlement": 300, "remaining": 75, "unlimited": false}}}
            """
        let window = try #require(CopilotUsageParser.parse(Data(json.utf8))?.windows.first)
        #expect(window.usedPercent == 75)
        #expect(window.resetsAt == iso("2026-11-01T00:00:00Z"))
    }

    @Test("Respostas inválidas", arguments: ["", "<html>", "{}", #"{"quota_snapshots": {}}"#])
    func invalid(body: String) {
        #expect(CopilotUsageParser.parse(Data(body.utf8)) == nil)
    }

    @Test(
        "Nomes de plano",
        arguments: [
            ("free_limited_copilot", nil, "Free"),
            ("free_educational_quota", nil, "Education"),
            ("monthly_subscriber_quota", nil, "Pro"),
            ("plus_yearly_subscriber_quota", nil, "Pro+"),
            ("copilot_enterprise_seat", nil, "Enterprise"),
            ("copilot_business_seat", nil, "Business"),
            (nil, "individual_pro", "Individual Pro"),
            (nil, " ", nil),
            (nil, nil, nil),
        ] as [(String?, String?, String?)]
    )
    func planNames(sku: String?, plan: String?, expected: String?) {
        #expect(CopilotUsageParser.planName(sku: sku, plan: plan) == expected)
    }
}

@Suite("Ollama Cloud e servidor local")
struct OllamaParserTests {
    @Test("Janelas de sessão e semanal, com o total de requisições")
    func cloudUsage() throws {
        let windows = try #require(OllamaParser.parseCloudUsage(try Fixture.data("ollama-usage.json")))
        #expect(windows.map(\.id) == ["ollama.session", "ollama.weekly"])
        #expect(windows.map(\.usedPercent) == [22.5, 58])
        #expect(windows.map(\.subtitle) == ["48 requisições", "1.510 requisições"])
        #expect(windows.map(\.windowSeconds) == [18_000, 604_800])
        #expect(windows.map(\.isPrimary) == [true, false])
        // The endpoint does not say when the windows renew.
        #expect(windows.allSatisfy { $0.resetsAt == nil })
    }

    @Test("Aceita percentual em vez de fração e limita a 100%")
    func percentages() throws {
        let json = #"{"limits": {"weekly": {"usage": 140, "models": {"m": {"request_count": 1}}}}}"#
        let window = try #require(OllamaParser.parseCloudUsage(Data(json.utf8))?.first)
        #expect(window.usedPercent == 100)
        #expect(window.subtitle == "1 requisição")
        #expect(window.isPrimary)
    }

    @Test("Respostas inválidas", arguments: ["", "{}", #"{"limits": {}}"#, #"{"limits": {"monthly": {"usage": 0.1}}}"#])
    func invalid(body: String) {
        #expect(OllamaParser.parseCloudUsage(Data(body.utf8)) == nil)
    }

    @Test("Versão e modelos carregados no servidor local")
    func localServer() throws {
        #expect(OllamaParser.parseVersion(Data(#"{"version": "0.13.2"}"#.utf8)) == "0.13.2")
        #expect(OllamaParser.parseVersion(Data("{}".utf8)) == nil)
        let models = try #require(OllamaParser.parseLoadedModels(try Fixture.data("ollama-ps.json")))
        #expect(
            models == [
                OllamaParser.LoadedModel(name: "qwen3-coder:30b", sizeBytes: 19_975_561_216, vramBytes: 19_975_561_216),
                OllamaParser.LoadedModel(name: "nomic-embed-text:latest", sizeBytes: 849_813_504, vramBytes: 0),
            ])
        #expect(OllamaParser.parseLoadedModels(Data(#"{"models": []}"#.utf8)) == [])
        #expect(OllamaParser.parseLoadedModels(Data("<html>".utf8)) == nil)
    }
}

@Suite("API do OpenRouter")
struct OpenRouterParserTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 14:13 UTC, a Monday

    /// Currency amounts keep "US$" and the number together with a no-break space.
    private func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test("Chave com limite mensal e cota diária de modelos gratuitos")
    func keyWithLimit() throws {
        let key = try #require(OpenRouterParser.parseKey(try Fixture.data("openrouter-key.json")))
        #expect(key.limit == 100)
        #expect(key.limitReset == "monthly")
        #expect(!key.isFreeTier)

        let windows = OpenRouterParser.windows(for: key, now: now)
        #expect(windows.map(\.id) == ["openrouter.limit", "openrouter.free"])
        let limit = try #require(windows.first)
        #expect(limit.title == "Limite da chave · mensal")
        #expect(limit.usedPercent == 25.5)
        #expect(plain(limit.subtitle) == "US$ 25,50 de US$ 100,00")
        #expect(limit.resetsAt == iso("2026-10-01T00:00:00Z"))
        #expect(limit.isPrimary)
        let free = try #require(windows.last)
        #expect(free.subtitle == "12 de 1.000 requisições")
        #expect(abs(free.usedPercent - 1.2) < 0.0001)
        #expect(free.resetsAt == iso("2026-09-22T00:00:00Z"))
        #expect(!free.isPrimary)

        let credits = try #require(OpenRouterParser.parseCredits(try Fixture.data("openrouter-credits.json")))
        #expect(credits.balance == 74.75)
        #expect(
            OpenRouterParser.details(for: key, credits: credits).map { "\($0.label): \(plain($0.value) ?? "")" } == [
                "Gasto: hoje US$ 1,20 · semana US$ 5,30 · mês US$ 25,50",
                "Saldo: US$ 74,75 de US$ 100,50",
            ])
    }

    @Test("Chave sem limite, no plano gratuito")
    func freeKey() throws {
        let key = try #require(OpenRouterParser.parseKey(try Fixture.data("openrouter-key-free.json")))
        #expect(key.limit == nil)
        #expect(key.isFreeTier)
        let windows = OpenRouterParser.windows(for: key, now: now)
        #expect(windows.map(\.id) == ["openrouter.free"])
        #expect(windows.first?.usedPercent == 90)
        #expect(windows.first?.isPrimary == true)
        #expect(OpenRouterParser.details(for: key, credits: nil).last == DetailRow(label: "Limite da chave", value: "sem limite"))
    }

    @Test("Sem limit_remaining, o gasto vem do período do limite")
    func spendFromPeriod() throws {
        let json = #"{"data": {"limit": 10, "limit_reset": "weekly", "usage": 50, "usage_weekly": 4}}"#
        let key = try #require(OpenRouterParser.parseKey(Data(json.utf8)))
        let window = try #require(OpenRouterParser.windows(for: key, now: now).first)
        #expect(window.usedPercent == 40)
        #expect(window.title == "Limite da chave · semanal")
        // Weeks run Monday to Sunday: the next Monday at midnight UTC.
        #expect(window.resetsAt == iso("2026-09-28T00:00:00Z"))

        let lifetime = try #require(OpenRouterParser.parseKey(Data(#"{"data": {"limit": 20, "usage": 5}}"#.utf8)))
        let capped = try #require(OpenRouterParser.windows(for: lifetime, now: now).first)
        #expect(capped.title == "Limite da chave")
        #expect(capped.usedPercent == 25)
        #expect(capped.resetsAt == nil)
    }

    @Test("Respostas inválidas")
    func invalid() {
        #expect(OpenRouterParser.parseKey(Data("{}".utf8)) == nil)
        #expect(OpenRouterParser.parseKey(Data("<html>".utf8)) == nil)
        #expect(OpenRouterParser.parseCredits(Data(#"{"data": {}}"#.utf8)) == nil)
    }
}
