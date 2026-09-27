import AERESBarCore

/// Composition root: the real providers with their production dependencies.
@MainActor
enum LiveEnvironment {
    static func makeStore(persistent: Bool) -> UsageStore {
        UsageStore(
            providers: [ClaudeProvider(), CodexProvider(), AntigravityProvider()],
            persistence: persistent ? FileSnapshotStore() : nil
        )
    }
}
