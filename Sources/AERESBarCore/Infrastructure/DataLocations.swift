import Foundation

/// Where each tool keeps its data on disk, and where AERES Bar keeps its own.
public enum DataLocations {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Claude Code transcripts. `CLAUDE_CONFIG_DIR` is honoured when set.
    public static var claudeProjectRoots: [URL] {
        var roots = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            roots.insert(URL(fileURLWithPath: custom).appendingPathComponent("projects"), at: 0)
        }
        return roots
    }

    /// Claude Code's user settings, where third-party coding plans set `ANTHROPIC_BASE_URL`.
    public static var claudeSettingsFiles: [URL] {
        var files = [home.appendingPathComponent(".claude/settings.json")]
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            files.insert(URL(fileURLWithPath: custom).appendingPathComponent("settings.json"), at: 0)
        }
        return files
    }

    /// Kimi Code CLI homes: the current CLI (`KIMI_CODE_HOME`, `~/.kimi-code`) and the legacy one
    /// (`KIMI_SHARE_DIR`, `~/.kimi`).
    public static var kimiCodeHomes: [URL] {
        var homes: [URL] = []
        if let custom = environment["KIMI_CODE_HOME"], !custom.isEmpty { homes.append(URL(fileURLWithPath: custom)) }
        homes.append(home.appendingPathComponent(".kimi-code"))
        if let legacy = environment["KIMI_SHARE_DIR"], !legacy.isEmpty { homes.append(URL(fileURLWithPath: legacy)) }
        homes.append(home.appendingPathComponent(".kimi"))
        return homes
    }

    /// Where vendor CLIs installed with npm, Homebrew and friends end up (a GUI app has no shell
    /// `PATH`), newest Node version first for nvm.
    public static var cliSearchDirectories: [URL] {
        var directories = ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(fileURLWithPath: $0) }
        for relative in [".local/bin", ".npm-global/bin", ".volta/bin", ".bun/bin", "Library/pnpm", ".asdf/shims", ".bailian/bin"] {
            directories.append(home.appendingPathComponent(relative))
        }
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? []
        for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
            directories.append(nvm.appendingPathComponent(version).appendingPathComponent("bin"))
        }
        return directories
    }

    /// The official MiniMax CLI's configuration (`MMX_CONFIG_DIR` is honoured).
    public static var minimaxCLIConfig: URL {
        let folder =
            environment["MMX_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".mmx")
        return folder.appendingPathComponent("config.json")
    }

    /// Volcengine's `arkcli` keeps its login here.
    public static var arkCLIHome: URL {
        home.appendingPathComponent(".arkcli")
    }

    /// Alibaba Model Studio's `bl` keeps its login here (`BAILIAN_CONFIG_DIR` is honoured).
    public static var bailianConfig: URL {
        if let custom = environment["BAILIAN_CONFIG_DIR"], !custom.isEmpty { return URL(fileURLWithPath: custom) }
        return home.appendingPathComponent(".bailian")
    }

    /// Z.ai's Coding Tool Helper configuration (`api_key`, `plan`).
    public static var glmHelperConfig: URL {
        home.appendingPathComponent(".chelper/config.yaml")
    }

    /// Claude Code's credentials file, used where the Keychain is unavailable.
    public static var claudeCredentialsFile: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }

    /// Codex home (`auth.json`, `sessions/`). `CODEX_HOME` is honoured when set.
    public static var codexHome: URL {
        if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return home.appendingPathComponent(".codex")
    }

    /// Places Antigravity may be installed, in order of preference.
    public static var antigravityApplications: [URL] {
        [
            URL(fileURLWithPath: "/Applications/Antigravity.app"),
            URL(fileURLWithPath: "/Applications/Antigravity IDE.app"),
            home.appendingPathComponent("Applications/Antigravity.app"),
        ]
    }

    /// Antigravity's per-user data, present once it has been used.
    public static var antigravityData: URL {
        home.appendingPathComponent(".gemini/antigravity")
    }

    /// Where the GitHub CLI may be installed (a GUI app has no shell `PATH`).
    public static var githubCLICandidates: [String] {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", home.appendingPathComponent(".local/bin/gh").path, "/usr/bin/gh"]
    }

    /// The GitHub CLI's `hosts.yml` (holds the token when gh does not use the Keychain).
    public static var githubCLIHostsFile: URL {
        if let custom = environment["GH_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom).appendingPathComponent("hosts.yml")
        }
        return home.appendingPathComponent(".config/gh/hosts.yml")
    }

    /// Tokens saved by Copilot plugins for Vim, Neovim, JetBrains and Xcode.
    public static var copilotTokenFiles: [URL] {
        let folder = home.appendingPathComponent(".config/github-copilot")
        return [folder.appendingPathComponent("apps.json"), folder.appendingPathComponent("hosts.json")]
    }

    /// Ollama's local server. `OLLAMA_HOST` is honoured when set (`host:port` or a URL).
    public static var ollamaServer: URL {
        ollamaServer(from: environment["OLLAMA_HOST"])
    }

    /// Reads `OLLAMA_HOST` with the same rules as Ollama's own client: without a scheme it is http
    /// on port 11434; with one, the scheme's usual port; an empty host means this Mac.
    static func ollamaServer(from raw: String?) -> URL {
        let value = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return defaultOllamaServer }
        let hasScheme = value.contains("://")
        guard var components = URLComponents(string: hasScheme ? value : "http://\(value)"),
            components.scheme == "http" || components.scheme == "https"
        else { return defaultOllamaServer }
        if components.host?.isEmpty ?? true { components.host = "127.0.0.1" }
        if components.port == nil { components.port = hasScheme ? (components.scheme == "https" ? 443 : 80) : 11_434 }
        return components.url ?? defaultOllamaServer
    }

    private static let defaultOllamaServer: URL = {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 11_434
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    /// Signs that Ollama is installed.
    public static var ollamaInstallations: [URL] {
        [
            URL(fileURLWithPath: "/Applications/Ollama.app"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ollama"),
            URL(fileURLWithPath: "/usr/local/bin/ollama"),
            home.appendingPathComponent(".ollama"),
        ]
    }

    /// AERES Bar's own cache of the last snapshots.
    public static var snapshotCacheFile: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AERES Bar", isDirectory: true).appendingPathComponent("snapshots.json")
    }
}
