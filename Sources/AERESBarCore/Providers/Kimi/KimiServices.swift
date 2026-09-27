import Foundation

extension KeyedService {
    /// Kimi Code: the coding subscription's 5-hour, weekly and monthly quotas, with a key from the
    /// Kimi Code console, Claude Code set up for Kimi, or the Kimi Code CLI's own login.
    public static func kimiCode(
        homes: [URL] = DataLocations.kimiCodeHomes,
        claudeSettings: [URL] = DataLocations.claudeSettingsFiles
    ) -> KeyedService {
        KeyedService(
            provider: .kimi,
            account: .kimiCode,
            name: "Kimi Code",
            source: "API do Kimi Code",
            regions: [Region("global", "https://api.kimi.ai/coding/v1"), Region("china", "https://api.kimi.com/coding/v1")],
            request: { base, key in get(base.appendingPathComponent("usages"), key: key) },
            extras: { base, key in [get(base.appendingPathComponent("me"), key: key)] },
            read: { answer, _ in
                guard let windows = KimiCodeParser.windows(from: answer.main) else { return nil }
                let plan = answer.extras.first.flatMap { $0 }.flatMap(KimiCodeParser.planName)
                return KeyedReading(plan: plan, windows: windows, details: KimiCodeParser.details(from: answer.main))
            },
            localCredential: { now in
                if let token = ClaudeCodeSettings.token(forHosts: ["api.kimi.ai", "api.kimi.com"], in: claudeSettings) {
                    return .token(token)
                }
                return KimiCodeCredentials.find(in: homes, now: now)
            }
        )
    }

    /// Kimi API (Moonshot's open platform, now platform.kimi.ai): the account balance, in dollars
    /// internationally and in yuan in mainland China.
    public static func kimiAPI(claudeSettings: [URL] = DataLocations.claudeSettingsFiles) -> KeyedService {
        KeyedService(
            provider: .moonshot,
            account: .moonshot,
            name: "Kimi API",
            subject: "a plataforma Kimi",
            source: "API da plataforma Kimi",
            regions: [Region("global", "https://api.moonshot.ai/v1"), Region("china", "https://api.moonshot.cn/v1")],
            request: { base, key in get(base.appendingPathComponent("users/me/balance"), key: key) },
            read: { answer, _ in MoonshotBalanceParser.reading(from: answer.main, currency: answer.region.name == "china" ? "CNY" : "USD")
            },
            localCredential: { _ in
                ClaudeCodeSettings.token(forHosts: ["api.moonshot.ai", "api.moonshot.cn"], in: claudeSettings).map { .token($0) }
            }
        )
    }
}
