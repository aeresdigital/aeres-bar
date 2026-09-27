import Foundation

extension KeyedService {
    /// DeepSeek: the prepaid balance (DeepSeek has no usage or limits API).
    public static func deepSeek(
        claudeSettings: [URL] = DataLocations.claudeSettingsFiles,
        codexConfig: URL = DataLocations.codexHome.appendingPathComponent("config.toml")
    ) -> KeyedService {
        KeyedService(
            provider: .deepseek,
            account: .deepseek,
            name: "DeepSeek",
            source: "API do DeepSeek",
            regions: [Region("global", "https://api.deepseek.com")],
            request: { base, key in get(base.appendingPathComponent("user/balance"), key: key) },
            read: { answer, _ in DeepSeekParser.reading(from: answer.main) },
            localCredential: { _ in DeepSeekCredentials.find(claudeSettings: claudeSettings, codexConfig: codexConfig) }
        )
    }
}
