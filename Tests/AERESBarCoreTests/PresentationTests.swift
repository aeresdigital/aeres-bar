import Foundation
import Testing

@testable import AERESBarCore

@Suite("Número da barra de menus")
struct BarPresenterTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func snapshot(_ windows: [UsageWindow], tokens: TokenSummary? = nil) -> ProviderSnapshot {
        ProviderSnapshot(provider: .claude, status: .ok, windows: windows, tokens: tokens)
    }

    private var session: UsageWindow {
        UsageWindow(
            id: "s", title: "Sessão", usedPercent: 10, resetsAt: now.addingTimeInterval(3_600), windowSeconds: 18_000, isPrimary: true)
    }

    private var weekly: UsageWindow {
        UsageWindow(id: "w", title: "Semanal", usedPercent: 83, resetsAt: now.addingTimeInterval(86_400), windowSeconds: 604_800)
    }

    @Test("O limite mais crítico decide o número e o alerta")
    func mostCritical() {
        let value = BarPresenter.value(for: snapshot([session, weekly]), config: .init(metric: .mostCritical), now: now)
        #expect(value.text == "83%")
        #expect(value.alert == .warning)
        #expect(value.window?.id == "w")
    }

    @Test("Janela principal e semanal")
    func primaryAndWeekly() {
        #expect(BarPresenter.value(for: snapshot([session, weekly]), config: .init(metric: .primary), now: now).text == "10%")
        let weeklyRemaining = BarPresenter.value(
            for: snapshot([session, weekly]),
            config: .init(metric: .weekly, showRemaining: true, showCountdown: true),
            now: now
        )
        #expect(weeklyRemaining.text == "17% · 1d0h")
    }

    @Test("Janela vencida conta como renovada")
    func expiredWindow() {
        let old = UsageWindow(id: "s", title: "Sessão", usedPercent: 98, resetsAt: now.addingTimeInterval(-60), windowSeconds: 18_000)
        #expect(old.effectiveUsed(at: now) == 0)
        #expect(old.start(now: now) == nil)
        let value = BarPresenter.value(for: snapshot([old]), config: .init(), now: now)
        #expect(value.text == "0%")
        #expect(value.alert == nil)
    }

    @Test("Janela não iniciada não mostra contagem regressiva")
    func notStarted() {
        let idle = UsageWindow(
            id: "w", title: "Semanal", usedPercent: 0, resetsAt: now.addingTimeInterval(604_800), windowSeconds: 604_800, notStarted: true)
        #expect(BarPresenter.value(for: snapshot([idle]), config: .init(showCountdown: true), now: now).text == "0%")
    }

    @Test("Sem dados")
    func noData() {
        #expect(BarPresenter.value(for: nil, config: .init(), now: now).text == "…")
        #expect(BarPresenter.value(for: ProviderSnapshot(provider: .codex), config: .init(), now: now).text == "…")
        let failed = ProviderSnapshot(provider: .antigravity, status: .error)
        let value = BarPresenter.value(for: failed, config: .init(), now: now)
        #expect(value.text == "–")
        #expect(!value.hasData)
    }

    @Test("Tokens de hoje")
    func tokensToday() {
        let tokens = TokenSummary(today: TokenCounts(input: 1_000, output: 2_000, cacheRead: 1_200_000, requests: 3))
        #expect(BarPresenter.value(for: snapshot([], tokens: tokens), config: .init(metric: .tokensToday), now: now).text == "1,2M")
    }

    @Test("Níveis de alerta", arguments: [(79.9, nil), (80, AlertLevel.warning), (94.9, .warning), (95, .critical), (100, .critical)])
    func alertLevels(used: Double, expected: AlertLevel?) {
        #expect(AlertLevel(usedPercent: used) == expected)
    }

    @Test("Descrição para o VoiceOver")
    func accessibility() {
        let value = BarPresenter.value(for: snapshot([session, weekly]), config: .init(), now: now)
        #expect(BarPresenter.accessibilityLabel(for: .claude, value: value, now: now) == "Claude Code: Semanal, 83% usado, renova em 1d")
        #expect(BarPresenter.accessibilityLabel(for: .codex, value: BarValue(text: "–", hasData: false), now: now) == "Codex: sem dados")
    }
}

@Suite("Textos do painel")
struct UsagePresentationTests {
    let calendar = Calendar.saoPaulo

    @Test("Descrição da renovação")
    func resetDescription() throws {
        let now = try #require(iso("2026-09-27T03:30:00Z"))
        var window = UsageWindow(id: "s", title: "Sessão", usedPercent: 10, resetsAt: iso("2026-09-27T08:10:00Z"), windowSeconds: 18_000)
        #expect(UsagePresentation.resetDescription(for: window, now: now, calendar: calendar) == "Renova em 4h 40min · hoje às 05:10")

        window.resetsAt = iso("2026-09-27T03:00:00Z")
        #expect(
            UsagePresentation.resetDescription(for: window, now: now, calendar: calendar)
                == "Renovou hoje às 00:00 — aguardando nova leitura")

        window.resetsAt = nil
        #expect(UsagePresentation.resetDescription(for: window, now: now, calendar: calendar) == "Sem horário de renovação informado")

        window.notStarted = true
        #expect(UsagePresentation.resetDescription(for: window, now: now, calendar: calendar) == "A janela começa a contar no próximo uso")
    }

    @Test("Linha de status do cabeçalho")
    func statusLine() throws {
        let now = try #require(iso("2026-09-27T03:30:00Z"))
        #expect(UsagePresentation.statusLine(for: nil, now: now) == "Carregando…")
        var snapshot = ProviderSnapshot(provider: .claude, status: .ok, limitsUpdatedAt: now.addingTimeInterval(-20))
        #expect(UsagePresentation.statusLine(for: snapshot, now: now) == "Limites lidos há 20 s")
        snapshot.limitsUpdatedAt = now.addingTimeInterval(-2 * 3_600)
        #expect(UsagePresentation.statusLine(for: snapshot, now: now, calendar: calendar) == "Limites de ontem às 22:30 (há 2 h)")
        #expect(UsagePresentation.statusLine(for: ProviderSnapshot(provider: .codex, status: .notInstalled), now: now) == "Não instalado")
        #expect(
            UsagePresentation.statusLine(for: ProviderSnapshot(provider: .codex, status: .error), now: now) == "Limites ainda não lidos")
    }

    @Test(
        "Selos de status",
        arguments: [
            (SnapshotStatus.ok, "ao vivo"), (.stale, "em cache"), (.error, "sem dados"), (.notInstalled, "ausente"),
            (.loading, "carregando"),
        ])
    func badges(status: SnapshotStatus, expected: String) {
        #expect(UsagePresentation.statusBadge(for: status) == expected)
    }

    @Test("Tabela de tokens omite linhas zeradas")
    func tokenTable() {
        let summary = TokenSummary(
            session: TokenCounts(input: 5, output: 10, cacheRead: 100, requests: 1),
            today: TokenCounts(input: 10, output: 20, cacheRead: 200, requests: 2),
            week: TokenCounts(input: 50, output: 90, cacheRead: 900, requests: 9),
            weekIsRolling: false
        )
        let columns = UsagePresentation.tokenColumns(for: summary)
        #expect(columns.map(\.title) == ["Sessão 5h", "Hoje", "Semana"])
        #expect(UsagePresentation.tokenRows(for: columns) == [.total, .input, .output, .cacheRead, .requests])
        #expect(TokenMetric.total.value(in: summary.week) == 1_040)
        #expect(UsagePresentation.tokenColumns(for: TokenSummary()).map(\.title) == ["Hoje", "7 dias"])
    }

    @Test("Textos compactos das linhas do resumo")
    func compactTexts() throws {
        let now = try #require(iso("2026-09-27T03:30:00Z"))
        var window = UsageWindow(
            id: "s", title: "Sessão", usedPercent: 10, resetsAt: now.addingTimeInterval(4 * 3_600 + 51 * 60), windowSeconds: 18_000)
        #expect(UsagePresentation.compactReset(for: window, now: now) == "4h51")
        window.resetsAt = now.addingTimeInterval(-60)
        #expect(UsagePresentation.compactReset(for: window, now: now) == "renovou")
        window.resetsAt = nil
        #expect(UsagePresentation.compactReset(for: window, now: now) == "")
        window.notStarted = true
        #expect(UsagePresentation.compactReset(for: window, now: now) == "—")

        let summary = TokenSummary(
            session: TokenCounts(input: 1_500), today: TokenCounts(input: 118_000_000), week: TokenCounts(input: 3_600_000_000),
            weekIsRolling: false)
        #expect(UsagePresentation.tokenLine(for: summary) == "Tokens: sessão 1,5K · hoje 118M · semana 3,6B")
        #expect(UsagePresentation.tokenLine(for: TokenSummary(today: TokenCounts(input: 10))) == "Tokens: hoje 10 · 7 dias 0")
        #expect(UsagePresentation.tokenLine(for: TokenSummary()) == nil)
    }

    @Test("Cabeçalho e rodapé do painel")
    func headerAndFooter() throws {
        let now = try #require(iso("2026-09-27T03:30:00Z"))
        #expect(UsagePresentation.updatedLine(for: [], now: now) == "Ainda não atualizado")
        let snapshots = [
            ProviderSnapshot(provider: .claude, checkedAt: now.addingTimeInterval(-300)),
            ProviderSnapshot(provider: .codex, checkedAt: now.addingTimeInterval(-12)),
            ProviderSnapshot(provider: .copilot),
        ]
        #expect(UsagePresentation.updatedLine(for: snapshots, now: now) == "Atualizado há 12 s")
        #expect(UsagePresentation.unconfiguredLine(for: []) == nil)
        #expect(UsagePresentation.unconfiguredLine(for: [.ollama, .openrouter]) == "Não configurados: Ollama, OpenRouter")
    }

    @Test("Cota restante por modelo")
    func modelRemaining() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(
            UsagePresentation.remainingDescription(for: ModelQuota(label: "A", remainingFraction: 0.35, resetsAt: nil), now: now)
                == "35% livre")
        #expect(
            UsagePresentation.remainingDescription(for: ModelQuota(label: "B", remainingFraction: nil, resetsAt: nil), now: now)
                == "sem cota")
        let renewed = ModelQuota(label: "C", remainingFraction: 0, resetsAt: Date(timeIntervalSince1970: 10))
        #expect(UsagePresentation.remainingDescription(for: renewed, now: now) == "100% livre")
    }
}

@Suite("Linha de comando")
struct CLICommandTests {
    @Test(
        "Interpretação dos argumentos",
        arguments: [
            ([], CLICommand.runApp),
            (["-psn_0_12345"], .runApp),
            (["--dump"], .dump),
            (["--render-preview", "out"], .renderPreview(directory: "out", demo: false)),
            (["--render-preview", "docs/images", "--demo"], .renderPreview(directory: "docs/images", demo: true)),
            (["--login-item", "off"], .loginItem(.off)),
            (["--set-key", "openrouter"], .setKey(.openRouter)),
            (["--delete-key", "ollama"], .deleteKey(.ollama)),
            (["--version"], .version),
            (["-h"], .help),
        ]
    )
    func parse(arguments: [String], expected: CLICommand) {
        #expect(CLICommand.parse(["AERESBar"] + arguments) == expected)
    }

    @Test("Erros de uso")
    func invalid() {
        guard case .invalid = CLICommand.parse(["AERESBar", "--render-preview"]) else {
            Issue.record("esperava erro para pasta ausente")
            return
        }
        guard case .invalid = CLICommand.parse(["AERESBar", "--render-preview", "--demo"]) else {
            Issue.record("esperava erro para pasta ausente antes de --demo")
            return
        }
        guard case .invalid = CLICommand.parse(["AERESBar", "--login-item", "maybe"]) else {
            Issue.record("esperava erro para ação inválida")
            return
        }
        guard case .invalid(let reason) = CLICommand.parse(["AERESBar", "--set-key", "anthropic"]) else {
            Issue.record("esperava erro para conta de chave desconhecida")
            return
        }
        #expect(reason == "--set-key aceita openrouter ou ollama")
        guard case .invalid = CLICommand.parse(["AERESBar", "--delete-key"]) else {
            Issue.record("esperava erro para conta ausente")
            return
        }
        guard case .invalid = CLICommand.parse(["AERESBar", "--bogus"]) else {
            Issue.record("esperava erro para opção desconhecida")
            return
        }
        #expect(CLICommand.usage.contains("--dump"))
        #expect(CLICommand.usage.contains("--set-key openrouter|ollama"))
    }
}

@Suite("Item único da barra de menus")
struct OverallBarTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// A provider with one window per value; window `n` renews in `n + 1` hours.
    private func snapshot(_ provider: ProviderID, _ used: [Double], tokensToday: Int? = nil) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            status: .ok,
            windows: used.enumerated().map { index, value in
                UsageWindow(
                    id: "\(provider.rawValue).\(index)", title: "Janela \(index)", usedPercent: value,
                    resetsAt: now.addingTimeInterval(3_600 * Double(index + 1)), windowSeconds: 18_000)
            },
            tokens: tokensToday.map { TokenSummary(today: TokenCounts(input: $0)) }
        )
    }

    @Test("O número vem do provedor mais perto do limite; o medidor mostra todos")
    func mostCritical() {
        let snapshots = [
            ProviderID.claude: snapshot(.claude, [38, 74]),
            .codex: snapshot(.codex, [86, 41]),
            .copilot: snapshot(.copilot, [12]),
        ]
        let overall = BarPresenter.overall(for: snapshots, providers: [.claude, .codex, .copilot], config: .init(), now: now)
        #expect(overall.text == "86%")
        #expect(overall.critical == .codex)
        #expect(overall.usedPercent == 86)
        #expect(overall.alert == .warning)
        #expect(overall.hasData)
        #expect(
            overall.levels == [
                OverallBarValue.Level(provider: .claude, usedPercent: 74),
                OverallBarValue.Level(provider: .codex, usedPercent: 86),
                OverallBarValue.Level(provider: .copilot, usedPercent: 12),
            ])
    }

    @Test("Ferramentas ausentes ou sem limites ficam fora do medidor; as que carregam aparecem vazias")
    func excluded() {
        let snapshots = [
            ProviderID.claude: snapshot(.claude, [20]),
            .antigravity: ProviderSnapshot(provider: .antigravity, status: .notInstalled),
            .ollama: ProviderSnapshot(provider: .ollama, status: .ok),  // local models only: no limits
            .openrouter: ProviderSnapshot(provider: .openrouter),  // still loading
        ]
        let overall = BarPresenter.overall(
            for: snapshots, providers: [.claude, .antigravity, .ollama, .openrouter], config: .init(), now: now)
        #expect(overall.levels.map(\.provider) == [.claude, .openrouter])
        #expect(overall.levels.last?.usedPercent == nil)
        #expect(overall.text == "20%")
        #expect(overall.alert == nil)
        #expect(BarPresenter.accessibilityLabel(for: overall) == "AERES Bar: Claude 20%, OpenRouter sem dados")
    }

    @Test("Sem dados: reticências enquanto carrega, traço depois")
    func noData() {
        let loading = BarPresenter.overall(for: [:], providers: [.claude], config: .init(), now: now)
        #expect(loading.text == "…")
        #expect(!loading.hasData)
        #expect(loading.levels.isEmpty)

        let failed = BarPresenter.overall(
            for: [.claude: ProviderSnapshot(provider: .claude, status: .error)], providers: [.claude], config: .init(), now: now)
        #expect(failed.text == "–")
        #expect(failed.critical == nil)
        #expect(BarPresenter.accessibilityLabel(for: failed) == "AERES Bar: sem dados")
    }

    @Test("Tokens de hoje somam todos os provedores; o alerta continua vindo dos limites")
    func tokensToday() {
        let snapshots = [
            ProviderID.claude: snapshot(.claude, [50], tokensToday: 1_200_000),
            .codex: snapshot(.codex, [97], tokensToday: 300_000),
        ]
        let overall = BarPresenter.overall(for: snapshots, providers: [.claude, .codex], config: .init(metric: .tokensToday), now: now)
        #expect(overall.text == "1,5M")
        #expect(overall.critical == .codex)
        #expect(overall.alert == .critical)
        #expect(overall.hasData)

        // Nobody logs tokens: fall back to the most critical limit.
        let limitsOnly = BarPresenter.overall(
            for: [.copilot: snapshot(.copilot, [45])], providers: [.copilot], config: .init(metric: .tokensToday, showRemaining: true),
            now: now)
        #expect(limitsOnly.text == "55%")
    }

    @Test("% restante e tempo até renovar seguem as preferências")
    func preferences() {
        let overall = BarPresenter.overall(
            for: [.claude: snapshot(.claude, [30, 80])], providers: [.claude], config: .init(showRemaining: true, showCountdown: true),
            now: now)
        #expect(overall.text == "20% · 2h00")
    }

    @Test("Estilos de ícone")
    func iconStyles() {
        #expect(BarIconStyle.allCases == [.meters, .criticalLogo])
        #expect(BarIconStyle.allCases.allSatisfy { !$0.title.isEmpty })
    }
}

@Suite("Resumo em anéis do painel")
struct SummaryRingTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func snapshot(_ provider: ProviderID, _ used: Double, title: String = "Semanal") -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            status: .ok,
            windows: [
                UsageWindow(id: "w", title: title, usedPercent: used, resetsAt: now.addingTimeInterval(7_200), windowSeconds: 604_800)
            ],
            tokens: TokenSummary(today: TokenCounts(input: 5_000))
        )
    }

    @Test("Um anel por provedor com limites, na ordem e com os números da barra")
    func rings() {
        let snapshots = [
            ProviderID.claude: snapshot(.claude, 15),
            .codex: snapshot(.codex, 0),
            .antigravity: snapshot(.antigravity, 97),
            .copilot: ProviderSnapshot(provider: .copilot, status: .notInstalled),
            .ollama: ProviderSnapshot(provider: .ollama, status: .ok),  // local models only: no limits
        ]
        let rings = UsagePresentation.summaryRings(
            for: snapshots, providers: [.claude, .codex, .antigravity, .copilot, .ollama], config: .init(), now: now)
        #expect(rings.map(\.provider) == [.claude, .codex, .antigravity])
        #expect(rings.map(\.text) == ["15%", "0%", "97%"])
        #expect(rings.map(\.fraction) == [0.15, 0, 0.97])
        #expect(rings.map(\.alert) == [nil, nil, .critical])
        // The time of day that follows depends on the machine's time zone.
        #expect(rings.first?.description.hasPrefix("Claude Code · Semanal: 15% usado. Renova em 2h · ") == true)
    }

    @Test("Com % restante, o anel mostra o que sobra; o alerta continua vindo do uso")
    func remaining() {
        let rings = UsagePresentation.summaryRings(
            for: [.codex: snapshot(.codex, 86)], providers: [.codex], config: .init(showRemaining: true, showCountdown: true), now: now)
        #expect(rings.first?.text == "14%")  // no countdown under a ring
        #expect(abs((rings.first?.fraction ?? 0) - 0.14) < 1e-9)
        #expect(rings.first?.alert == .warning)
    }

    @Test("Tokens de hoje na barra: os anéis continuam em porcentagem")
    func tokensMetric() {
        let rings = UsagePresentation.summaryRings(
            for: [.claude: snapshot(.claude, 40)], providers: [.claude], config: .init(metric: .tokensToday), now: now)
        #expect(rings.first?.text == "40%")
        #expect(rings.first?.fraction == 0.4)
    }

    @Test("Enquanto carrega, o anel fica vazio")
    func loading() {
        let rings = UsagePresentation.summaryRings(
            for: [.openrouter: ProviderSnapshot(provider: .openrouter)], providers: [.openrouter], config: .init(), now: now)
        #expect(rings.count == 1)
        #expect(rings.first?.fraction == nil)
        #expect(rings.first?.text == "…")
        #expect(rings.first?.description == "OpenRouter: carregando")
        #expect(UsagePresentation.summaryRings(for: [:], providers: [], config: .init(), now: now).isEmpty)
    }
}
