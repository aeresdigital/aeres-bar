import AERESBarCore
import AppKit
import Observation

/// Wires the store, the settings, the menu bar and the system events together.
@MainActor
public final class AppCoordinator {
    private let store: UsageStore
    private let settings: AppSettings
    private let statusBar: StatusBarController
    private let events = SystemEventsMonitor()
    private var antigravityFollowUp: Task<Void, Never>?

    public init(store: UsageStore, settings: AppSettings, secrets: any SecretStore) {
        self.store = store
        self.settings = settings
        self.statusBar = StatusBarController(
            store: store,
            settings: settings,
            settingsMenu: SettingsMenu(store: store, settings: settings, secrets: secrets)
        )
    }

    public func start() {
        store.enabledProviders = Set(settings.enabledProviders)
        statusBar.install()
        store.startAutoRefresh(every: settings.refreshInterval)
        followRefreshInterval()
        followEnabledProviders()
        events.start(
            onWake: { [weak self] in self?.store.refreshAll() },
            onAntigravityLaunchOrQuit: { [weak self] in self?.refreshAntigravitySoon() }
        )
        LoginItem.enableOnFirstLaunch()
        Log.app.notice("\(AppInfo.name, privacy: .public) \(AppInfo.version, privacy: .public) iniciado")
    }

    /// Restarts the refresh loop whenever the interval setting changes.
    private func followRefreshInterval() {
        withObservationTracking {
            _ = settings.refreshInterval
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                store.startAutoRefresh(every: settings.refreshInterval)
                followRefreshInterval()
            }
        }
    }

    /// Keeps the store's providers in step with the menu, reading newly enabled ones right away.
    private func followEnabledProviders() {
        withObservationTracking {
            _ = settings.disabledProviders
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let enabled = Set(settings.enabledProviders)
                let added = enabled.subtracting(store.enabledProviders)
                store.enabledProviders = enabled
                for provider in added { store.requestRefresh(provider) }
                followEnabledProviders()
            }
        }
    }

    /// The language server needs a few seconds after Antigravity launches; try a few times.
    private func refreshAntigravitySoon() {
        antigravityFollowUp?.cancel()
        antigravityFollowUp = Task { [weak self] in
            for delay in [2, 8, 20] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.store.requestRefresh(.antigravity)
            }
        }
    }
}
