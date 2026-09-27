import Foundation

/// A third-party key the user set Claude Code up with: `env.ANTHROPIC_AUTH_TOKEN` (or
/// `ANTHROPIC_API_KEY`) in Claude Code's settings, taken only when `env.ANTHROPIC_BASE_URL` points
/// at the provider asking. That is how the Chinese coding plans are used from Claude Code; the key
/// then only ever goes to that same provider.
public enum ClaudeCodeSettings {
    public static func token(forHosts hosts: Set<String>, in files: [URL]) -> String? {
        for file in files {
            guard let data = try? Data(contentsOf: file), let env = JSON.object(data).flatMap({ JSON.dict($0["env"]) }),
                let base = JSON.string(env["ANTHROPIC_BASE_URL"]), let host = URLComponents(string: base)?.host?.lowercased(),
                hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
            else { continue }
            if let token = JSON.string(env["ANTHROPIC_AUTH_TOKEN"]) ?? JSON.string(env["ANTHROPIC_API_KEY"]) { return token }
        }
        return nil
    }
}
