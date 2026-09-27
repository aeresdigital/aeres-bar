/// The services whose usage AERES Bar tracks, in display order.
public enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity
    case copilot
    case ollama
    case openrouter
    // Chinese model platforms.
    case glm
    case kimi
    case moonshot
    case minimax
    case deepseek
    case qwen
    case doubao

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
        case .glm: "GLM (Z.ai)"
        case .kimi: "Kimi Code"
        case .moonshot: "Kimi API"
        case .minimax: "MiniMax"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen (Model Studio)"
        case .doubao: "Doubao (Volcengine)"
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
        case .glm: "GLM"
        case .kimi: "Kimi"
        case .moonshot: "Kimi API"
        case .minimax: "MiniMax"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen"
        case .doubao: "Doubao"
        }
    }
}

/// Why a refresh happens. A manual refresh skips the reuse of recent API responses.
public enum RefreshReason: Sendable {
    case automatic
    case manual
}
