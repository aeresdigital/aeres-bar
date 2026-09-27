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
        guard case .invalid = CLICommand.parse(["AERESBar", "--bogus"]) else {
            Issue.record("esperava erro para opção desconhecida")
            return
        }
        #expect(CLICommand.usage.contains("--dump"))
    }
}
