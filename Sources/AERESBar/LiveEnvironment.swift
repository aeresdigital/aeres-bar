import AERESBarCore
import AppKit

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

    /// The published feed (or the one set for testing), read with timeouts that suit a download.
    static let updateFeed: UpdateFeed = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return UpdateFeed(
            manifestURL: UpdateFeed.configuredManifestURL(defaults: .standard),
            http: URLSessionHTTPClient(session: URLSession(configuration: configuration))
        )
    }()

    static func makeUpdater() -> AppUpdater {
        let bundle = Bundle.main
        let build = Int(AppInfo.build) ?? 0
        return AppUpdater(
            source: updateFeed,
            installer: BundleUpdateInstaller(bundleURL: bundle.bundleURL, currentBuild: build),
            currentVersion: AppInfo.version,
            currentBuild: build,
            // `swift run` has no app to replace.
            isEnabled: bundle.bundleURL.pathExtension == "app" && bundle.bundleIdentifier == AppInfo.bundleIdentifier && build > 0,
            quit: quitForUpdate
        )
    }

    /// Quits so the helper can swap the apps. Should something keep the app from quitting (a modal
    /// dialog, say), it exits on its own after a few seconds, since the helper is already waiting.
    private static func quitForUpdate() {
        NSApp.terminate(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            exit(0)
        }
    }
}
