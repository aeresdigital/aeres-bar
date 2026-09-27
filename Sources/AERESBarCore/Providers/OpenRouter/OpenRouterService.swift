import Foundation

extension KeyedService {
    /// OpenRouter: the API key's spending cap, free-model allowance and spend, plus the credit
    /// balance (`/credits` only answers management keys; with a regular key it is skipped).
    public static let openRouter = KeyedService(
        provider: .openrouter,
        account: .openRouter,
        name: "OpenRouter",
        source: "API do OpenRouter",
        regions: [Region("global", "https://openrouter.ai/api/v1")],
        request: { base, key in get(base.appendingPathComponent("key"), key: key, headers: ["X-Title": AppInfo.name]) },
        extras: { base, key in [get(base.appendingPathComponent("credits"), key: key, headers: ["X-Title": AppInfo.name])] },
        read: { answer, now in
            guard let info = OpenRouterParser.parseKey(answer.main) else { return nil }
            let credits = answer.extras.first.flatMap { $0 }.flatMap(OpenRouterParser.parseCredits)
            return KeyedReading(
                plan: info.isFreeTier ? "Gratuito" : nil,
                windows: OpenRouterParser.windows(for: info, now: now),
                details: OpenRouterParser.details(for: info, credits: credits)
            )
        }
    )
}
