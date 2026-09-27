import Foundation

extension KeyedService {
    /// GLM Coding Plan (Z.ai, and Zhipu's BigModel in mainland China): the 5-hour and weekly
    /// windows (in credits or tokens) and the monthly MCP tool quota. Takes the raw key, without
    /// "Bearer".
    public static func glm(
        claudeSettings: [URL] = DataLocations.claudeSettingsFiles,
        helperConfig: URL = DataLocations.glmHelperConfig
    ) -> KeyedService {
        KeyedService(
            provider: .glm,
            account: .glm,
            name: "GLM",
            source: "API do GLM Coding Plan",
            regions: [Region("global", "https://api.z.ai"), Region("china", "https://open.bigmodel.cn")],
            request: { base, key in
                get(
                    base.appendingPathComponent("api/monitor/usage/quota/limit"), authorization: key,
                    headers: ["Accept-Language": "en-US,en"])
            },
            read: { answer, now in GLMParser.reading(from: answer.main, now: now) },
            errorInBody: GLMParser.bodyIssue,
            localCredential: { _ in GLMCredentials.find(claudeSettings: claudeSettings, helperConfig: helperConfig) }
        )
    }
}
