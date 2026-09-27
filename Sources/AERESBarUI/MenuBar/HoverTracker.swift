import AppKit

/// Receives mouse enter/exit events for the menu bar button (tracking-area owner).
@MainActor
final class HoverTracker: NSResponder {
    private let handler: (Bool) -> Void

    init(handler: @escaping (Bool) -> Void) {
        self.handler = handler
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseEntered(with event: NSEvent) {
        handler(true)
    }

    override func mouseExited(with event: NSEvent) {
        handler(false)
    }
}
