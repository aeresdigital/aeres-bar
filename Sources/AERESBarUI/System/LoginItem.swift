import AERESBarCore
import Foundation
import ServiceManagement

/// "Open at login", through `SMAppService`.
public enum LoginItem {
    private static let configuredKey = "loginItemConfigured"

    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "ativado"
        case .requiresApproval: "aguardando aprovação em Ajustes do Sistema"
        case .notRegistered: "desativado"
        case .notFound: "indisponível (o app precisa estar em /Applications)"
        @unknown default: "desconhecido"
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Turns "open at login" on the first time the installed app runs; the user can turn it off in the menu.
    @MainActor
    public static func enableOnFirstLaunch(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: configuredKey), Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        defaults.set(true, forKey: configuredKey)
        do {
            try SMAppService.mainApp.register()
        } catch {
            Log.app.error("Falha ao registrar abertura no login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
