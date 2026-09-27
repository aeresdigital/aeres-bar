import Foundation

extension CommandService {
    /// Doubao: Volcengine Ark's Coding Plan (and Agent Plan), through the official `arkcli` and its
    /// own login. Ark API keys cannot read the plan's usage.
    public static func doubao(home: URL = DataLocations.arkCLIHome) -> CommandService {
        CommandService(
            provider: .doubao,
            name: "Doubao",
            source: "arkcli (Volcengine)",
            executables: ["arkcli"],
            pathVariable: "ARKCLI_PATH",
            loginFolders: [home],
            arguments: ["usage", "plan", "--format", "json"],
            installHint:
                "Para acompanhar o Coding Plan do Doubao, instale o arkcli (npm i -g @volcengine/ark-cli) e rode “arkcli auth login”.",
            loginHint: "Rode “arkcli auth login” no Terminal para o AERES Bar ler o Coding Plan do Doubao.",
            read: ArkCLIParser.outcome
        )
    }

    /// Qwen: Alibaba Model Studio's Coding Plan, through the official `bl` CLI and its console
    /// login. Model Studio has no API that reads the plan with its API key.
    public static func qwen(config: URL = DataLocations.bailianConfig) -> CommandService {
        CommandService(
            provider: .qwen,
            name: "Qwen",
            source: "bl (Model Studio)",
            executables: ["bl"],
            pathVariable: "BAILIAN_CLI_PATH",
            loginFolders: [config],
            arguments: ["usage", "coding-plan", "--output", "json"],
            installHint:
                "Para acompanhar o Coding Plan do Qwen, instale o CLI do Model Studio (npm install -g bailian-cli) e rode “bl auth login --console”.",
            loginHint: "Rode “bl auth login --console” no Terminal (com “--console-site international” em contas internacionais).",
            read: BailianCLIParser.outcome
        )
    }
}
