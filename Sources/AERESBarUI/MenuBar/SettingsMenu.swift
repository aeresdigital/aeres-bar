import AERESBarCore
import AppKit

/// The right-click / gear menu with every preference, and the app's updates.
@MainActor
final class SettingsMenu: NSObject {
    private let store: UsageStore
    private let settings: AppSettings
    private let secrets: any SecretStore
    private let updater: AppUpdater?

    init(store: UsageStore, settings: AppSettings, secrets: any SecretStore, updater: AppUpdater? = nil) {
        self.store = store
        self.settings = settings
        self.secrets = secrets
        self.updater = updater
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let updater, let title = UpdatePresentation.menuTitle(for: updater.phase) {
            let install = item(title, #selector(installUpdate))
            install.isEnabled = !updater.isBusy
            install.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(install)
            menu.addItem(.separator())
        }

        menu.addItem(item("Atualizar agora", #selector(refresh), key: "r"))
        menu.addItem(.separator())

        let providers = NSMenu()
        for provider in ProviderID.allCases {
            let entry = item(provider.displayName, #selector(toggleProvider(_:)))
            entry.representedObject = provider.rawValue
            entry.state = settings.isEnabled(provider) ? .on : .off
            entry.image = BrandImage.template(for: provider, pointSize: 14)
            providers.addItem(entry)
        }
        menu.addItem(submenu("Provedores", providers))
        menu.addItem(submenu("Chaves de API", keysMenu()))
        menu.addItem(.separator())

        let icons = NSMenu()
        for style in BarIconStyle.allCases {
            let entry = item(style.title, #selector(selectIconStyle(_:)))
            entry.representedObject = style.rawValue
            entry.state = settings.barIconStyle == style ? .on : .off
            icons.addItem(entry)
        }
        menu.addItem(submenu("Ícone na barra", icons))

        let metrics = NSMenu()
        for metric in BarMetric.allCases {
            let entry = item(metric.title, #selector(selectMetric(_:)))
            entry.representedObject = metric.rawValue
            entry.state = settings.barMetric == metric ? .on : .off
            metrics.addItem(entry)
        }
        menu.addItem(submenu("Número na barra", metrics))
        menu.addItem(toggle("Mostrar o número ao lado do ícone", settings.showPercentInBar, #selector(togglePercent)))
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
        menu.addItem(checkForUpdatesItem())
        menu.addItem(item("Sair do \(AppInfo.name)", #selector(quit), key: "q"))
        return menu
    }

    private func checkForUpdatesItem() -> NSMenuItem {
        let entry = item(updater?.phase == .checking ? "Procurando atualizações…" : "Procurar atualizações…", #selector(checkForUpdates))
        entry.isEnabled = updater?.isEnabled == true && updater?.isBusy == false
        if updater?.isEnabled != true { entry.toolTip = "Só no app instalado" }
        return entry
    }

    /// One submenu per key: its state, set, remove and where to create one.
    private func keysMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for account in SecretAccount.allCases {
            let hasKey = secrets.secret(for: account) != nil
            let options = NSMenu()
            options.autoenablesItems = false
            let status = NSMenuItem(title: hasKey ? "Chave guardada no Chaves" : "Nenhuma chave definida", action: nil, keyEquivalent: "")
            status.isEnabled = false
            options.addItem(status)
            options.addItem(.separator())
            let set = item(hasKey ? "Trocar a chave…" : "Definir a chave…", #selector(setKey(_:)))
            set.representedObject = account.rawValue
            options.addItem(set)
            let remove = item("Remover a chave", #selector(removeKey(_:)))
            remove.representedObject = account.rawValue
            remove.isEnabled = hasKey
            options.addItem(remove)
            let site = item("Criar uma chave no site…", #selector(openKeysPage(_:)))
            site.representedObject = account.rawValue
            options.addItem(site)

            let entry = submenu(account.displayName, options)
            entry.state = hasKey ? .on : .off
            entry.image = BrandImage.template(for: account.provider, pointSize: 14)
            menu.addItem(entry)
        }
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

    @objc private func refresh() { store.refreshAll(reason: .manual) }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = ProviderID(rawValue: raw) else { return }
        settings.setEnabled(provider, !settings.isEnabled(provider))
    }

    @objc private func selectIconStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = BarIconStyle(rawValue: raw) else { return }
        settings.barIconStyle = style
    }

    @objc private func selectMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let metric = BarMetric(rawValue: raw) else { return }
        settings.barMetric = metric
    }

    @objc private func togglePercent() { settings.showPercentInBar.toggle() }
    @objc private func toggleRemaining() { settings.showRemaining.toggle() }
    @objc private func toggleCountdown() { settings.showCountdown.toggle() }
    @objc private func toggleAlerts() { settings.colorAlerts.toggle() }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        settings.refreshInterval = seconds
    }

    @objc private func setKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let account = SecretAccount(rawValue: raw),
            let key = APIKeyPrompt.ask(for: account)
        else { return }
        do {
            try secrets.setSecret(key, for: account)
            settings.setEnabled(account.provider, true)
            store.requestRefresh(account.provider, reason: .manual)
        } catch SecretStoreError.invalidFormat {
            APIKeyPrompt.showError("Essa chave não parece válida: cole a chave inteira, sem espaços nem aspas.")
        } catch {
            APIKeyPrompt.showError("Não foi possível guardar a chave no Chaves do macOS.")
        }
    }

    @objc private func removeKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let account = SecretAccount(rawValue: raw) else { return }
        do {
            try secrets.deleteSecret(for: account)
            store.requestRefresh(account.provider, reason: .manual)
        } catch {
            APIKeyPrompt.showError("Não foi possível remover a chave do Chaves do macOS.")
        }
    }

    @objc private func openKeysPage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let url = SecretAccount(rawValue: raw)?.keysPage else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLogin() {
        if LoginItem.needsApproval {
            LoginItem.openSystemSettings()
            return
        }
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            APIKeyPrompt.showError(
                "Não foi possível alterar a abertura automática. Mova o \(AppInfo.name) para a pasta Aplicativos e tente de novo."
            )
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func installUpdate() {
        guard let updater, let manifest = updater.pendingUpdate else { return }
        guard UpdatePrompt.confirm(UpdatePresentation.confirmation(for: manifest, currentVersion: updater.currentVersion)) else {
            updater.dismiss()
            return
        }
        install(with: updater)
    }

    @objc private func checkForUpdates() {
        guard let updater else { return }
        Task { @MainActor [weak self] in
            let result = await updater.check(userInitiated: true)
            let message = UpdatePresentation.checkMessage(for: result, currentVersion: updater.currentVersion)
            guard case .available = result else {
                let isProblem = if case .failed = result { true } else { false }
                UpdatePrompt.inform(message, isProblem: isProblem)
                return
            }
            if UpdatePrompt.confirm(message) {
                self?.install(with: updater)
            } else {
                updater.dismiss()
            }
        }
    }

    /// Installs and, since the menu is gone by then, reports a failure in a dialog. On success the
    /// app quits and the new version opens.
    private func install(with updater: AppUpdater) {
        guard let task = updater.install() else { return }
        Task { @MainActor in
            await task.value
            if case .failed(let failure, _) = updater.phase { UpdatePrompt.showFailure(failure) }
        }
    }
}
