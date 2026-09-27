import Foundation
import Testing

@testable import AERESBarCore

/// Currency amounts keep the symbol and the number together with a no-break space.
private func plain(_ text: String?) -> String? {
    text?.replacingOccurrences(of: "\u{00A0}", with: " ")
}

@Suite("Kimi Code e plataforma Kimi")
struct KimiParserTests {
    @Test("Plano antigo (internacional): contagens valem mais que a razão zerada")
    func legacyPlan() throws {
        let windows = try #require(KimiCodeParser.windows(from: try Fixture.data("kimi-code-usages-global.json")))
        #expect(windows.map(\.id) == ["kimi.session", "kimi.weekly"])
        #expect(windows.map(\.usedPercent) == [0, 100])  // the weekly ratio says 0, its counts say used up
        #expect(windows.map(\.isPrimary) == [true, false])
        #expect(windows.last?.resetsAt == iso("2026-09-24T02:09:07.465054Z"))
        #expect(windows.map(\.windowSeconds) == [18_000, 604_800])
    }

    @Test("China continental: sessão, mês e a parte do Kimi Code no mês")
    func mainland() throws {
        let data = try Fixture.data("kimi-code-usages-china.json")
        let windows = try #require(KimiCodeParser.windows(from: data))
        #expect(windows.map(\.id) == ["kimi.session", "kimi.monthly"])
        #expect(windows.first?.usedPercent == 100)
        #expect(abs((windows.last?.usedPercent ?? 0) - 7.95) < 1e-9)
        #expect(windows.last?.resetsAt == iso("2026-10-22T00:00:00Z"))
        #expect(KimiCodeParser.details(from: data) == [DetailRow(label: "Kimi Code na cota mensal", value: "0%")])
    }

    @Test("Janelas descritas em outras unidades, e respostas sem janelas")
    func units() {
        let weekly = #"{"limits":[{"window":{"duration":7,"timeUnit":"TIME_UNIT_DAY"},"detail":{"limit":"50","used":"10"}}]}"#
        #expect(KimiCodeParser.windows(from: Data(weekly.utf8))?.map(\.usedPercent) == [20])
        #expect(KimiCodeParser.windows(from: Data(#"{"usages":{}}"#.utf8)) == nil)
        #expect(KimiCodeParser.windows(from: Data("<html>".utf8)) == nil)
        #expect(KimiCodeParser.seconds(of: ["duration": 2, "timeUnit": "TIME_UNIT_HOUR"]) == 7_200)
        #expect(KimiCodeParser.seconds(of: ["duration": 2, "timeUnit": "TIME_UNIT_YEAR"]) == nil)
        #expect(KimiCodeParser.planName(from: Data(#"{"user_level_name":"Allegretto"}"#.utf8)) == "Allegretto")
    }

    @Test("Saldo da plataforma, em dólar ou yuan conforme a região")
    func balance() throws {
        let data = try Fixture.data("moonshot-balance.json")
        let dollars = try #require(MoonshotBalanceParser.reading(from: data, currency: "USD"))
        #expect(dollars.windows.isEmpty)
        #expect(
            dollars.details.map { "\($0.label): \(plain($0.value) ?? "")" } == [
                "Saldo disponível: US$ 49,59", "Cupons: US$ 46,59", "Saldo em dinheiro: US$ 3,00",
            ])
        let yuan = try #require(MoonshotBalanceParser.reading(from: data, currency: "CNY"))
        #expect(plain(yuan.details.first?.value)?.contains("49,59") == true)
        #expect(yuan.details.first?.value != dollars.details.first?.value)

        let owing = #"{"code":0,"data":{"available_balance":0,"voucher_balance":0,"cash_balance":-1.5},"status":true}"#
        let empty = try #require(MoonshotBalanceParser.reading(from: Data(owing.utf8), currency: "USD"))
        #expect(plain(empty.details.first { $0.label == "Saldo em dinheiro" }?.value) == "-US$ 1,50 (em débito)")
        #expect(empty.details.last?.label == "Aviso")
        #expect(MoonshotBalanceParser.reading(from: Data(#"{"code":0,"data":{}}"#.utf8), currency: "USD") == nil)
    }

    @Test("Login do Kimi Code CLI no disco: o mais recente, e o vencido pede novo login")
    func cliCredentials() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(KimiCodeCredentials.find(in: [folder.url], now: now) == nil)

        let old = try folder.write(#"{"access_token":"old-token","expires_at":1790003600}"#, to: "home/credentials/kimi-code.json")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: old.path)
        try folder.write(#"{"access_token":"new-token","expires_at":1790003600}"#, to: "home/credentials/kimi-code-env-abc.json")
        try folder.write(#"{"access_token":"other-tool"}"#, to: "home/credentials/other.json")
        let home = folder.url.appendingPathComponent("home")
        #expect(KimiCodeCredentials.find(in: [home], now: now) == .token("new-token"))

        let expired = KimiCodeCredentials.find(in: [home], now: now.addingTimeInterval(7_200))
        guard case .expired(let message) = expired else {
            Issue.record("esperava login vencido, veio \(String(describing: expired))")
            return
        }
        #expect(message.contains("/login"))
    }
}

@Suite("GLM Coding Plan (Z.ai e Zhipu)")
struct GLMParserTests {
    @Test("Plano de créditos: sessão e semana contadas em créditos")
    func creditsPlan() throws {
        let data = try Fixture.data("glm-quota-credits.json")
        let now = Date(timeIntervalSince1970: 1_786_073_946.574 - 3_600)  // an hour before the session renews
        let reading = try #require(GLMParser.reading(from: data, now: now))
        #expect(reading.plan == "Lite")
        #expect(reading.windows.map(\.id) == ["glm.session", "glm.weekly"])
        #expect(abs(reading.windows[0].usedPercent - 3.55) < 1e-9)  // 71 of 2000, sharper than "percentage": 3
        #expect(reading.windows.map(\.subtitle) == ["71 de 2.000 créditos", "71 de 10.000 créditos"])
        #expect(reading.windows[0].resetsAt == Date(timeIntervalSince1970: 1_786_073_946.574))
        #expect(reading.windows.map(\.isPrimary) == [true, false])
        #expect(!reading.windows[0].notStarted)
    }

    @Test("Plano antigo: tokens em porcentagem e cota mensal de ferramentas MCP")
    func legacyPlan() throws {
        let data = try Fixture.data("glm-quota-legacy.json")
        let now = Date(timeIntervalSince1970: 1_783_049_703.178 - 7_200)
        let reading = try #require(GLMParser.reading(from: data, now: now))
        #expect(reading.plan == "Pro")
        #expect(reading.windows.map(\.id) == ["glm.session", "glm.weekly", "glm.tools"])  // by kind, not by order
        #expect(reading.windows.map(\.usedPercent) == [8, 7, 14.7])
        #expect(reading.windows.map(\.subtitle) == [nil, nil, "147 de 1.000 chamadas"])
        #expect(reading.details == [DetailRow(label: "Chamadas de ferramentas", value: "busca 84 · leitura de páginas 41 · Zread 8")])
    }

    @Test("Sessão sem horário ainda não começou; horário absurdo é descartado")
    func sessionEdgeCases() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let idle = #"{"code":200,"success":true,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":0}]}}"#
        let notStarted = try #require(GLMParser.reading(from: Data(idle.utf8), now: now)?.windows.first)
        #expect(notStarted.notStarted)
        #expect(notStarted.resetsAt == nil)

        let far =
            #"{"code":200,"success":true,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":20,"nextResetTime":1790036000000}]}}"#
        let window = try #require(GLMParser.reading(from: Data(far.utf8), now: now)?.windows.first)  // 10 hours ahead
        #expect(window.resetsAt == nil)
        #expect(!window.notStarted)
        #expect(window.usedPercent == 20)
    }

    @Test(
        "Erros vêm com HTTP 200 e o código no corpo",
        arguments: [
            (#"{"code":401,"msg":"token expired or incorrect","success":false}"#, ProviderIssue.Kind.unauthorized),
            (#"{"code":1001,"msg":"Authentication parameter not received in Header","success":false}"#, .unauthorized),
            (#"{"code":500,"msg":"当前用户不存在coding plan","success":false}"#, .notSignedIn),
            (#"{"code":1302,"msg":"busy","success":false}"#, .rateLimited),
            (#"{"code":1234,"msg":"x","success":false}"#, .invalidResponse),
        ] as [(String, ProviderIssue.Kind)]
    )
    func bodyErrors(body: String, expected: ProviderIssue.Kind) {
        #expect(GLMParser.bodyIssue(Data(body.utf8))?.kind == expected)
        #expect(GLMParser.reading(from: Data(body.utf8), now: Date()) == nil)
    }

    @Test("Resposta boa não é erro")
    func success() throws {
        #expect(GLMParser.bodyIssue(try Fixture.data("glm-quota-credits.json")) == nil)
        #expect(GLMParser.bodyIssue(Data("<html>".utf8)) == nil)
        #expect(
            GLMParser.bodyIssue(Data(#"{"code":500,"msg":"当前用户不存在coding plan","success":false}"#.utf8))?.message
                == "Esta chave não tem um GLM Coding Plan ativo.")
    }
}

@Suite("Chaves já configuradas no Mac")
struct LocalKeyTests {
    @Test("Claude Code apontado para o provedor: só vale o host exato ou um subdomínio dele")
    func claudeSettings() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        func settings(_ base: String, token: String = "glm-key-123") throws -> [URL] {
            [
                try folder.write(
                    #"{"env":{"ANTHROPIC_BASE_URL":"\#(base)","ANTHROPIC_AUTH_TOKEN":"\#(token)"}}"#, to: "\(UUID().uuidString).json")
            ]
        }
        let glm = GLMCredentials.hosts
        #expect(ClaudeCodeSettings.token(forHosts: glm, in: try settings("https://api.z.ai/api/anthropic")) == "glm-key-123")
        #expect(ClaudeCodeSettings.token(forHosts: glm, in: try settings("https://open.bigmodel.cn/api/anthropic")) == "glm-key-123")
        #expect(ClaudeCodeSettings.token(forHosts: glm, in: try settings("https://www.bigmodel.cn/api/anthropic")) == "glm-key-123")
        #expect(ClaudeCodeSettings.token(forHosts: glm, in: try settings("https://notbigmodel.cn/api")) == nil)
        #expect(ClaudeCodeSettings.token(forHosts: glm, in: try settings("https://evil.example.com/?u=api.z.ai")) == nil)
        #expect(ClaudeCodeSettings.token(forHosts: ["api.kimi.com"], in: try settings("https://api.z.ai/api/anthropic")) == nil)
        #expect(ClaudeCodeSettings.token(forHosts: glm, in: [folder.url.appendingPathComponent("missing.json")]) == nil)
    }

    @Test("Chave do Coding Tool Helper do Z.ai, e a ordem de busca")
    func helperConfig() throws {
        #expect(GLMCredentials.helperKey(in: "plan: glm_coding_plan_global\napi_key: \"helper-key-1\"\n") == "helper-key-1")
        #expect(GLMCredentials.helperKey(in: "plan: x\n  api_key: nested\n") == nil)

        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let helper = try folder.write("api_key: helper-key-1\n", to: "chelper/config.yaml")
        let claude = try folder.write(
            #"{"env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic","ANTHROPIC_AUTH_TOKEN":"claude-key-1"}}"#, to: "settings.json")
        #expect(GLMCredentials.find(claudeSettings: [claude], helperConfig: helper) == .token("claude-key-1"))
        #expect(GLMCredentials.find(claudeSettings: [], helperConfig: helper) == .token("helper-key-1"))
        #expect(GLMCredentials.find(claudeSettings: [], helperConfig: folder.url.appendingPathComponent("none.yaml")) == nil)
    }
}

@Suite("MiniMax Token Plan")
struct MiniMaxParserTests {
    @Test("Formato atual: porcentagem restante vale mais que as contagens zeradas")
    func currentPlan() throws {
        let reading = try #require(MiniMaxParser.reading(from: try Fixture.data("minimax-remains.json")))
        #expect(reading.windows.map(\.id) == ["minimax.session", "minimax.weekly"])
        #expect(reading.windows.map(\.usedPercent) == [4, 1])  // 96% and 99% remaining
        #expect(reading.windows.map(\.subtitle) == [nil, nil])
        #expect(reading.windows[0].resetsAt == Date(timeIntervalSince1970: 1_780_297_200))
        #expect(reading.windows.map(\.windowSeconds) == [18_000, 604_800])
        #expect(reading.windows.map(\.isPrimary) == [true, false])
    }

    @Test("Formato antigo: a contagem é o que resta")
    func legacyPlan() throws {
        let reading = try #require(MiniMaxParser.reading(from: try Fixture.data("minimax-remains-legacy.json")))
        let session = try #require(reading.windows.first)
        #expect(reading.windows.count == 1)
        #expect(abs(session.usedPercent - 84.8) < 1e-9)  // 228 of 1500 left
        #expect(session.subtitle == "228 de 1.500 restantes")
    }

    @Test("Faixas ilimitadas somem, esgotadas ficam cheias, e o vídeo vira detalhe")
    func lanes() throws {
        let json = """
            {"base_resp":{"status_code":0},"model_remains":[
              {"model_name":"general","start_time":1780279200000,"end_time":1780293600000,"current_interval_status":2,
               "current_weekly_status":3,"current_weekly_total_count":0},
              {"model_name":"video","current_interval_remaining_percent":70}]}
            """
        let reading = try #require(MiniMaxParser.reading(from: Data(json.utf8)))
        #expect(reading.windows.map(\.id) == ["minimax.session"])
        #expect(reading.windows.first?.usedPercent == 100)
        #expect(reading.windows.first?.windowSeconds == 14_400)  // the 20h block lasts 4 hours
        #expect(reading.details == [DetailRow(label: "Vídeo", value: "30% usado")])
    }

    @Test(
        "Erros no base_resp",
        arguments: [(1004, ProviderIssue.Kind.unauthorized), (2049, .unauthorized), (1002, .rateLimited), (1008, .invalidResponse)]
    )
    func bodyErrors(code: Int, expected: ProviderIssue.Kind) {
        let body = Data(#"{"base_resp":{"status_code":\#(code),"status_msg":"x"}}"#.utf8)
        #expect(MiniMaxParser.bodyIssue(body)?.kind == expected)
        #expect(MiniMaxParser.reading(from: body) == nil)
        #expect(MiniMaxParser.bodyIssue(Data(#"{"base_resp":{"status_code":0}}"#.utf8)) == nil)
    }

    @Test("Chave do MiniMax CLI: chave, token OAuth e token vencido (em ms)")
    func cliConfig() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let withKey = try folder.write(#"{"api_key":"sk-cp-key","region":"global"}"#, to: "a/config.json")
        #expect(MiniMaxCredentials.find(claudeSettings: [], cliConfig: withKey, now: now) == .token("sk-cp-key"))
        let oauth = try folder.write(#"{"oauth":{"access_token":"oauth-token","expires_at":1790003600000}}"#, to: "b/config.json")
        #expect(MiniMaxCredentials.find(claudeSettings: [], cliConfig: oauth, now: now) == .token("oauth-token"))
        guard case .expired = MiniMaxCredentials.find(claudeSettings: [], cliConfig: oauth, now: now.addingTimeInterval(7_200)) else {
            Issue.record("esperava login vencido")
            return
        }
        let claude = try folder.write(
            #"{"env":{"ANTHROPIC_BASE_URL":"https://api.minimax.io/anthropic","ANTHROPIC_AUTH_TOKEN":"claude-mm"}}"#, to: "s.json")
        #expect(MiniMaxCredentials.find(claudeSettings: [claude], cliConfig: withKey, now: now) == .token("claude-mm"))
    }
}

@Suite("DeepSeek")
struct DeepSeekParserTests {
    @Test("Saldo com bônus e recarga, pelo exemplo oficial")
    func balance() throws {
        let reading = try #require(DeepSeekParser.reading(from: try Fixture.data("deepseek-balance.json")))
        #expect(reading.windows.isEmpty)
        #expect(reading.details.count == 1)
        #expect(reading.details.first?.label == "Saldo")
        let value = try #require(plain(reading.details.first?.value))
        #expect(value.contains("110,00") && value.contains("100,00") && value.contains("10,00 de bônus"))
    }

    @Test("Duas moedas e saldo insuficiente")
    func currenciesAndEmpty() throws {
        let json =
            #"{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0.00"},{"currency":"CNY","total_balance":"0.50"}]}"#
        let reading = try #require(DeepSeekParser.reading(from: Data(json.utf8)))
        #expect(reading.details.map(\.label) == ["Saldo em USD", "Saldo em CNY", "Aviso"])
        #expect(DeepSeekParser.reading(from: Data(#"{"is_available":true,"balance_infos":[]}"#.utf8)) == nil)
    }

    @Test("Chave configurada no Codex para o DeepSeek")
    func codexConfig() {
        let toml = """
            model = "gpt-5"

            [model_providers.openai-compat]
            base_url = "https://example.com/v1"
            experimental_bearer_token = "other-token"

            [model_providers.deepseek]
            name = "DeepSeek"
            base_url = "https://api.deepseek.com/"
            experimental_bearer_token = "ds-token-123"
            """
        #expect(DeepSeekCredentials.codexToken(in: toml) == "ds-token-123")
        #expect(DeepSeekCredentials.codexToken(in: "[model_providers.x]\nbase_url = \"https://api.deepseek.com\"\n") == nil)
        #expect(
            DeepSeekCredentials.codexToken(
                in: "[profiles.deepseek]\nbase_url = \"https://api.deepseek.com\"\nexperimental_bearer_token = \"t\"\n") == nil)
    }
}

@Suite("Doubao e Qwen pelas CLIs oficiais")
struct VendorCLITests {
    @Test("arkcli: Coding Plan com sessão, semana e mês; horários em UTC+8")
    func arkcli() throws {
        guard case .reading(let reading) = ArkCLIParser.outcome(from: try Fixture.data("arkcli-usage-plan.json")) else {
            Issue.record("esperava uma leitura")
            return
        }
        #expect(reading.plan == "Coding Plan")
        #expect(reading.windows.map(\.title) == ["Sessão (5h)", "Semanal", "Mensal"])
        #expect(abs(reading.windows[1].usedPercent - 3.182143) < 1e-9)
        #expect(reading.windows[0].resetsAt == Date(timeIntervalSince1970: 1_782_226_478))
        #expect(reading.windows[1].resetsAt == Date(timeIntervalSince1970: 1_782_662_400))  // Monday 00:00 in China
        #expect(reading.windows.map(\.isPrimary) == [true, false, false])
    }

    @Test("arkcli: sem assinatura, várias assinaturas e saída estranha")
    func arkcliEdgeCases() {
        let none = #"{"viewer":{},"items":[{"product":"coding-plan","subscribed":false,"periods":[]}]}"#
        guard case .noPlan = ArkCLIParser.outcome(from: Data(none.utf8)) else {
            Issue.record("esperava sem plano")
            return
        }
        let two = """
            {"items":[{"product":"coding-plan","tier":"lite","subscribed":true,"periods":[{"label":"session","percent":10}]},
            {"product":"agent-plan","subscribed":true,"periods":[{"label":"5h","percent":20},{"label":"daily","percent":5}]}]}
            """
        guard case .reading(let reading) = ArkCLIParser.outcome(from: Data(two.utf8)) else {
            Issue.record("esperava uma leitura")
            return
        }
        #expect(reading.plan == "Coding Plan Lite")
        #expect(reading.windows.map(\.title) == ["Coding Plan · Sessão (5h)", "Agent Plan · Sessão (5h)"])
        #expect(ArkCLIParser.outcome(from: Data("usage: arkcli …".utf8)) == .unreadable)
    }

    @Test("bl: Coding Plan do Qwen com sessão, semana e mês de cobrança")
    func bailian() throws {
        guard case .reading(let reading) = BailianCLIParser.outcome(from: try Fixture.data("bailian-coding-plan.json")) else {
            Issue.record("esperava uma leitura")
            return
        }
        #expect(reading.plan == "Pro")
        #expect(reading.windows.map(\.id) == ["qwen.session", "qwen.weekly", "qwen.monthly"])
        #expect(reading.windows.map(\.usedPercent) == [38, 50, 95])
        #expect(reading.windows.first?.subtitle == "38 de 100 requisições")
        #expect(reading.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_786_000_000))
        #expect(
            BailianCLIParser.outcome(from: Data(#"{"instanceType":"pro"}"#.utf8))
                == .noPlan("Nenhum Coding Plan ativo nesta conta do Model Studio."))
        #expect(BailianCLIParser.outcome(from: Data(#"{"error":"not logged in"}"#.utf8)) == .unreadable)
    }

    private func service(folders: [URL]) -> CommandService {
        CommandService(
            provider: .copilot, name: "Teste", source: "CLI de teste", executables: ["fake-cli"], pathVariable: "FAKE_CLI_PATH",
            loginFolders: folders, arguments: ["usage", "--format", "json"], installHint: "Instale a CLI.", loginHint: "Entre na CLI.",
            read: { ArkCLIParser.outcome(from: $0) }
        )
    }

    @Test("Provedor por CLI: ausente, sem login, com dados reaproveitados e com falhas")
    func commandProvider() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let bin = folder.url.appendingPathComponent("bin")
        let clock = TestClock()
        let runner = ScriptedCommandRunner { _ in CommandOutput(status: 0, stdout: (try? Fixture.data("arkcli-usage-plan.json")) ?? Data())
        }
        let login = folder.url.appendingPathComponent("login")

        let absent = CommandUsageProvider(service: service(folders: [login]), runner: runner, searchDirectories: [bin], environment: [:])
        #expect(await absent.snapshot(previous: nil).status == .notInstalled)

        let executable = try folder.write("#!/bin/sh\n", to: "bin/fake-cli")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let provider = CommandUsageProvider(
            service: service(folders: [login]), runner: runner, searchDirectories: [bin], environment: [:], now: clock.provider)
        #expect(await provider.snapshot(previous: nil).issue == .notSignedIn)  // no login folder yet
        #expect(runner.calls.isEmpty)

        try FileManager.default.createDirectory(at: login, withIntermediateDirectories: true)
        let snapshot = await provider.snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.source == "CLI de teste")
        #expect(runner.calls.first?.executable == executable.path)
        #expect(runner.calls.first?.arguments == ["usage", "--format", "json"])
        clock.advance(by: 30)
        _ = await provider.snapshot(previous: snapshot)
        #expect(runner.calls.count == 1)  // reused

        let failing = CommandUsageProvider(
            service: service(folders: [login]), runner: ScriptedCommandRunner { _ in CommandOutput(status: 1, stdout: Data()) },
            searchDirectories: [], environment: ["FAKE_CLI_PATH": executable.path])
        #expect(await failing.snapshot(previous: nil).message == "Entre na CLI.")
        let silent = CommandUsageProvider(
            service: service(folders: [login]), runner: ScriptedCommandRunner { _ in nil }, searchDirectories: [bin], environment: [:])
        #expect(await silent.snapshot(previous: nil).issue == .network)
    }
}

@Suite("Serviços chineses ligados ao provedor com chave")
struct ChineseServiceTests {
    let clock = TestClock(Date(timeIntervalSince1970: 1_786_073_946.574 - 3_600))
    let nowhere = [URL(fileURLWithPath: "/nonexistent/settings.json")]

    private func provider(_ service: KeyedService, _ http: MockHTTPClient, key: String? = "key-12345678") -> KeyedUsageProvider {
        let secrets = MemorySecretStore(key.map { [service.account: $0] } ?? [:])
        return KeyedUsageProvider(service: service, http: http, secrets: secrets, now: clock.provider)
    }

    @Test("GLM: chave crua (sem Bearer); chave da China cai para o BigModel")
    func glm() async throws {
        let quota = try Fixture.data("glm-quota-credits.json")
        let http = MockHTTPClient { request in
            // An international host refuses a mainland key with HTTP 200 and the code in the body.
            request.url?.host() == "api.z.ai"
                ? HTTPResponse(status: 200, body: Data(#"{"code":401,"msg":"token expired or incorrect","success":false}"#.utf8))
                : HTTPResponse(status: 200, body: quota)
        }
        let glm = KeyedService.glm(claudeSettings: nowhere, helperConfig: URL(fileURLWithPath: "/nonexistent.yaml"))
        let snapshot = await provider(glm, http).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.plan == "Lite")
        #expect(snapshot.windows.count == 2)
        #expect(
            http.requests.map { $0.url?.absoluteString } == [
                "https://api.z.ai/api/monitor/usage/quota/limit", "https://open.bigmodel.cn/api/monitor/usage/quota/limit",
            ])
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "key-12345678")
    }

    @Test("GLM: chave sem Coding Plan mostra o motivo")
    func glmWithoutPlan() async {
        let http = MockHTTPClient(status: 200, body: Data(#"{"code":500,"msg":"当前用户不存在coding plan","success":false}"#.utf8))
        let glm = KeyedService.glm(claudeSettings: nowhere, helperConfig: URL(fileURLWithPath: "/nonexistent.yaml"))
        let snapshot = await provider(glm, http).snapshot(previous: nil)
        #expect(snapshot.issue == .notSignedIn)
        #expect(snapshot.message == "Esta chave não tem um GLM Coding Plan ativo.")
    }

    @Test("MiniMax: Bearer no endpoint do Token Plan; erro no base_resp troca de região")
    func minimax() async throws {
        let remains = try Fixture.data("minimax-remains.json")
        let http = MockHTTPClient { request in
            request.url?.host() == "api.minimax.io"
                ? HTTPResponse(status: 200, body: Data(#"{"base_resp":{"status_code":1004,"status_msg":"login fail"}}"#.utf8))
                : HTTPResponse(status: 200, body: remains)
        }
        let minimax = KeyedService.minimax(claudeSettings: nowhere, cliConfig: URL(fileURLWithPath: "/nonexistent.json"))
        let snapshot = await provider(minimax, http).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(http.requests.last?.url?.absoluteString == "https://api.minimaxi.com/v1/token_plan/remains")
        #expect(http.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer key-12345678")
    }

    @Test("Kimi Code: login do CLI, uso e plano pelo /me")
    func kimiCode() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try folder.write(#"{"access_token":"cli-token","expires_at":1890000000}"#, to: "home/credentials/kimi-code.json")
        let usages = try Fixture.data("kimi-code-usages-global.json")
        let http = MockHTTPClient { request in
            HTTPResponse(
                status: 200, body: request.url?.lastPathComponent == "me" ? Data(#"{"user_level_name":"Allegretto"}"#.utf8) : usages)
        }
        let kimi = KeyedService.kimiCode(homes: [folder.url.appendingPathComponent("home")], claudeSettings: nowhere)
        let snapshot = await provider(kimi, http, key: nil).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.plan == "Allegretto")
        #expect(snapshot.windows.map(\.id) == ["kimi.session", "kimi.weekly"])
        #expect(
            http.requests.map { $0.url?.absoluteString } == ["https://api.kimi.ai/coding/v1/usages", "https://api.kimi.ai/coding/v1/me"])
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer cli-token")
    }

    @Test("Kimi API: saldo em dólar no site internacional e em yuan na China")
    func kimiAPI() async throws {
        let balance = try Fixture.data("moonshot-balance.json")
        let mainland = MockHTTPClient { request in
            request.url?.host() == "api.moonshot.ai" ? HTTPResponse(status: 401, body: Data()) : HTTPResponse(status: 200, body: balance)
        }
        let yuan = await provider(.kimiAPI(claudeSettings: nowhere), mainland).snapshot(previous: nil)
        #expect(yuan.status == .ok)
        #expect(yuan.windows.isEmpty)
        let dollars = await provider(.kimiAPI(claudeSettings: nowhere), MockHTTPClient(status: 200, body: balance)).snapshot(previous: nil)
        #expect(plain(dollars.details.first?.value) == "US$ 49,59")
        #expect(yuan.details.first?.value != dollars.details.first?.value)
    }

    @Test("DeepSeek: saldo pelo endpoint oficial; sem chave, lê a do Claude Code")
    func deepSeek() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let settings = try folder.write(
            #"{"env":{"ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"ds-claude"}}"#, to: "s.json")
        let http = MockHTTPClient(status: 200, body: try Fixture.data("deepseek-balance.json"))
        let deepSeek = KeyedService.deepSeek(claudeSettings: [settings], codexConfig: URL(fileURLWithPath: "/nonexistent.toml"))
        let snapshot = await provider(deepSeek, http, key: nil).snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.details.first?.label == "Saldo")
        #expect(http.requests.first?.url?.absoluteString == "https://api.deepseek.com/user/balance")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer ds-claude")
    }

    @Test("Sem chave nem login, cada serviço diz onde pôr a chave")
    func unconfigured() async {
        let http = MockHTTPClient(status: 200)
        for service in [
            KeyedService.glm(claudeSettings: nowhere, helperConfig: URL(fileURLWithPath: "/n.yaml")),
            .kimiCode(homes: [URL(fileURLWithPath: "/nonexistent")], claudeSettings: nowhere), .kimiAPI(claudeSettings: nowhere),
            .minimax(claudeSettings: nowhere, cliConfig: URL(fileURLWithPath: "/n.json")),
            .deepSeek(claudeSettings: nowhere, codexConfig: URL(fileURLWithPath: "/n.toml")),
        ] {
            let snapshot = await provider(service, http, key: nil).snapshot(previous: nil)
            #expect(snapshot.status == .notInstalled, "\(service.name)")
            #expect(snapshot.message?.contains("Chaves de API") == true)
        }
        #expect(http.requests.isEmpty)
        let kimiAPI = await provider(.kimiAPI(claudeSettings: nowhere), http, key: nil).snapshot(previous: nil)
        #expect(kimiAPI.message == "Defina a chave da API da plataforma Kimi em Ajustes › Chaves de API.")
        let refused = await provider(.kimiAPI(claudeSettings: nowhere), MockHTTPClient(status: 401)).snapshot(previous: nil)
        #expect(refused.message == "A chave da plataforma Kimi foi recusada — confira em Ajustes › Chaves de API.")
    }
}
