import AERESBarCore
import AppKit

/// Dialogs for updates started from the menu: the answer to "Procurar atualizações…", the
/// confirmation before installing, and a failure.
@MainActor
enum UpdatePrompt {
    /// Asks before installing. `true` for "Instalar e reabrir".
    static func confirm(_ message: UpdatePresentation.Message) -> Bool {
        let alert = NSAlert()
        alert.messageText = message.title
        alert.informativeText = message.body
        alert.addButton(withTitle: "Instalar e reabrir")
        alert.addButton(withTitle: "Agora não")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func inform(_ message: UpdatePresentation.Message, isProblem: Bool) {
        let alert = NSAlert()
        alert.alertStyle = isProblem ? .warning : .informational
        alert.messageText = message.title
        alert.informativeText = message.body
        NSApp.activate()
        alert.runModal()
    }

    /// When only a reinstall fixes it, shows the Terminal command and offers to copy it.
    static func showFailure(_ failure: UpdateFailure) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Não foi possível atualizar"
        alert.informativeText = failure.message
        if failure.needsReinstall {
            let field = NSTextField(wrappingLabelWithString: UpdateFeed.installCommand)
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.isSelectable = true
            field.frame = NSRect(x: 0, y: 0, width: 360, height: 44)
            alert.accessoryView = field
            alert.addButton(withTitle: "Copiar comando")
            alert.addButton(withTitle: "Fechar")
        }
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, failure.needsReinstall {
            Pasteboard.copy(UpdateFeed.installCommand)
        }
    }
}
