import Foundation

/// Texts for the update notice in the panel, the menu item and the dialogs.
public enum UpdatePresentation {
    /// The panel's notice: what is happening and what it means.
    public struct Notice: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var isProblem: Bool
    }

    /// A dialog's heading and body.
    public struct Message: Equatable, Sendable {
        public var title: String
        public var body: String
    }

    /// Note lines shown in a dialog before it is cut short.
    static let noteLimit = 8

    /// The menu item for a build on offer or under way, or `nil` when there is none. ("Atualizar
    /// agora" already means reading the usage again, so installing says "Instalar".)
    public static func menuTitle(for phase: AppUpdater.Phase) -> String? {
        switch phase {
        case .available(let manifest), .failed(_, .some(let manifest)): "Instalar a versão \(manifest.version)…"
        case .downloading(let manifest): "Baixando a versão \(manifest.version)…"
        case .installing(let manifest): "Instalando a versão \(manifest.version)…"
        case .idle, .checking, .failed(_, .none): nil
        }
    }

    public static func notice(for phase: AppUpdater.Phase, currentVersion: String) -> Notice? {
        switch phase {
        case .idle, .checking:
            nil
        case .available(let manifest):
            Notice(
                title: "Nova versão disponível: \(manifest.version)",
                detail: manifest.releaseNotes.first(where: { !$0.isHeading })?.text ?? "Você tem a \(currentVersion).",
                isProblem: false
            )
        case .downloading(let manifest):
            Notice(title: "Baixando a versão \(manifest.version)…", detail: "O pacote é verificado antes de instalar.", isProblem: false)
        case .installing(let manifest):
            Notice(
                title: "Instalando a versão \(manifest.version)…",
                detail: "O \(AppInfo.name) fecha e abre de novo em alguns segundos.",
                isProblem: false
            )
        case .failed(let failure, _):
            Notice(title: "Não foi possível atualizar", detail: failure.message, isProblem: true)
        }
    }

    /// The answer to "Procurar atualizações…".
    public static func checkMessage(for result: AppUpdater.CheckResult, currentVersion: String) -> Message {
        switch result {
        case .upToDate:
            Message(title: "O \(AppInfo.name) está atualizado", body: "Você já tem a versão mais recente (\(currentVersion)).")
        case .available(let manifest):
            confirmation(for: manifest, currentVersion: currentVersion)
        case .failed(let failure):
            Message(title: "Não foi possível procurar atualizações", body: failure.message)
        case .busy:
            Message(title: "Atualização em andamento", body: "Espere a atualização em andamento terminar.")
        }
    }

    /// Asks before installing: the versions, what changed, and that the app reopens.
    public static func confirmation(for manifest: UpdateManifest, currentVersion: String) -> Message {
        let notes = manifest.releaseNotes
        var body = "Você tem a \(currentVersion)."
        if !notes.isEmpty {
            body += "\n" + notes.prefix(noteLimit).map { $0.isHeading ? "\n\($0.text):" : "• \($0.text)" }.joined(separator: "\n")
            if notes.count > noteLimit { body += "\n…" }
        }
        body += "\n\nO \(AppInfo.name) fecha e abre de novo em alguns segundos."
        return Message(title: "Nova versão do \(AppInfo.name): \(manifest.version)", body: body)
    }
}
