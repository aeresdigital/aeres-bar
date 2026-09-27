import Foundation
import Testing
import os

@testable import AERESBarCore

/// Returns scripted snapshots and counts refreshes.
actor FakeProvider: UsageProvider {
    nonisolated let id: ProviderID
    private(set) var calls = 0
    private(set) var reasons: [RefreshReason] = []
    private let delay: Duration
    private let usedPercent: Double

    init(_ id: ProviderID, usedPercent: Double = 42, delay: Duration = .zero) {
        self.id = id
        self.usedPercent = usedPercent
        self.delay = delay
    }

    func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot {
        calls += 1
        reasons.append(reason)
        if delay > .zero { try? await Task.sleep(for: delay) }
        var snapshot = previous ?? ProviderSnapshot(provider: id)
        snapshot.windows = [UsageWindow(id: "w", title: "Semanal", usedPercent: usedPercent, windowSeconds: 604_800)]
        snapshot.checkedAt = Date()
        snapshot.markFresh(at: Date(), source: "fake")
        return snapshot
    }
}

/// Keeps snapshots in memory and counts saves.
final class MemorySnapshotStore: SnapshotPersisting {
    private let state: OSAllocatedUnfairLock<(stored: [ProviderID: ProviderSnapshot], saves: Int)>

    init(_ stored: [ProviderID: ProviderSnapshot] = [:]) {
        state = OSAllocatedUnfairLock(initialState: (stored, 0))
    }

    func load() -> [ProviderID: ProviderSnapshot] { state.withLock { $0.stored } }

    func save(_ snapshots: [ProviderID: ProviderSnapshot]) {
        state.withLock {
            $0.stored = snapshots
            $0.saves += 1
        }
    }

    var saves: Int { state.withLock { $0.saves } }
}

@Suite("Store de uso")
@MainActor
struct UsageStoreTests {
    @Test("Começa com o cache e placeholders para quem não tem cache")
    func initialState() {
        let cached = ProviderSnapshot(provider: .claude, status: .stale, windows: [UsageWindow(id: "s", title: "S", usedPercent: 12)])
        let store = UsageStore(
            providers: [FakeProvider(.claude), FakeProvider(.codex)], persistence: MemorySnapshotStore([.claude: cached]))
        #expect(store.snapshots[.claude]?.windows.first?.usedPercent == 12)
        #expect(store.snapshots[.codex]?.status == .loading)
        #expect(store.snapshots[.antigravity]?.status == .loading)
        #expect(store.providerIDs == [.claude, .codex])
    }

    @Test("Atualiza, persiste e limpa o estado de carregamento")
    func refresh() async {
        let persistence = MemorySnapshotStore()
        let store = UsageStore(providers: [FakeProvider(.claude, usedPercent: 73)], persistence: persistence)
        await store.refresh(.claude)
        #expect(store.snapshots[.claude]?.status == .ok)
        #expect(store.snapshots[.claude]?.windows.first?.usedPercent == 73)
        #expect(store.refreshing.isEmpty)
        #expect(persistence.saves == 1)
    }

    @Test("Pedidos simultâneos para o mesmo provedor viram uma consulta só")
    func coalescesRequests() async {
        let provider = FakeProvider(.codex, delay: .milliseconds(50))
        let store = UsageStore(providers: [provider])
        store.requestRefresh(.codex)
        store.requestRefresh(.codex)
        #expect(store.refreshing == [.codex])
        await store.refresh(.codex)
        #expect(await provider.calls == 1)
    }

    @Test("Atualiza todos em paralelo")
    func refreshAll() async {
        let providers = ProviderID.allCases.map { FakeProvider($0) }
        let store = UsageStore(providers: providers)
        await store.refreshAllAndWait()
        for provider in providers {
            #expect(await provider.calls == 1)
        }
        #expect(store.snapshots.values.allSatisfy { $0.status == .ok })
    }

    @Test("Só atualiza ao abrir o painel se a leitura estiver velha")
    func refreshIfStale() async throws {
        let provider = FakeProvider(.claude)
        let store = UsageStore(providers: [provider])
        await store.refresh(.claude)
        store.refreshIfStale(.claude, olderThan: 30)
        #expect(store.refreshing.isEmpty)
        store.refreshIfStale(.claude, olderThan: -1)
        #expect(store.refreshing == [.claude])
        await store.refresh(.claude)
        #expect(await provider.calls == 2)
    }

    @Test("Provedor desconhecido é ignorado")
    func unknownProvider() async {
        let store = UsageStore(providers: [FakeProvider(.claude)])
        await store.refresh(.antigravity)
        #expect(store.snapshots[.antigravity]?.status == .loading)
    }

    @Test("Atualização automática periódica")
    func autoRefresh() async throws {
        let provider = FakeProvider(.claude)
        let store = UsageStore(providers: [provider])
        store.startAutoRefresh(every: 10)
        await store.refresh(.claude)
        store.stopAutoRefresh()
        #expect(await provider.calls == 1)
    }

    @Test("O botão Atualizar pede uma leitura manual a todos")
    func manualRefresh() async {
        let claude = FakeProvider(.claude)
        let codex = FakeProvider(.codex, delay: .milliseconds(30))
        let store = UsageStore(providers: [claude, codex])
        store.refreshAll(reason: .manual)
        #expect(store.isRefreshing)
        await store.refreshAllAndWait()  // joins the manual refreshes already running
        #expect(!store.isRefreshing)
        #expect(await claude.reasons == [.manual])
        #expect(await codex.reasons == [.manual])
    }

    @Test("Provedores desligados não são consultados nem listados")
    func disabledProviders() async {
        let claude = FakeProvider(.claude)
        let codex = FakeProvider(.codex)
        let store = UsageStore(providers: [claude, codex], enabledProviders: [.claude])
        #expect(store.providerIDs == [.claude])
        await store.refreshAllAndWait()
        store.requestRefresh(.codex)
        #expect(store.refreshing.isEmpty)
        #expect(await codex.calls == 0)

        store.enabledProviders.insert(.codex)
        #expect(store.providerIDs == [.claude, .codex])
        await store.refresh(.codex)
        #expect(await codex.calls == 1)
    }

    @Test("Ao abrir o painel, só relê quem está velho")
    func refreshStale() async {
        let claude = FakeProvider(.claude)
        let codex = FakeProvider(.codex)
        let store = UsageStore(providers: [claude, codex])
        await store.refresh(.claude)
        store.refreshStale(olderThan: 30)
        #expect(store.refreshing == [.codex])
        await store.refresh(.codex)
        #expect(await claude.calls == 1)
        #expect(await codex.calls == 1)
    }
}

@Suite("Persistência e preferências")
struct PersistenceTests {
    @Test("Cache em disco: ida e volta, e leituras restauradas ficam em cache")
    func fileStore() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = FileSnapshotStore(fileURL: folder.url.appendingPathComponent("nested/snapshots.json"))
        #expect(store.load().isEmpty)

        let snapshot = ProviderSnapshot(
            provider: .codex,
            status: .ok,
            issue: nil,
            plan: "Pro Lite",
            windows: [
                UsageWindow(id: "codex.primary", title: "Semanal", usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_790_000_000))
            ],
            tokens: TokenSummary(today: TokenCounts(input: 1)),
            limitsUpdatedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )
        store.save([.codex: snapshot])
        let restored = try #require(store.load()[.codex])
        #expect(restored.status == .stale)
        #expect(restored.plan == "Pro Lite")
        #expect(restored.windows == snapshot.windows)
        #expect(restored.tokens == snapshot.tokens)
    }

    @Test("Arquivo corrompido é ignorado")
    func corruptedCache() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = try folder.write("{not json", to: "snapshots.json")
        #expect(FileSnapshotStore(fileURL: file).load().isEmpty)
    }

    @Test("Estados do snapshot")
    func snapshotTransitions() {
        var snapshot = ProviderSnapshot(provider: .claude)
        snapshot.markFailed(ProviderIssue(.network, "offline"))
        #expect(snapshot.status == .error)
        snapshot.markFresh(at: Date(), source: "api")
        #expect(snapshot.status == .ok)
        #expect(snapshot.issue == nil)
        snapshot.markFailed(ProviderIssue(.rateLimited, "calma"))
        #expect(snapshot.status == .stale)
        #expect(snapshot.message == "calma")
        snapshot.markFailed(ProviderIssue(.notInstalled, "sumiu"))
        #expect(snapshot.status == .notInstalled)
    }

    @Test("Preferências persistem e o último provedor não pode ser desligado")
    @MainActor
    func settings() throws {
        let suite = "AERESBarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.barMetric == .mostCritical)
        #expect(settings.barIconStyle == .meters)
        #expect(settings.showPercentInBar)
        #expect(settings.colorAlerts)
        #expect(settings.refreshInterval == 120)
        #expect(settings.enabledProviders == ProviderID.allCases)

        settings.barMetric = .weekly
        settings.barIconStyle = .criticalLogo
        settings.showPercentInBar = false
        settings.showRemaining = true
        settings.refreshInterval = 300
        for provider in ProviderID.allCases { settings.setEnabled(provider, false) }
        #expect(settings.enabledProviders == [.openrouter])  // the last one stays on

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.barMetric == .weekly)
        #expect(reloaded.barIconStyle == .criticalLogo)
        #expect(!reloaded.showPercentInBar)
        #expect(reloaded.showRemaining)
        #expect(reloaded.refreshInterval == 300)
        #expect(reloaded.disabledProviders == Set(ProviderID.allCases).subtracting([.openrouter]))
        #expect(reloaded.barConfig == BarPresenter.Config(metric: .weekly, showRemaining: true, showCountdown: false))

        reloaded.setEnabled(.codex, true)
        #expect(reloaded.isEnabled(.codex))
        #expect(reloaded.enabledProviders == [.codex, .openrouter])
    }

    @Test("Valores inválidos gravados voltam ao padrão")
    @MainActor
    func invalidStoredValues() throws {
        let suite = "AERESBarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("bogus", forKey: "barMetric")
        defaults.set("bogus", forKey: "barIconStyle")
        defaults.set(5.0, forKey: "refreshInterval")
        defaults.set(["codex", "gone"], forKey: "disabledProviders")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.barMetric == .mostCritical)
        #expect(settings.barIconStyle == .meters)
        #expect(settings.refreshInterval == 30)
        #expect(settings.disabledProviders == [.codex])
    }
}
