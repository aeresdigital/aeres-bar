import Foundation
import Testing
import os

@testable import AERESBarCore

/// Returns scripted snapshots and counts refreshes.
actor FakeProvider: UsageProvider {
    nonisolated let id: ProviderID
    private(set) var calls = 0
    private let delay: Duration
    private let usedPercent: Double

    init(_ id: ProviderID, usedPercent: Double = 42, delay: Duration = .zero) {
        self.id = id
        self.usedPercent = usedPercent
        self.delay = delay
    }

    func snapshot(previous: ProviderSnapshot?) async -> ProviderSnapshot {
        calls += 1
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

    @Test("Preferências persistem e o último item não some")
    @MainActor
    func settings() throws {
        let suite = "AERESBarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.barMetric == .mostCritical)
        #expect(settings.colorAlerts)
        #expect(settings.refreshInterval == 120)
        #expect(ProviderID.allCases.allSatisfy(settings.isVisible))

        settings.barMetric = .weekly
        settings.showRemaining = true
        settings.refreshInterval = 300
        settings.setVisible(.codex, false)
        settings.setVisible(.antigravity, false)
        settings.setVisible(.claude, false)  // refused: it is the last one
        #expect(settings.isVisible(.claude))

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.barMetric == .weekly)
        #expect(reloaded.showRemaining)
        #expect(reloaded.refreshInterval == 300)
        #expect(reloaded.hiddenProviders == [.codex, .antigravity])
        #expect(reloaded.barConfig == BarPresenter.Config(metric: .weekly, showRemaining: true, showCountdown: false))

        reloaded.setVisible(.codex, true)
        #expect(reloaded.isVisible(.codex))
    }
}
