import AERESBarCore
import AppKit
import Observation

/// One menu bar item per provider: the brand mark plus the number chosen in the settings.
@MainActor
final class StatusBarController: NSObject {
    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    private let store: UsageStore
    private let settings: AppSettings
    private let settingsMenu: SettingsMenu
    private var items: [ProviderID: NSStatusItem] = [:]
    private var trackers: [ProviderID: HoverTracker] = [:]
    private var clock: Task<Void, Never>?
    private lazy var panel = PanelController(
        store: store,
        settings: settings,
        makeMenu: { [unowned self] in settingsMenu.makeMenu() },
        isStatusItemWindow: { [unowned self] window in
            window != nil && items.values.contains { $0.button?.window === window }
        }
    )

    init(store: UsageStore, settings: AppSettings, settingsMenu: SettingsMenu) {
        self.store = store
        self.settings = settings
        self.settingsMenu = settingsMenu
        super.init()
    }

    func install() {
        // Each new status item lands left of the previous ones, so create them right-to-left.
        for provider in ProviderID.allCases.reversed() {
            makeItem(for: provider)
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

    private func makeItem(for provider: ProviderID) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "AERESBar.\(provider.rawValue)"
        items[provider] = item

        guard let button = item.button else { return }
        button.image = BrandImage.template(for: provider)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
        button.target = self
        button.action = #selector(itemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let tracker = HoverTracker(provider: provider) { [weak self, weak button] provider, inside in
            guard let self, let button else { return }
            if inside {
                panel.hoverBegan(provider, anchor: button)
            } else {
                panel.hoverEnded()
            }
        }
        button.addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: tracker, userInfo: nil)
        )
        trackers[provider] = tracker
    }

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let provider = ProviderID(rawValue: raw) else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.hide()
            guard let item = items[provider] else { return }
            item.menu = settingsMenu.makeMenu()
            sender.performClick(nil)
            item.menu = nil
        } else {
            panel.clicked(provider, anchor: sender)
        }
    }

    private func render() {
        let now = Date()
        let config = settings.barConfig
        let colorAlerts = settings.colorAlerts
        for provider in ProviderID.allCases {
            guard let item = items[provider] else { continue }
            let visible = settings.isVisible(provider)
            if item.isVisible != visible { item.isVisible = visible }
            guard visible, let button = item.button else { continue }

            let value = BarPresenter.value(for: store.snapshots[provider], config: config, now: now)
            let text = " " + value.text
            if colorAlerts, let alert = value.alert {
                button.attributedTitle = NSAttributedString(
                    string: text,
                    attributes: [.font: Self.titleFont, .foregroundColor: BrandPalette.color(for: alert)]
                )
            } else {
                button.font = Self.titleFont
                button.title = text
            }
            button.appearsDisabled = !value.hasData
            button.setAccessibilityLabel(BarPresenter.accessibilityLabel(for: provider, value: value, now: now))
        }
    }

    /// One line in the unified log saying where each item landed, for troubleshooting.
    private func logPlacement() {
        let lines = ProviderID.allCases.map { provider -> String in
            guard let item = items[provider] else { return "\(provider.rawValue)=ausente" }
            let frame = item.button?.window?.frame ?? .zero
            return
                "\(provider.rawValue)=\(item.isVisible ? "visível" : "oculto") x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width))"
        }
        Log.statusBar.notice("Itens na barra: \(lines.joined(separator: " · "), privacy: .public)")
    }
}
