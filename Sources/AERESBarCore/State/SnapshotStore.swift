import Foundation

/// Persists the last snapshots, so numbers show up right after launch and stay visible
/// while a source is unreachable.
public protocol SnapshotPersisting: Sendable {
    func load() -> [ProviderID: ProviderSnapshot]
    func save(_ snapshots: [ProviderID: ProviderSnapshot])
}

/// Stores snapshots as JSON in Application Support.
public struct FileSnapshotStore: SnapshotPersisting {
    private let fileURL: URL

    public init(fileURL: URL = DataLocations.snapshotCacheFile) {
        self.fileURL = fileURL
    }

    /// Restored snapshots are marked stale: they have not been confirmed by this run yet.
    public func load() -> [ProviderID: ProviderSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let stored = try? decoder.decode([String: ProviderSnapshot].self, from: data) else { return [:] }
        var result: [ProviderID: ProviderSnapshot] = [:]
        for (key, snapshot) in stored {
            guard let provider = ProviderID(rawValue: key) else { continue }
            var restored = snapshot
            if restored.status == .ok { restored.status = .stale }
            result[provider] = restored
        }
        return result
    }

    public func save(_ snapshots: [ProviderID: ProviderSnapshot]) {
        var stored: [String: ProviderSnapshot] = [:]
        for (provider, snapshot) in snapshots { stored[provider.rawValue] = snapshot }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(stored) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Não foi possível salvar o cache: \(error.localizedDescription, privacy: .public)")
        }
    }
}
