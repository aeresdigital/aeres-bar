/// What the executable was asked to do.
public enum CLICommand: Equatable, Sendable {
    public enum LoginItemAction: String, Sendable {
        case on, off, status
    }

    /// Start the menu bar app (no arguments).
    case runApp
    /// Print every provider snapshot as JSON and exit.
    case dump
    /// Render panel and menu bar previews as PNG files into a folder, from live or sample data.
    case renderPreview(directory: String, demo: Bool)
    /// Enable, disable or report "open at login".
    case loginItem(LoginItemAction)
    /// Store an API key read from standard input.
    case setKey(SecretAccount)
    /// Remove a stored API key.
    case deleteKey(SecretAccount)
    /// Compare the installed version with the newest published one.
    case checkUpdate
    case version
    case help
    /// Unrecognised input, with the reason.
    case invalid(String)

    /// Parses `CommandLine.arguments` (the first element is the executable path).
    public static func parse(_ arguments: [String]) -> CLICommand {
        let args = Array(arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }  // Finder's process serial number
        guard let first = args.first else { return .runApp }
        switch first {
        case "--dump":
            return .dump
        case "--render-preview":
            guard args.count >= 2, !args[1].hasPrefix("--") else { return .invalid("--render-preview precisa de uma pasta de destino") }
            return .renderPreview(directory: args[1], demo: args.dropFirst(2).contains("--demo"))
        case "--login-item":
            guard args.count >= 2, let action = LoginItemAction(rawValue: args[1]) else {
                return .invalid("--login-item aceita on, off ou status")
            }
            return .loginItem(action)
        case "--set-key", "--delete-key":
            guard args.count >= 2, let account = SecretAccount(rawValue: args[1]) else {
                let names = SecretAccount.allCases.map(\.rawValue).joined(separator: " ou ")
                return .invalid("\(first) aceita \(names)")
            }
            return first == "--set-key" ? .setKey(account) : .deleteKey(account)
        case "--check-update":
            return .checkUpdate
        case "--version", "-v":
            return .version
        case "--help", "-h":
            return .help
        default:
            return .invalid("opção desconhecida: \(first)")
        }
    }

    public static let usage: String = {
        let accounts = SecretAccount.allCases.map(\.rawValue).joined(separator: "|")
        return """
            Uso: AERESBar [opção]

            Sem opções, abre o AERES Bar na barra de menus.

              --dump                   imprime em JSON tudo o que o app lê e sai
              --render-preview <dir> [--demo]
                                       salva imagens do painel e da barra em <dir>
                                       (--demo usa dados de exemplo em vez dos seus)
              --login-item on|off|status
                                       liga, desliga ou mostra a abertura no login
              --set-key \(accounts)
                                       guarda no Chaves a chave digitada (sem eco)
                                       ou recebida pela entrada padrão
              --delete-key \(accounts)
                                       apaga a chave guardada
              --check-update           compara a versão instalada com a mais recente
              --version                mostra a versão
              --help                   mostra esta ajuda
            """
    }()
}
