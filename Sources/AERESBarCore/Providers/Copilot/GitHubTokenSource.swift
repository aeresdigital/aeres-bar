import Foundation

/// Supplies a GitHub token for the Copilot usage API.
public protocol GitHubTokenSource: Sendable {
    func token() -> String?
}

/// Reuses a GitHub login already on this Mac, in order:
/// 1. `gh auth token` (GitHub CLI, including logins kept in the Keychain);
/// 2. `oauth_token` in the CLI's `hosts.yml`;
/// 3. the token saved by Copilot plugins (Vim, Neovim, JetBrains, Xcode) in `~/.config/github-copilot`;
/// 4. `GH_TOKEN` / `GITHUB_TOKEN`.
public struct LocalGitHubTokenSource: GitHubTokenSource {
    private let runner: any CommandRunner
    private let cliCandidates: [String]
    private let hostsFile: URL
    private let copilotFiles: [URL]
    private let environment: [String: String]

    public init(
        runner: any CommandRunner = ProcessCommandRunner(),
        cliCandidates: [String] = DataLocations.githubCLICandidates,
        hostsFile: URL = DataLocations.githubCLIHostsFile,
        copilotFiles: [URL] = DataLocations.copilotTokenFiles,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.runner = runner
        self.cliCandidates = cliCandidates
        self.hostsFile = hostsFile
        self.copilotFiles = copilotFiles
        self.environment = environment
    }

    public func token() -> String? {
        for cli in cliCandidates where FileManager.default.isExecutableFile(atPath: cli) {
            if let token = runner.run(cli, ["auth", "token", "--hostname", "github.com"], timeout: 8)?.trimmedOutput {
                return token
            }
        }
        if let text = try? String(contentsOf: hostsFile, encoding: .utf8), let token = Self.hostsToken(in: text) {
            return token
        }
        for file in copilotFiles {
            if let data = try? Data(contentsOf: file), let token = Self.copilotToken(in: data) { return token }
        }
        return ["GH_TOKEN", "GITHUB_TOKEN"].lazy.compactMap { environment[$0] }.first { !$0.isEmpty }
    }

    /// `oauth_token` of the `github.com` host in the GitHub CLI's `hosts.yml`. The host's own
    /// token (the active account) wins over the per-account ones nested under `users:`.
    static func hostsToken(in yaml: String) -> String? {
        var inGitHub = false
        var best: (indent: Int, token: String)?
        for line in yaml.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            if indent == 0 {
                inGitHub = trimmed == "github.com:"
                continue
            }
            guard inGitHub, trimmed.hasPrefix("oauth_token:") else { continue }
            let value = trimmed.dropFirst("oauth_token:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if !value.isEmpty, indent < best?.indent ?? .max { best = (indent, value) }
        }
        return best?.token
    }

    /// First `oauth_token` for github.com in `apps.json` / `hosts.json`.
    static func copilotToken(in data: Data) -> String? {
        guard let root = JSON.object(data) else { return nil }
        for key in root.keys.sorted() where key.hasPrefix("github.com") {
            if let token = JSON.string(JSON.dict(root[key])?["oauth_token"]) { return token }
        }
        return nil
    }
}
