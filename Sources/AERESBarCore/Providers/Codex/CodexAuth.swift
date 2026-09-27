import Foundation

/// The ChatGPT sign-in Codex stores in `~/.codex/auth.json` (written by `codex login`).
struct CodexAuth: Equatable {
    var accessToken: String
    var accountID: String?
    var expiresAt: Date?

    static func load(home: URL) -> CodexAuth? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> CodexAuth? {
        guard let root = JSON.object(data),
            let tokens = JSON.dict(root["tokens"]),
            let access = JSON.string(tokens["access_token"])
        else { return nil }
        return CodexAuth(accessToken: access, accountID: JSON.string(tokens["account_id"]), expiresAt: JWT.expiry(access))
    }
}
