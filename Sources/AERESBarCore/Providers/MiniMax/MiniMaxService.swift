import Foundation

extension KeyedService {
    /// MiniMax Token Plan (formerly Coding Plan): the 5-hour and weekly windows of the text models.
    public static func minimax(
        claudeSettings: [URL] = DataLocations.claudeSettingsFiles,
        cliConfig: URL = DataLocations.minimaxCLIConfig
    ) -> KeyedService {
        KeyedService(
            provider: .minimax,
            account: .minimax,
            name: "MiniMax",
            source: "API do MiniMax Token Plan",
            regions: [Region("global", "https://api.minimax.io"), Region("china", "https://api.minimaxi.com")],
            request: { base, key in get(base.appendingPathComponent("v1/token_plan/remains"), key: key) },
            read: { answer, _ in MiniMaxParser.reading(from: answer.main) },
            errorInBody: MiniMaxParser.bodyIssue,
            localCredential: { now in MiniMaxCredentials.find(claudeSettings: claudeSettings, cliConfig: cliConfig, now: now) }
        )
    }
}
