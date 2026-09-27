import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
public final class AppSettings {
    /// Refresh intervals offered in the menu, in seconds.
    public static let refreshIntervals: [TimeInterval] = [60, 120, 300, 600]

    enum Key {
        static let hiddenProviders = "hiddenProviders"
        static let barMetric = "barMetric"
        static let showRemaining = "showRemaining"
        static let showCountdown = "showCountdown"
        static let colorAlerts = "colorAlerts"
        static let refreshInterval = "refreshInterval"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Providers the user removed from the menu bar.
    public private(set) var hiddenProviders: Set<ProviderID> {
        didSet { defaults.set(hiddenProviders.map(\.rawValue).sorted(), forKey: Key.hiddenProviders) }
    }

    public var barMetric: BarMetric {
        didSet { defaults.set(barMetric.rawValue, forKey: Key.barMetric) }
    }

    /// Show the percentage left instead of the percentage used.
    public var showRemaining: Bool {
        didSet { defaults.set(showRemaining, forKey: Key.showRemaining) }
    }

    /// Append the time until renewal to the menu bar number.
    public var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: Key.showCountdown) }
    }

    /// Tint the menu bar number orange at 80% and red at 95%.
    public var colorAlerts: Bool {
        didSet { defaults.set(colorAlerts, forKey: Key.colorAlerts) }
    }

    /// Seconds between automatic refreshes.
    public var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.barMetric: BarMetric.mostCritical.rawValue,
            Key.showRemaining: false,
            Key.showCountdown: false,
            Key.colorAlerts: true,
            Key.refreshInterval: 120.0,
        ])
        hiddenProviders = Set((defaults.stringArray(forKey: Key.hiddenProviders) ?? []).compactMap(ProviderID.init(rawValue:)))
        barMetric = BarMetric(rawValue: defaults.string(forKey: Key.barMetric) ?? "") ?? .mostCritical
        showRemaining = defaults.bool(forKey: Key.showRemaining)
        showCountdown = defaults.bool(forKey: Key.showCountdown)
        colorAlerts = defaults.bool(forKey: Key.colorAlerts)
        refreshInterval = max(30, defaults.double(forKey: Key.refreshInterval))
    }

    public var barConfig: BarPresenter.Config {
        BarPresenter.Config(metric: barMetric, showRemaining: showRemaining, showCountdown: showCountdown)
    }

    public func isVisible(_ provider: ProviderID) -> Bool {
        !hiddenProviders.contains(provider)
    }

    /// Shows or hides a provider. The last visible one cannot be hidden:
    /// without any menu bar item the app would be unreachable.
    public func setVisible(_ provider: ProviderID, _ visible: Bool) {
        if visible {
            hiddenProviders.remove(provider)
        } else if ProviderID.allCases.contains(where: { $0 != provider && isVisible($0) }) {
            hiddenProviders.insert(provider)
        }
    }
}
