import AERESBarCore

/// Composition root: the real providers with their production dependencies.
@MainActor
enum LiveEnvironment {
    static let secrets = KeychainSecretStore()

    static func makeStore(persistent: Bool, enabled: Set<ProviderID> = Set(ProviderID.allCases)) -> UsageStore {
        UsageStore(
            providers: [
                ClaudeProvider(),
                CodexProvider(),
                AntigravityProvider(),
                CopilotProvider(),
                OllamaProvider(secrets: secrets),
                OpenRouterProvider(secrets: secrets),
            ],
            persistence: persistent ? FileSnapshotStore() : nil,
            enabledProviders: enabled
        )
    }
}
