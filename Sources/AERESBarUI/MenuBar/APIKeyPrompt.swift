import AERESBarCore
import AppKit

/// Asks for an API key in a secure field.
@MainActor
enum APIKeyPrompt {
    /// The key typed, or `nil` if cancelled or left empty.
    static func ask(for account: SecretAccount) -> String? {
        let alert = NSAlert()
        alert.messageText = "Chave da API do \(account.displayName)"
        alert.informativeText =
            "Cole a chave criada em \(account.keysPage?.host() ?? "site do serviço"). "
            + "Ela fica guardada no Chaves do macOS e só é enviada para o \(account.displayName)."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = account == .openRouter ? "sk-or-v1-…" : "Chave da API"
        alert.accessoryView = field
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppInfo.name
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
