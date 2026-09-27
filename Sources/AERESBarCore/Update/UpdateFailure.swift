import Foundation

/// Why checking for or installing an update did not work. Nothing is installed in any of these cases.
public enum UpdateFailure: Error, Equatable, Sendable {
    /// No connection, DNS failure, timeout: the transport's own description.
    case unreachable(String)
    /// The feed or the download answered with this HTTP status.
    case http(Int)
    /// `update.json` cannot be read, or points somewhere other than the feed.
    case invalidManifest
    /// The zip's signature does not match the key compiled into the app.
    case badSignature
    /// The zip holds no app, another app, or one that fails the code signature check.
    case invalidPackage
    /// The app inside the zip is not newer than the running one.
    case notNewer
    /// Gatekeeper runs the app from a temporary read-only copy (opened from Downloads or the DMG).
    case translocated
    /// This user cannot write to the folder or the app.
    case notWritable(String)
    /// macOS protects an app installed from a browser download: nothing but Finder may replace it.
    case protectedByMacOS
    /// The helper could not swap the apps after the app quit, and kept the old one.
    case swapFailed
    /// Running outside an installed app (`swift run`): there is no app to replace.
    case developmentBuild
    /// Anything else (disk full, for one), with the system's description.
    case other(String)

    public var message: String {
        switch self {
        case .unreachable(let detail):
            "Não foi possível acessar as atualizações: \(detail)"
        case .http(404):
            "Nenhuma versão publicada foi encontrada (HTTP 404)."
        case .http(let status):
            "O servidor de atualizações respondeu HTTP \(status). Tente de novo mais tarde."
        case .invalidManifest:
            "A descrição da versão publicada não é válida. Nada foi instalado."
        case .badSignature:
            "A assinatura do pacote baixado não confere. Nada foi instalado."
        case .invalidPackage:
            "O pacote baixado não contém uma versão válida do \(AppInfo.name). Nada foi instalado."
        case .notNewer:
            "O pacote baixado não é mais novo que a versão instalada. Nada foi instalado."
        case .translocated:
            "O macOS está abrindo o \(AppInfo.name) de um local temporário. Mova o app para a pasta Aplicativos, abra de novo e tente atualizar."
        case .notWritable(let folder):
            "Sem permissão para substituir o \(AppInfo.name) em \(folder). Instale a nova versão pelo DMG."
        case .protectedByMacOS:
            "O macOS protege o \(AppInfo.name) porque ele veio de um download pelo navegador, e não deixa o app se atualizar. "
                + "Reinstale uma vez pelo Terminal com o comando abaixo; depois as atualizações chegam sozinhas."
        case .swapFailed:
            "A atualização não conseguiu substituir o \(AppInfo.name), e a versão anterior foi mantida. "
                + "Reinstale uma vez pelo Terminal com o comando abaixo; depois as atualizações chegam sozinhas."
        case .developmentBuild:
            "Esta cópia roda fora de um app instalado e não se atualiza sozinha."
        case .other(let detail):
            "A atualização não foi concluída: \(detail)"
        }
    }

    /// Fixed by reinstalling once with `UpdateFeed.installCommand`.
    public var needsReinstall: Bool {
        self == .protectedByMacOS || self == .swapFailed
    }
}
