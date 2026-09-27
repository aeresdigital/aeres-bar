import AERESBarCore
import Foundation

/// Sample snapshots covering every state of the UI, for documentation images.
@MainActor
public enum DemoData {
    public static func store(now: Date = Date()) -> UsageStore {
        UsageStore(providers: snapshots(now: now).map(DemoProvider.init))
    }

    static func snapshots(now: Date) -> [ProviderSnapshot] {
        func hours(_ value: Double) -> Date { now.addingTimeInterval(value * 3_600) }
        let week: Double = 7 * 86_400

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
            limitsUpdatedAt: now.addingTimeInterval(-12),
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
            limitsUpdatedAt: now.addingTimeInterval(-12),
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
                ModelQuota(label: "Gemini 3.1 Pro (High)", remainingFraction: 0.38, resetsAt: hours(121)),
                ModelQuota(label: "Claude Sonnet 4.6 (Thinking)", remainingFraction: 0.03, resetsAt: hours(27)),
                ModelQuota(label: "GPT-OSS 120B (Medium)", remainingFraction: 0.03, resetsAt: hours(27)),
            ],
            limitsUpdatedAt: now.addingTimeInterval(-12),
            checkedAt: now,
            source: "Language server local do Antigravity"
        )
        return [claude, codex, antigravity]
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

    func snapshot(previous: ProviderSnapshot?) async -> ProviderSnapshot { fixed }
}
