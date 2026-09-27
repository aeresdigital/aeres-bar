/// The services whose usage AERES Bar tracks, in display order.
public enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity
    case copilot
    case ollama
    case openrouter

    public var id: String { rawValue }

    /// Product name, as shown in the panel.
    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .copilot: "GitHub Copilot"
        case .ollama: "Ollama"
        case .openrouter: "OpenRouter"
        }
    }

    /// Compact name for menus and accessibility.
    public var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .copilot: "Copilot"
        case .ollama: "Ollama"
        case .openrouter: "OpenRouter"
        }
    }
}

/// Why a refresh happens. A manual refresh skips the reuse of recent API responses.
public enum RefreshReason: Sendable {
    case automatic
    case manual
}
