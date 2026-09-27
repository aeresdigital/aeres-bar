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
                KeyedUsageProvider(service: .openRouter, secrets: secrets),
                KeyedUsageProvider(service: .glm(), secrets: secrets),
                KeyedUsageProvider(service: .kimiCode(), secrets: secrets),
                KeyedUsageProvider(service: .kimiAPI(), secrets: secrets),
                KeyedUsageProvider(service: .minimax(), secrets: secrets),
                KeyedUsageProvider(service: .deepSeek(), secrets: secrets),
                CommandUsageProvider(service: .qwen()),
                CommandUsageProvider(service: .doubao()),
            ],
            persistence: persistent ? FileSnapshotStore() : nil,
            enabledProviders: enabled
        )
    }
}
