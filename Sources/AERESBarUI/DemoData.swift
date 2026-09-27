import AERESBarCore
import Foundation

/// Sample snapshots covering every state of the UI, for documentation images and tests.
@MainActor
public enum DemoData {
    public static func store(now: Date = Date()) -> UsageStore {
        UsageStore(providers: snapshots(now: now).map(DemoProvider.init))
    }

    static func snapshots(now: Date) -> [ProviderSnapshot] {
        func hours(_ value: Double) -> Date { now.addingTimeInterval(value * 3_600) }
        let week: Double = 7 * 86_400
        let month: Double = 30 * 86_400
        let fresh = now.addingTimeInterval(-12)

        let claude = ProviderSnapshot(
            provider: .claude,
            status: .ok,
            plan: "Max 5x",
            windows: [
                UsageWindow(
                    id: "session", title: "Sessão (5h)", usedPercent: 38, resetsAt: hours(2.25), windowSeconds: 18_000, isPrimary: true),
                UsageWindow(
                    id: "weekly_all", title: "Semanal · todos os modelos", usedPercent: 74, resetsAt: hours(84.5), windowSeconds: week),
                UsageWindow(
                    id: "weekly_scoped.Fable", title: "Semanal · Fable", usedPercent: 16, resetsAt: hours(84.5), windowSeconds: week),
            ],
            tokens: TokenSummary(
                session: TokenCounts(input: 312, output: 402_000, cacheRead: 51_900_000, cacheWrite: 612_000, requests: 188),
                today: TokenCounts(input: 941, output: 1_120_000, cacheRead: 117_400_000, cacheWrite: 1_730_000, requests: 532),
                week: TokenCounts(input: 28_100, output: 15_400_000, cacheRead: 3_600_000_000, cacheWrite: 57_400_000, requests: 11_900),
                weekIsRolling: false,
                lastActivity: now.addingTimeInterval(-40)
            ),
            details: [
                DetailRow(label: "Semana por produto", value: "Claude Code 96% · Cowork 3% · Outros 1%"),
                DetailRow(label: "Uso extra", value: "desativado"),
            ],
            limitsUpdatedAt: fresh,
            checkedAt: now,
            source: "API da Anthropic + logs locais"
        )

        let codex = ProviderSnapshot(
            provider: .codex,
            status: .ok,
            plan: "Plus",
            windows: [
                UsageWindow(
                    id: "codex.primary", title: "Sessão (5h)", usedPercent: 86, resetsAt: hours(0.78), windowSeconds: 18_000,
                    isPrimary: true),
                UsageWindow(id: "codex.secondary", title: "Semanal", usedPercent: 41, resetsAt: hours(98), windowSeconds: week),
            ],
            tokens: TokenSummary(
                session: TokenCounts(input: 1_900_000, output: 184_000, cacheRead: 21_300_000, requests: 412),
                today: TokenCounts(input: 2_600_000, output: 251_000, cacheRead: 30_800_000, requests: 596),
                week: TokenCounts(input: 11_700_000, output: 1_320_000, cacheRead: 373_000_000, requests: 3_323),
                weekIsRolling: false,
                lastActivity: now.addingTimeInterval(-300)
            ),
            limitsUpdatedAt: fresh,
            checkedAt: now,
            source: "API do ChatGPT + logs locais"
        )

        let antigravity = ProviderSnapshot(
            provider: .antigravity,
            status: .ok,
            plan: "Pro",
            windows: [
                UsageWindow(
                    id: "ag.gemini-weekly",
                    title: "Modelos Gemini · semanal",
                    subtitle: "Gemini Flash, Gemini Pro",
                    usedPercent: 62,
                    resetsAt: hours(121),
                    windowSeconds: week,
                    isPrimary: true
                ),
                UsageWindow(
                    id: "ag.3p-weekly",
                    title: "Claude e GPT · semanal",
                    subtitle: "Claude Opus, Claude Sonnet, GPT-OSS",
                    usedPercent: 97,
                    resetsAt: hours(27),
                    windowSeconds: week
                ),
            ],
            models: [
                ModelQuota(label: "Gemini 3.8 Flash (High)", remainingFraction: 0.38, resetsAt: hours(121)),
                ModelQuota(label: "Claude Sonnet 4.6 (Thinking)", remainingFraction: 0.03, resetsAt: hours(27)),
            ],
            limitsUpdatedAt: fresh,
            checkedAt: now,
            source: "Language server local do Antigravity"
        )

        let copilot = ProviderSnapshot(
            provider: .copilot,
            status: .ok,
            plan: "Pro",
            windows: [
                UsageWindow(
                    id: "copilot.premium_interactions",
                    title: "Requisições premium",
                    subtitle: "164 de 300 restantes no mês",
                    usedPercent: 45,
                    resetsAt: hours(96),
                    windowSeconds: month,
                    isPrimary: true
                )
            ],
            details: [DetailRow(label: "Chat", value: "ilimitado"), DetailRow(label: "Autocompletar", value: "ilimitado")],
            limitsUpdatedAt: fresh,
            checkedAt: now,
            source: "API do GitHub"
        )

        let ollama = ProviderSnapshot(
            provider: .ollama,
            status: .ok,
            windows: [
                UsageWindow(
                    id: "ollama.session", title: "Sessão (5h)", subtitle: "48 requisições", usedPercent: 22, windowSeconds: 18_000,
                    isPrimary: true),
                UsageWindow(id: "ollama.weekly", title: "Semanal", subtitle: "310 requisições", usedPercent: 58, windowSeconds: week),
            ],
            details: [
                DetailRow(label: "Servidor local", value: "v0.13.2 · em execução"),
                DetailRow(label: "Modelos carregados", value: "qwen3-coder:30b (18,6 GB)"),
            ],
            limitsUpdatedAt: fresh,
            checkedAt: now,
            source: "Ollama Cloud + servidor local"
        )

        let openRouter = ProviderSnapshot(
            provider: .openrouter,
            status: .ok,
            windows: [
                UsageWindow(
                    id: "openrouter.limit",
                    title: "Limite da chave · mensal",
                    subtitle: "US$ 25,50 de US$ 100,00",
                    usedPercent: 25.5,
                    resetsAt: hours(80),
                    windowSeconds: month,
                    isPrimary: true
                )
            ],
            details: [
                DetailRow(label: "Gasto", value: "hoje US$ 1,20 · semana US$ 5,30 · mês US$ 25,50"),
                DetailRow(label: "Saldo", value: "US$ 74,75 de US$ 100,50"),
            ],
            limitsUpdatedAt: fresh,
            checkedAt: now,
            source: "API do OpenRouter"
        )
        return [claude, codex, antigravity, copilot, ollama, openRouter]
    }
}

/// Serves a fixed snapshot.
actor DemoProvider: UsageProvider {
    nonisolated let id: ProviderID
    private let fixed: ProviderSnapshot

    init(_ snapshot: ProviderSnapshot) {
        id = snapshot.provider
        fixed = snapshot
    }

    func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot { fixed }
}
