import AERESBarCore
import AppKit

/// The right-click / gear menu with every preference.
@MainActor
final class SettingsMenu: NSObject {
    private let store: UsageStore
    private let settings: AppSettings

    init(store: UsageStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item("Atualizar agora", #selector(refresh), key: "r"))
        menu.addItem(.separator())

        let providers = NSMenu()
        for provider in ProviderID.allCases {
            let entry = item(provider.displayName, #selector(toggleProvider(_:)))
            entry.representedObject = provider.rawValue
            entry.state = settings.isVisible(provider) ? .on : .off
            entry.image = BrandImage.template(for: provider, pointSize: 14)
            providers.addItem(entry)
        }
        menu.addItem(submenu("Mostrar na barra", providers))

        let metrics = NSMenu()
        for metric in BarMetric.allCases {
            let entry = item(metric.title, #selector(selectMetric(_:)))
            entry.representedObject = metric.rawValue
            entry.state = settings.barMetric == metric ? .on : .off
            metrics.addItem(entry)
        }
        menu.addItem(submenu("Número na barra", metrics))

        menu.addItem(toggle("Mostrar % restante (em vez de usado)", settings.showRemaining, #selector(toggleRemaining)))
        menu.addItem(toggle("Mostrar tempo até renovar", settings.showCountdown, #selector(toggleCountdown)))
        menu.addItem(toggle("Cores de alerta (80% e 95%)", settings.colorAlerts, #selector(toggleAlerts)))

        let intervals = NSMenu()
        for seconds in AppSettings.refreshIntervals {
            let minutes = Int(seconds / 60)
            let entry = item(minutes == 1 ? "1 minuto" : "\(minutes) minutos", #selector(selectInterval(_:)))
            entry.representedObject = seconds
            entry.state = abs(settings.refreshInterval - seconds) < 1 ? .on : .off
            intervals.addItem(entry)
        }
        menu.addItem(submenu("Atualizar a cada", intervals))

        menu.addItem(.separator())
        let login = toggle("Abrir ao iniciar o macOS", LoginItem.isEnabled, #selector(toggleLogin))
        if LoginItem.needsApproval { login.title += " (aprovar em Ajustes)" }
        menu.addItem(login)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(item("Sair do \(AppInfo.name)", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func toggle(_ title: String, _ isOn: Bool, _ action: Selector) -> NSMenuItem {
        let entry = item(title, action)
        entry.state = isOn ? .on : .off
        return entry
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }

    @objc private func refresh() { store.refreshAll() }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = ProviderID(rawValue: raw) else { return }
        settings.setVisible(provider, !settings.isVisible(provider))
    }

    @objc private func selectMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let metric = BarMetric(rawValue: raw) else { return }
        settings.barMetric = metric
    }

    @objc private func toggleRemaining() { settings.showRemaining.toggle() }
    @objc private func toggleCountdown() { settings.showCountdown.toggle() }
    @objc private func toggleAlerts() { settings.colorAlerts.toggle() }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        settings.refreshInterval = seconds
    }

    @objc private func toggleLogin() {
        if LoginItem.needsApproval {
            LoginItem.openSystemSettings()
            return
        }
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Não foi possível alterar a abertura automática"
            alert.informativeText = "Mova o \(AppInfo.name) para a pasta Aplicativos e tente de novo.\n\n\(error.localizedDescription)"
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
