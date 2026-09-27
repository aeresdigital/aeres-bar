import Foundation

/// A source of usage data for one service.
///
/// Providers are actors: each owns its incremental log readers and backoff state, and the
/// store calls them concurrently. A refresh never throws — failures are recorded in the
/// returned snapshot (see ``ProviderSnapshot/markFailed(_:)``) so the last good data stays visible.
public protocol UsageProvider: Actor {
    nonisolated var id: ProviderID { get }

    /// Reads the provider and returns an updated snapshot, starting from `previous`.
    func snapshot(previous: ProviderSnapshot?) async -> ProviderSnapshot
}
