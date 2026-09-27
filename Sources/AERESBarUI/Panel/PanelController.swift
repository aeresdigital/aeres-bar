import AERESBarCore
import AppKit
import SwiftUI

/// Which provider the panel shows and whether it was pinned by a click.
@MainActor
@Observable
final class PanelState {
    var selected: ProviderID = .claude
    var pinned = false
}

/// Actions the panel's buttons trigger.
struct PanelActions {
    var refresh: @MainActor () -> Void = {}
    var openMenu: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

/// Shows the details panel under a menu bar item. On hover it follows the pointer and closes
/// when the pointer leaves; on click it stays until a click elsewhere or Esc.
@MainActor
final class PanelController {
    let state = PanelState()

    private static let showDelay: Duration = .milliseconds(150)
    private static let hideDelay: TimeInterval = 0.35
    private static let gap: CGFloat = 6

    private let store: UsageStore
    private let makeMenu: () -> NSMenu
    private let isStatusItemWindow: (NSWindow?) -> Bool
    private let panel = FloatingPanel()
    private var hostingView: PanelHostingView<PanelRootView>?
    private weak var anchor: NSStatusBarButton?
    private var showTask: Task<Void, Never>?
    private var pointerWatch: Task<Void, Never>?
    private var outsideSince: Date?
    private var monitors: [Any] = []
    private(set) var isVisible = false

    init(
        store: UsageStore,
        settings: AppSettings,
        makeMenu: @escaping () -> NSMenu,
        isStatusItemWindow: @escaping (NSWindow?) -> Bool
    ) {
        self.store = store
        self.makeMenu = makeMenu
        self.isStatusItemWindow = isStatusItemWindow

        var actions = PanelActions()
        actions.refresh = { [weak store] in store?.refreshAll() }
        actions.openMenu = { [weak self] in self?.showSettingsMenu() }
        actions.quit = { NSApp.terminate(nil) }
        let hosting = PanelHostingView(rootView: PanelRootView(store: store, settings: settings, state: state, actions: actions))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.frame = NSRect(x: 0, y: 0, width: PanelRootView.width, height: 320)
        hosting.onIntrinsicSizeChange = { [weak self] in
            // Read the new size once SwiftUI has finished this update.
            Task { @MainActor in self?.fitToContent() }
        }
        panel.contentView = FloatingPanel.background(wrapping: hosting)
        hostingView = hosting
    }

    // MARK: Triggers

    func hoverBegan(_ provider: ProviderID, anchor: NSStatusBarButton) {
        if isVisible {
            // Slide across the items like a menu.
            state.selected = provider
            self.anchor = anchor
            outsideSince = nil
            fitToContent()
            store.refreshIfStale(provider)
            return
        }
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            guard !Task.isCancelled else { return }
            self?.show(provider, anchor: anchor, pinned: false)
        }
    }

    func hoverEnded() {
        showTask?.cancel()
        showTask = nil
        // Hiding is left to the pointer watch, so the pointer can travel into the panel.
    }

    func clicked(_ provider: ProviderID, anchor: NSStatusBarButton) {
        showTask?.cancel()
        if isVisible && state.pinned && state.selected == provider {
            hide()
        } else {
            show(provider, anchor: anchor, pinned: true)
        }
    }

    // MARK: Showing and hiding

    func show(_ provider: ProviderID, anchor: NSStatusBarButton, pinned: Bool) {
        showTask?.cancel()
        state.selected = provider
        state.pinned = pinned
        self.anchor = anchor
        outsideSince = nil
        fitToContent()

        if !isVisible {
            isVisible = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            startPointerWatch()
        }
        if pinned {
            installClickMonitors()
            panel.makeKey()
        }
        store.refreshIfStale(provider)
    }

    func hide() {
        showTask?.cancel()
        guard isVisible else { return }
        isVisible = false
        state.pinned = false
        pointerWatch?.cancel()
        removeClickMonitors()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func showSettingsMenu() {
        // Keep the panel around while the menu is open.
        state.pinned = true
        installClickMonitors()
        makeMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Layout

    private func fitToContent() {
        guard let hostingView else { return }
        let height = hostingView.intrinsicContentSize.height
        guard height > 1 else { return }
        let frame = frame(for: NSSize(width: PanelRootView.width, height: height.rounded(.up)))
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: false)
        panel.invalidateShadow()
    }

    private func frame(for size: NSSize) -> NSRect {
        guard let anchorRect = anchorScreenRect(), let screen = anchor?.window?.screen ?? NSScreen.main else {
            return NSRect(origin: panel.frame.origin, size: size)
        }
        let visible = screen.visibleFrame
        let top = min(anchorRect.minY, visible.maxY) - Self.gap
        let height = min(size.height, top - visible.minY - 8)
        let x = min(max(anchorRect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        return NSRect(x: x.rounded(), y: (top - height).rounded(), width: size.width, height: height.rounded())
    }

    private func anchorScreenRect() -> NSRect? {
        guard let anchor, let window = anchor.window else { return nil }
        return window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    }

    // MARK: Pointer tracking

    private func startPointerWatch() {
        pointerWatch?.cancel()
        pointerWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.checkPointer()
            }
        }
    }

    private func checkPointer() {
        guard isVisible, !state.pinned else {
            outsideSince = nil
            return
        }
        if isPointerInside(NSEvent.mouseLocation) {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) > Self.hideDelay { hide() }
        } else {
            outsideSince = Date()
        }
    }

    private func isPointerInside(_ point: NSPoint) -> Bool {
        if panel.frame.insetBy(dx: -4, dy: -4).contains(point) { return true }
        guard let anchorRect = anchorScreenRect() else { return false }
        if anchorRect.insetBy(dx: -2, dy: -3).contains(point) { return true }
        // The strip between the menu bar item and the top of the panel.
        let gap = NSRect(
            x: anchorRect.minX,
            y: panel.frame.maxY - 2,
            width: anchorRect.width,
            height: max(0, anchorRect.minY - panel.frame.maxY + 4)
        )
        return gap.contains(point)
    }

    // MARK: Click-away

    private func installClickMonitors() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }
        ) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { [weak self] event in
                // Local monitors run on the main thread, synchronously with event dispatch.
                let swallow = MainActor.assumeIsolated { self?.shouldSwallow(event) ?? false }
                return swallow ? nil : event
            }
        ) {
            monitors.append(local)
        }
    }

    private func removeClickMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Closes the panel on Esc (swallowing the key) or on a click outside it and our menu bar items.
    private func shouldSwallow(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return false }  // Esc
            hide()
            return true
        }
        // Clicks on our own menu bar items are handled by their action (toggle or switch).
        if event.window !== panel && !isStatusItemWindow(event.window) { hide() }
        return false
    }
}
