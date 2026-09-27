import Foundation
import Observation

/// The app's single source of truth: the latest snapshot per provider and which ones are refreshing.
///
/// Refreshes run concurrently (each provider is an actor); a refresh requested while one is
/// in flight for the same provider joins it instead of starting another.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshots: [ProviderID: ProviderSnapshot]
    public private(set) var refreshing: Set<ProviderID> = []
    /// Providers to refresh and show. Registered providers outside this set are left alone.
    public var enabledProviders: Set<ProviderID>

    @ObservationIgnored private let providers: [ProviderID: any UsageProvider]
    @ObservationIgnored private let persistence: (any SnapshotPersisting)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var inFlight: [ProviderID: Task<Void, Never>] = [:]
    @ObservationIgnored private var autoRefresh: Task<Void, Never>?

    public init(
        providers: [any UsageProvider],
        persistence: (any SnapshotPersisting)? = nil,
        enabledProviders: Set<ProviderID> = Set(ProviderID.allCases),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        var byID: [ProviderID: any UsageProvider] = [:]
        for provider in providers { byID[provider.id] = provider }
        self.providers = byID
        self.persistence = persistence
        self.enabledProviders = enabledProviders
        self.now = now

        var initial = persistence?.load() ?? [:]
        for provider in ProviderID.allCases where initial[provider] == nil {
            initial[provider] = ProviderSnapshot(provider: provider)
        }
        snapshots = initial
    }

    /// Registered and enabled providers, in display order.
    public var providerIDs: [ProviderID] {
        ProviderID.allCases.filter { providers[$0] != nil && enabledProviders.contains($0) }
    }

    public var isRefreshing: Bool { !refreshing.isEmpty }

    /// Starts refreshing every provider now and then every `interval` seconds.
    public func startAutoRefresh(every interval: TimeInterval) {
        autoRefresh?.cancel()
        refreshAll()
        autoRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(interval, 10)))
                guard !Task.isCancelled else { return }
                self?.refreshAll()
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefresh?.cancel()
        autoRefresh = nil
    }

    /// Fire-and-forget refresh of every enabled provider.
    public func refreshAll(reason: RefreshReason = .automatic) {
        for id in providerIDs { requestRefresh(id, reason: reason) }
    }

    /// Fire-and-forget refresh of one provider.
    public func requestRefresh(_ id: ProviderID, reason: RefreshReason = .automatic) {
        _ = refreshTask(for: id, reason: reason)
    }

    /// Refreshes one provider and returns when its snapshot is updated.
    public func refresh(_ id: ProviderID, reason: RefreshReason = .automatic) async {
        await refreshTask(for: id, reason: reason)?.value
    }

    /// Refreshes every enabled provider concurrently and returns when all are done.
    public func refreshAllAndWait(reason: RefreshReason = .automatic) async {
        let tasks = providerIDs.compactMap { refreshTask(for: $0, reason: reason) }
        for task in tasks { await task.value }
    }

    /// Refreshes `id` only if its last attempt is older than `age` (used when the panel opens).
    public func refreshIfStale(_ id: ProviderID, olderThan age: TimeInterval = 30) {
        let checked = snapshots[id]?.checkedAt ?? .distantPast
        if now().timeIntervalSince(checked) > age { requestRefresh(id) }
    }

    /// Refreshes every enabled provider whose last attempt is older than `age`.
    public func refreshStale(olderThan age: TimeInterval = 30) {
        for id in providerIDs { refreshIfStale(id, olderThan: age) }
    }

    private func refreshTask(for id: ProviderID, reason: RefreshReason) -> Task<Void, Never>? {
        if let running = inFlight[id] { return running }
        guard let provider = providers[id], enabledProviders.contains(id) else { return nil }
        refreshing.insert(id)
        let previous = snapshots[id]
        let task = Task { [weak self] in
            let snapshot = await provider.snapshot(previous: previous, reason: reason)
            self?.complete(id, with: snapshot)
        }
        inFlight[id] = task
        return task
    }

    private func complete(_ id: ProviderID, with snapshot: ProviderSnapshot) {
        snapshots[id] = snapshot
        refreshing.remove(id)
        inFlight[id] = nil
        persistence?.save(snapshots)
    }
}
