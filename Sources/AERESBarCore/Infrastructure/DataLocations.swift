import Foundation

/// Where each tool keeps its data on disk, and where AERES Bar keeps its own.
public enum DataLocations {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Claude Code transcripts. `CLAUDE_CONFIG_DIR` is honoured when set.
    public static var claudeProjectRoots: [URL] {
        var roots = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            roots.insert(URL(fileURLWithPath: custom).appendingPathComponent("projects"), at: 0)
        }
        return roots
    }

    /// Claude Code's credentials file, used where the Keychain is unavailable.
    public static var claudeCredentialsFile: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }

    /// Codex home (`auth.json`, `sessions/`). `CODEX_HOME` is honoured when set.
    public static var codexHome: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
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

    /// AERES Bar's own cache of the last snapshots.
    public static var snapshotCacheFile: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AERES Bar", isDirectory: true).appendingPathComponent("snapshots.json")
    }
}
