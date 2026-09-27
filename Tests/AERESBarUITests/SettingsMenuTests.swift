import AppKit
import Testing

@testable import AERESBarCore
@testable import AERESBarUI

@Suite("Menu de ajustes")
@MainActor
struct SettingsMenuTests {
    /// Menu items target the builder weakly, so it is returned for the caller to keep alive (as the app does).
    private func makeMenu() throws -> (NSMenu, AppSettings, SettingsMenu, () -> Void) {
        let suite = "AERESBarUITests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        let builder = SettingsMenu(store: UsageStore(providers: []), settings: settings)
        return (builder.makeMenu(), settings, builder, { defaults.removePersistentDomain(forName: suite) })
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title.hasPrefix(title) }, "item \(title)")
    }

    /// Sends the item's action to its target, as AppKit does when it is chosen.
    private func perform(_ item: NSMenuItem) throws {
        let target = try #require(item.target as? NSObject, "item \(item.title) sem alvo")
        let action = try #require(item.action, "item \(item.title) sem ação")
        _ = target.perform(action, with: item)
    }

    @Test("Mostra todas as opções com o estado atual")
    func structure() throws {
        let (menu, settings, builder, cleanUp) = try makeMenu()
        defer { cleanUp() }
        withExtendedLifetime(builder) {}
        let titles = menu.items.map(\.title)
        #expect(titles.contains("Atualizar agora"))
        #expect(titles.contains("Mostrar na barra"))
        #expect(titles.contains("Número na barra"))
        #expect(titles.contains("Sair do AERES Bar"))
        let providers = try #require(try item("Mostrar na barra", in: menu).submenu)
        #expect(providers.items.map(\.title) == ProviderID.allCases.map(\.displayName))
        #expect(providers.items.allSatisfy { $0.state == .on && $0.image != nil })
        let metrics = try #require(try item("Número na barra", in: menu).submenu)
        #expect(metrics.items.filter { $0.state == .on }.map(\.title) == [settings.barMetric.title])
    }

    @Test("As ações alteram as preferências")
    func actions() throws {
        let (menu, settings, builder, cleanUp) = try makeMenu()
        defer {
            withExtendedLifetime(builder) {}
            cleanUp()
        }

        try perform(try item("Mostrar % restante", in: menu))
        #expect(settings.showRemaining)
        try perform(try item("Mostrar tempo até renovar", in: menu))
        #expect(settings.showCountdown)
        try perform(try item("Cores de alerta", in: menu))
        #expect(!settings.colorAlerts)

        let providers = try #require(try item("Mostrar na barra", in: menu).submenu)
        try perform(try #require(providers.items.first { $0.title == "Codex" }))
        #expect(!settings.isVisible(.codex))

        let metrics = try #require(try item("Número na barra", in: menu).submenu)
        try perform(try #require(metrics.items.first { $0.title == BarMetric.tokensToday.title }))
        #expect(settings.barMetric == .tokensToday)

        let intervals = try #require(try item("Atualizar a cada", in: menu).submenu)
        #expect(intervals.items.map(\.title) == ["1 minuto", "2 minutos", "5 minutos", "10 minutos"])
        try perform(try #require(intervals.items.last))
        #expect(settings.refreshInterval == 600)

        try perform(try item("Atualizar agora", in: menu))
    }
}
