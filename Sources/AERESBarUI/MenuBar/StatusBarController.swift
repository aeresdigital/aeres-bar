import AERESBarCore
import AppKit
import Observation

/// The single menu bar item: a meter of every provider (or the most critical provider's logo)
/// and the highest usage. Hovering opens the panel with all providers; a click pins it.
@MainActor
final class StatusBarController: NSObject {
    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    private let store: UsageStore
    private let settings: AppSettings
    private let settingsMenu: SettingsMenu
    private var item: NSStatusItem?
    private var tracker: HoverTracker?
    private var clock: Task<Void, Never>?
    private lazy var panel = PanelController(
        store: store,
        settings: settings,
        makeMenu: { [unowned self] in settingsMenu.makeMenu() },
        isStatusItemWindow: { [unowned self] window in window != nil && window === item?.button?.window }
    )

    init(store: UsageStore, settings: AppSettings, settingsMenu: SettingsMenu) {
        self.store = store
        self.settings = settings
        self.settingsMenu = settingsMenu
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "AERESBar.main"
        self.item = item

        if let button = item.button {
            button.imageHugsTitle = true
            button.target = self
            button.action = #selector(itemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let tracker = HoverTracker { [weak self, weak button] inside in
                guard let self, let button else { return }
                if inside {
                    panel.hoverBegan(anchor: button)
                } else {
                    panel.hoverEnded()
                }
            }
            button.addTrackingArea(
                NSTrackingArea(
                    rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: tracker, userInfo: nil)
            )
            self.tracker = tracker
        }
        observeAndRender()

        // Countdowns and renewals move even when no new data arrives.
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.render()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.logPlacement()
        }
    }

    /// Re-renders whenever anything `render()` reads changes.
    private func observeAndRender() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAndRender() }
        }
    }

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.hide()
            guard let item else { return }
            item.menu = settingsMenu.makeMenu()
            sender.performClick(nil)
            item.menu = nil
        } else {
            panel.clicked(anchor: sender)
        }
    }

    private func render() {
        guard let button = item?.button else { return }
        let overall = BarPresenter.overall(for: store.snapshots, providers: store.providerIDs, config: settings.barConfig, now: Date())

        switch settings.barIconStyle {
        case .meters:
            button.image = MeterImage.template(levels: overall.levels.map(\.usedPercent))
        case .criticalLogo:
            button.image = BrandImage.template(for: overall.critical ?? store.providerIDs.first ?? .claude)
        }

        if settings.showPercentInBar {
            button.imagePosition = .imageLeading
            let text = " " + overall.text
            if settings.colorAlerts, let alert = overall.alert {
                button.attributedTitle = NSAttributedString(
                    string: text,
                    attributes: [.font: Self.titleFont, .foregroundColor: BrandPalette.color(for: alert)]
                )
            } else {
                button.font = Self.titleFont
                button.title = text
            }
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.appearsDisabled = !overall.hasData
        button.setAccessibilityLabel(BarPresenter.accessibilityLabel(for: overall))
    }

    /// One line in the unified log saying where the item landed, for troubleshooting.
    private func logPlacement() {
        let frame = item?.button?.window?.frame ?? .zero
        Log.statusBar.notice(
            "Item na barra: \(self.item?.isVisible == true ? "visível" : "oculto", privacy: .public) x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width))"
        )
    }
}
