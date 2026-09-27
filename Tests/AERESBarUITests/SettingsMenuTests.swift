import AppKit
import Testing

@testable import AERESBarCore
@testable import AERESBarUI

@Suite("Menu de ajustes")
@MainActor
struct SettingsMenuTests {
    /// Menu items target the builder weakly, so it is returned for the caller to keep alive (as the app does).
    private func makeMenu(secrets: MemorySecrets = MemorySecrets()) throws -> (NSMenu, AppSettings, SettingsMenu, () -> Void) {
        let temporary = try TemporarySettings()
        let builder = SettingsMenu(store: UsageStore(providers: []), settings: temporary.settings, secrets: secrets)
        return (builder.makeMenu(), temporary.settings, builder, temporary.remove)
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title.hasPrefix(title) }, "item \(title)")
    }

    private func submenu(_ title: String, in menu: NSMenu) throws -> NSMenu {
        try #require(try item(title, in: menu).submenu, "submenu \(title)")
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
        for expected in [
            "Atualizar agora", "Provedores", "Chaves de API", "Ícone na barra", "Número na barra", "Mostrar o número ao lado do ícone",
            "Atualizar a cada", "Sair do AERES Bar",
        ] {
            #expect(titles.contains(expected), "falta \(expected)")
        }

        let providers = try submenu("Provedores", in: menu)
        #expect(providers.items.map(\.title) == ProviderID.allCases.map(\.displayName))
        #expect(providers.items.allSatisfy { $0.state == .on && $0.image != nil })

        let icons = try submenu("Ícone na barra", in: menu)
        #expect(icons.items.map(\.title) == BarIconStyle.allCases.map(\.title))
        #expect(icons.items.filter { $0.state == .on }.map(\.title) == [BarIconStyle.meters.title])

        let metrics = try submenu("Número na barra", in: menu)
        #expect(metrics.items.filter { $0.state == .on }.map(\.title) == [settings.barMetric.title])
        #expect(try item("Mostrar o número ao lado do ícone", in: menu).state == .on)
    }

    @Test("Chaves de API: estado de cada conta e o que dá para fazer")
    func keys() throws {
        let secrets = MemorySecrets([.openRouter: "sk-or-v1-abcdef123456"])
        let (menu, _, builder, cleanUp) = try makeMenu(secrets: secrets)
        defer {
            withExtendedLifetime(builder) {}
            cleanUp()
        }
        let keys = try submenu("Chaves de API", in: menu)
        #expect(keys.items.map(\.title) == ["OpenRouter", "Ollama Cloud"])
        #expect(keys.items.map(\.state) == [.on, .off])
        #expect(keys.items.allSatisfy { $0.image != nil })

        let openRouter = try #require(keys.items.first?.submenu)
        #expect(
            openRouter.items.map(\.title) == [
                "Chave guardada no Chaves", "", "Trocar a chave…", "Remover a chave", "Criar uma chave no site…",
            ])
        #expect(try item("Remover a chave", in: openRouter).isEnabled)

        let ollama = try #require(keys.items.last?.submenu)
        #expect(ollama.items.first?.title == "Nenhuma chave definida")
        #expect(try item("Definir a chave…", in: ollama).isEnabled)
        #expect(!(try item("Remover a chave", in: ollama).isEnabled))

        try perform(try item("Remover a chave", in: openRouter))
        #expect(secrets.secret(for: .openRouter) == nil)
    }

    @Test("As ações alteram as preferências")
    func actions() throws {
        let (menu, settings, builder, cleanUp) = try makeMenu()
        defer {
            withExtendedLifetime(builder) {}
            cleanUp()
        }

        try perform(try item("Mostrar o número ao lado do ícone", in: menu))
        #expect(!settings.showPercentInBar)
        try perform(try item("Mostrar % restante", in: menu))
        #expect(settings.showRemaining)
        try perform(try item("Mostrar tempo até renovar", in: menu))
        #expect(settings.showCountdown)
        try perform(try item("Cores de alerta", in: menu))
        #expect(!settings.colorAlerts)

        let providers = try submenu("Provedores", in: menu)
        try perform(try #require(providers.items.first { $0.title == "Codex" }))
        #expect(!settings.isEnabled(.codex))

        let icons = try submenu("Ícone na barra", in: menu)
        try perform(try #require(icons.items.first { $0.title == BarIconStyle.criticalLogo.title }))
        #expect(settings.barIconStyle == .criticalLogo)

        let metrics = try submenu("Número na barra", in: menu)
        try perform(try #require(metrics.items.first { $0.title == BarMetric.tokensToday.title }))
        #expect(settings.barMetric == .tokensToday)

        let intervals = try submenu("Atualizar a cada", in: menu)
        #expect(intervals.items.map(\.title) == ["1 minuto", "2 minutos", "5 minutos", "10 minutos"])
        try perform(try #require(intervals.items.last))
        #expect(settings.refreshInterval == 600)

        try perform(try item("Atualizar agora", in: menu))
    }
}
