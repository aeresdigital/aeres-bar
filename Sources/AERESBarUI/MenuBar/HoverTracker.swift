import AERESBarCore
import AppKit

/// Receives mouse enter/exit events for a menu bar button (tracking-area owner).
@MainActor
final class HoverTracker: NSResponder {
    private let provider: ProviderID
    private let handler: (ProviderID, Bool) -> Void

    init(provider: ProviderID, handler: @escaping (ProviderID, Bool) -> Void) {
        self.provider = provider
        self.handler = handler
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseEntered(with event: NSEvent) {
        handler(provider, true)
    }

    override func mouseExited(with event: NSEvent) {
        handler(provider, false)
    }
}
