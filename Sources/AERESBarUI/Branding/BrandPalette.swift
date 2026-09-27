import AERESBarCore
import AppKit
import SwiftUI

/// Brand colors, sampled from each vendor's official artwork.
public enum BrandPalette {
    /// Tint for progress bars and highlights.
    public static func accent(for provider: ProviderID) -> Color {
        switch provider {
        case .claude: Color(red: 0.851, green: 0.467, blue: 0.341)  // #D97757, Claude's mark
        case .codex: Color(red: 0.353, green: 0.420, blue: 0.969)  // #5A6BF7, Codex's cloud
        case .antigravity: Color(red: 0.290, green: 0.604, blue: 0.965)  // #4A9AF6, Antigravity's arch
        case .copilot: Color(red: 0.537, green: 0.341, blue: 0.898)  // #8957E5, Copilot purple
        case .ollama: Color(red: 0.455, green: 0.498, blue: 0.557)  // #747F8E, Ollama's mark is monochrome
        case .openrouter: Color(red: 0.392, green: 0.404, blue: 0.949)  // #6467F2, OpenRouter indigo
        case .glm: Color(red: 0.220, green: 0.349, blue: 1.000)  // #3859FF, Zhipu blue
        case .kimi: Color(red: 0.090, green: 0.514, blue: 1.000)  // #1783FF, Kimi's dot
        case .moonshot: Color(red: 0.059, green: 0.373, blue: 0.820)  // #0F5FD1, a deeper Kimi blue for the API
        case .minimax: Color(red: 0.906, green: 0.208, blue: 0.384)  // #E73562, MiniMax
        case .deepseek: Color(red: 0.302, green: 0.420, blue: 0.996)  // #4D6BFE, DeepSeek's whale
        case .qwen: Color(red: 0.412, green: 0.314, blue: 0.937)  // #6950EF, Qwen purple
        case .doubao: Color(red: 0.118, green: 0.216, blue: 0.988)  // #1E37FC, Doubao blue
        }
    }

    /// Fill of the colored mark in the panel.
    public static func logoFill(for provider: ProviderID) -> AnyShapeStyle {
        switch provider {
        case .claude: AnyShapeStyle(accent(for: .claude))
        case .antigravity: AnyShapeStyle(antigravityGradient)
        case .deepseek, .qwen, .minimax, .doubao: AnyShapeStyle(accent(for: provider))
        // OpenAI's, GitHub's, Ollama's, OpenRouter's, Kimi's and Z.ai's marks are monochrome.
        case .codex, .copilot, .ollama, .openrouter, .kimi, .moonshot, .glm: AnyShapeStyle(.primary)
        }
    }

    /// Antigravity's arch: warm at the top (green-yellow to coral), blue towards the feet.
    static let antigravityGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.965, green: 0.431, blue: 0.349), location: 0),  // #F66E59
            .init(color: Color(red: 0.714, green: 0.816, blue: 0.380), location: 0.22),  // #B6D061
            .init(color: Color(red: 0.337, green: 0.718, blue: 0.725), location: 0.45),  // #56B7B9
            .init(color: Color(red: 0.282, green: 0.663, blue: 0.929), location: 0.72),  // #48A9ED
            .init(color: Color(red: 0.349, green: 0.635, blue: 0.996), location: 1),  // #59A2FE
        ],
        startPoint: UnitPoint(x: 0.75, y: 0),
        endPoint: UnitPoint(x: 0.35, y: 1)
    )

    public static func color(for alert: AlertLevel) -> NSColor {
        switch alert {
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }
}
