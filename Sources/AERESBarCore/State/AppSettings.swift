import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
public final class AppSettings {
    /// Refresh intervals offered in the menu, in seconds.
    public static let refreshIntervals: [TimeInterval] = [60, 120, 300, 600]

    enum Key {
        static let disabledProviders = "disabledProviders"
        static let barMetric = "barMetric"
        static let barIconStyle = "barIconStyle"
        static let showPercentInBar = "showPercentInBar"
        static let showRemaining = "showRemaining"
        static let showCountdown = "showCountdown"
        static let colorAlerts = "colorAlerts"
        static let refreshInterval = "refreshInterval"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Providers the user turned off: not refreshed, not shown.
    public private(set) var disabledProviders: Set<ProviderID> {
        didSet { defaults.set(disabledProviders.map(\.rawValue).sorted(), forKey: Key.disabledProviders) }
    }

    public var barMetric: BarMetric {
        didSet { defaults.set(barMetric.rawValue, forKey: Key.barMetric) }
    }

    public var barIconStyle: BarIconStyle {
        didSet { defaults.set(barIconStyle.rawValue, forKey: Key.barIconStyle) }
    }

    /// Show the number next to the icon (off: icon only, the most compact).
    public var showPercentInBar: Bool {
        didSet { defaults.set(showPercentInBar, forKey: Key.showPercentInBar) }
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
            Key.barIconStyle: BarIconStyle.meters.rawValue,
            Key.showPercentInBar: true,
            Key.showRemaining: false,
            Key.showCountdown: false,
            Key.colorAlerts: true,
            Key.refreshInterval: 120.0,
        ])
        disabledProviders = Set((defaults.stringArray(forKey: Key.disabledProviders) ?? []).compactMap(ProviderID.init(rawValue:)))
        barMetric = BarMetric(rawValue: defaults.string(forKey: Key.barMetric) ?? "") ?? .mostCritical
        barIconStyle = BarIconStyle(rawValue: defaults.string(forKey: Key.barIconStyle) ?? "") ?? .meters
        showPercentInBar = defaults.bool(forKey: Key.showPercentInBar)
        showRemaining = defaults.bool(forKey: Key.showRemaining)
        showCountdown = defaults.bool(forKey: Key.showCountdown)
        colorAlerts = defaults.bool(forKey: Key.colorAlerts)
        refreshInterval = max(30, defaults.double(forKey: Key.refreshInterval))
    }

    public var barConfig: BarPresenter.Config {
        BarPresenter.Config(metric: barMetric, showRemaining: showRemaining, showCountdown: showCountdown)
    }

    /// Enabled providers, in display order.
    public var enabledProviders: [ProviderID] {
        ProviderID.allCases.filter(isEnabled)
    }

    public func isEnabled(_ provider: ProviderID) -> Bool {
        !disabledProviders.contains(provider)
    }

    /// Turns a provider on or off. The last enabled one cannot be turned off.
    public func setEnabled(_ provider: ProviderID, _ enabled: Bool) {
        if enabled {
            disabledProviders.remove(provider)
        } else if ProviderID.allCases.contains(where: { $0 != provider && isEnabled($0) }) {
            disabledProviders.insert(provider)
        }
    }
}
