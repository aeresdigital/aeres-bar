import Foundation
import os

@testable import AERESBarCore

/// Serves a fixed snapshot.
actor StaticProvider: UsageProvider {
    nonisolated let id: ProviderID
    let snapshot: ProviderSnapshot

    init(_ snapshot: ProviderSnapshot) {
        id = snapshot.provider
        self.snapshot = snapshot
    }

    func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot { snapshot }
}

/// Keeps API keys in memory.
final class MemorySecrets: SecretStore {
    private let stored: OSAllocatedUnfairLock<[SecretAccount: String]>

    init(_ secrets: [SecretAccount: String] = [:]) {
        stored = OSAllocatedUnfairLock(initialState: secrets)
    }

    func secret(for account: SecretAccount) -> String? { stored.withLock { $0[account] } }
    func setSecret(_ secret: String, for account: SecretAccount) throws { stored.withLock { $0[account] = secret } }
    func deleteSecret(for account: SecretAccount) throws { stored.withLock { $0[account] = nil } }
}

/// Settings backed by a throwaway `UserDefaults` suite.
@MainActor
struct TemporarySettings {
    let settings: AppSettings
    private let suite: String
    private let defaults: UserDefaults

    init() throws {
        suite = "AERESBarUITests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.featureUnsupported) }
        self.defaults = defaults
        settings = AppSettings(defaults: defaults)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
    }
}
