import AppKit

/// Forwards the system events that should trigger a refresh: waking from sleep, and Antigravity
/// opening or closing (its quotas are only readable while it runs).
@MainActor
final class SystemEventsMonitor {
    private var observers: [any NSObjectProtocol] = []

    func start(
        onWake: @escaping @MainActor @Sendable () -> Void,
        onAntigravityLaunchOrQuit: @escaping @MainActor @Sendable () -> Void
    ) {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onWake() }
            }
        )
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { notification in
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    guard application?.bundleIdentifier?.hasPrefix("com.google.antigravity") == true else { return }
                    MainActor.assumeIsolated { onAntigravityLaunchOrQuit() }
                }
            )
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }
}
