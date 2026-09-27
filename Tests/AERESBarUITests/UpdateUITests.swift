import AppKit
import SwiftUI
import Testing
import os

@testable import AERESBarCore
@testable import AERESBarUI

/// Always offers `manifest`; downloads can be made to wait, so the updater stays in "Baixando".
private final class OfferingSource: UpdateSource {
    let manifest = UpdateManifest(
        version: "1.0.99",
        build: 99,
        notes: "### Novidades\n\n- Atualização pelo próprio app\n",
        url: URL(fileURLWithPath: "/AERES-Bar.zip"),
        signature: ""
    )
    private let waits = OSAllocatedUnfairLock(initialState: false)

    func holdDownloads() {
        waits.withLock { $0 = true }
    }

    func latest() async throws -> UpdateManifest { manifest }

    func download(_ manifest: UpdateManifest) async throws -> Data {
        if waits.withLock({ $0 }) { try await Task.sleep(for: .seconds(30)) }
        return Data()
    }
}

/// Every step fails as if macOS protected the app.
private struct ProtectedInstaller: UpdateInstalling {
    func installTarget() throws -> URL { throw UpdateFailure.protectedByMacOS }
    func prepare(_ zip: Data, for manifest: UpdateManifest, replacing target: URL) throws -> PreparedUpdate {
        throw UpdateFailure.invalidPackage
    }
    func launch(_ update: PreparedUpdate) {}
    func consumeFailedSwap() -> Bool { false }
}

@MainActor
private func makeUpdater(_ source: OfferingSource = OfferingSource(), enabled: Bool = true) -> AppUpdater {
    AppUpdater(
        source: source,
        installer: ProtectedInstaller(),
        currentVersion: "1.0.41",
        currentBuild: 41,
        isEnabled: enabled,
        quit: {}
    )
}

@Suite("Atualização na interface")
@MainActor
struct UpdateUITests {
    private func menu(updater: AppUpdater?) throws -> (NSMenu, SettingsMenu, () -> Void) {
        let temporary = try TemporarySettings()
        let builder = SettingsMenu(
            store: UsageStore(providers: []), settings: temporary.settings, secrets: MemorySecrets(), updater: updater)
        return (builder.makeMenu(), builder, temporary.remove)
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title.hasPrefix(title) }, "item \(title)")
    }

    @Test("Procurar atualizações fica desligado fora do app instalado")
    func checkItemDisabled() throws {
        for updater in [nil, makeUpdater(enabled: false)] {
            let (menu, builder, cleanUp) = try self.menu(updater: updater)
            defer { cleanUp() }
            withExtendedLifetime(builder) {}
            let check = try item("Procurar atualizações", in: menu)
            #expect(!check.isEnabled)
            #expect(menu.items.first?.title == "Atualizar agora")
        }
    }

    @Test("Uma versão nova aparece no topo do menu")
    func installItem() async throws {
        let updater = makeUpdater()
        await updater.check(userInitiated: false)
        let (menu, builder, cleanUp) = try self.menu(updater: updater)
        defer { cleanUp() }
        withExtendedLifetime(builder) {}
        let install = try #require(menu.items.first)
        #expect(install.title == "Instalar a versão 1.0.99…")
        #expect(install.isEnabled)
        #expect(install.image != nil)
        #expect(menu.items[1].isSeparatorItem)
        #expect(try item("Procurar atualizações…", in: menu).isEnabled)
    }

    @Test("Durante o download, o item mostra o andamento e fica desligado")
    func downloadingItem() async throws {
        let source = OfferingSource()
        source.holdDownloads()
        let updater = AppUpdater(
            source: source, installer: WritableInstaller(), currentVersion: "1.0.41", currentBuild: 41, isEnabled: true, quit: {})
        await updater.check(userInitiated: true)
        let task = updater.install()
        for _ in 0..<100 where updater.phase != .downloading(source.manifest) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(updater.phase == .downloading(source.manifest))
        let (menu, builder, cleanUp) = try self.menu(updater: updater)
        defer { cleanUp() }
        withExtendedLifetime(builder) {}
        #expect(menu.items.first?.title == "Baixando a versão 1.0.99…")
        #expect(menu.items.first?.isEnabled == false)
        #expect(try item("Procurar atualizações…", in: menu).isEnabled == false)
        updater.cancel()
        await task?.value
        #expect(updater.phase == .available(source.manifest))
    }

    @Test("O aviso no painel aparece com a versão nova e cresce com o comando de reinstalação")
    func panelNotice() async throws {
        let temporary = try TemporarySettings()
        defer { temporary.remove() }
        let store = UsageStore(providers: [])
        await store.refreshAllAndWait()
        func height(_ updater: AppUpdater?) -> CGFloat {
            let view = PanelRootView(
                store: store, settings: temporary.settings, state: PanelState(), actions: PanelActions(), updater: updater)
            return ImageRenderer(content: view).nsImage?.size.height ?? 0
        }
        let idle = makeUpdater()
        let plain = height(idle)
        #expect(plain == height(nil))

        await idle.check(userInitiated: false)
        let offered = height(idle)
        #expect(offered > plain + 40)

        await idle.install()?.value
        #expect(idle.phase == .failed(.protectedByMacOS, idle.pendingUpdate))
        #expect(height(idle) > offered)

        idle.dismiss()
        #expect(height(idle) == plain)
    }

    @Test("O aviso desenha cada fase")
    func noticePhases() async throws {
        let source = OfferingSource()
        source.holdDownloads()
        let updater = AppUpdater(
            source: source, installer: WritableInstaller(), currentVersion: "1.0.41", currentBuild: 41, isEnabled: true, quit: {})
        func rendered() -> CGFloat {
            ImageRenderer(content: UpdateNotice(updater: updater).frame(width: 400)).nsImage?.size.height ?? 0
        }
        #expect(rendered() == 0)
        await updater.check(userInitiated: true)
        #expect(rendered() > 0)
        let task = updater.install()
        for _ in 0..<100 where updater.phase != .downloading(source.manifest) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(rendered() > 0)
        updater.cancel()
        await task?.value
    }

    @Test("Copiar o comando de reinstalação")
    func copiesCommand() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AERESBarTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        Pasteboard.copy(UpdateFeed.installCommand, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == UpdateFeed.installCommand)
    }
}

/// Lets the download start; nothing is ever installed.
private struct WritableInstaller: UpdateInstalling {
    func installTarget() -> URL { URL(fileURLWithPath: "/Applications/AERES Bar.app") }
    func prepare(_ zip: Data, for manifest: UpdateManifest, replacing target: URL) throws -> PreparedUpdate {
        throw UpdateFailure.invalidPackage
    }
    func launch(_ update: PreparedUpdate) {}
    func consumeFailedSwap() -> Bool { false }
}
