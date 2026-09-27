import Foundation
import Testing
import os

@testable import AERESBarCore

/// Serves canned responses to `URLSession`, keyed by URL.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    static let stubs = OSAllocatedUnfairLock<[String: Stub]>(initialState: [:])

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let stub = Self.stubs.withLock({ $0[url.absoluteString] }),
            let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Infraestrutura")
struct InfrastructureTests {
    private func client() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(session: URLSession(configuration: configuration))
    }

    @Test("Cliente HTTP devolve status, corpo e cabeçalhos em minúsculas")
    func httpClient() async throws {
        let address = "https://example.test/usage-\(UUID().uuidString)"
        StubURLProtocol.stubs.withLock {
            $0[address] = StubURLProtocol.Stub(status: 429, headers: ["Retry-After": "90"], body: Data("{}".utf8))
        }
        let response = try await client().send(URLRequest(url: try #require(URL(string: address))))
        #expect(response.status == 429)
        #expect(response.headers["retry-after"] == "90")
        #expect(response.body == Data("{}".utf8))
    }

    @Test("Cliente HTTP propaga falhas de transporte")
    func httpFailure() async throws {
        let url = try #require(URL(string: "https://example.test/missing-\(UUID().uuidString)"))
        await #expect(throws: (any Error).self) { try await client().send(URLRequest(url: url)) }
    }

    @Test("Executa comandos e captura a saída")
    func runsCommands() throws {
        let runner = ProcessCommandRunner()
        let output = try #require(runner.run("/bin/echo", ["olá"], timeout: 5))
        #expect(output.status == 0)
        #expect(output.text == "olá\n")

        let failing = try #require(runner.run("/bin/ls", ["/nonexistent-\(UUID().uuidString)"], timeout: 5))
        #expect(failing.status != 0)
        #expect(!failing.stderr.isEmpty)
    }

    @Test("Comando lento é interrompido; executável ausente devolve nil")
    func timeoutsAndMissingExecutables() {
        let runner = ProcessCommandRunner()
        let start = Date()
        #expect(runner.run("/bin/sleep", ["5"], timeout: 0.3) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(runner.run("/nonexistent/tool", [], timeout: 1) == nil)
    }

    @Test("Saída maior que o buffer do pipe não trava o processo")
    func largeOutput() throws {
        let output = try #require(ProcessCommandRunner().run("/usr/bin/head", ["-c", "1000000", "/dev/zero"], timeout: 10))
        #expect(output.status == 0)
        #expect(output.stdout.count == 1_000_000)
    }

    @Test("O PATH do comando inclui a pasta dele e as de instalação (scripts de Node)")
    func pathForScripts() throws {
        let output = try #require(ProcessCommandRunner().run("/usr/bin/env", [], timeout: 5))
        let path = output.text.split(separator: "\n").first { $0.hasPrefix("PATH=") }.map { String($0.dropFirst(5)) } ?? ""
        #expect(path.hasPrefix("/usr/bin:/opt/homebrew/bin:/usr/local/bin:"))
    }

    @Test("Entrega a entrada padrão ao comando")
    func standardInput() throws {
        let output = try #require(ProcessCommandRunner().run("/bin/cat", [], input: Data("segredo\n".utf8), timeout: 5))
        #expect(output.status == 0)
        #expect(output.trimmedOutput == "segredo")
        #expect(CommandOutput(status: 1, stdout: Data("x".utf8)).trimmedOutput == nil)
        #expect(CommandOutput(status: 0, stdout: Data(" \n".utf8)).trimmedOutput == nil)
    }

    @Test("Local padrão dos dados de cada ferramenta")
    func defaultLocations() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(DataLocations.claudeProjectRoots.map(\.path).contains("\(home)/.claude/projects"))
        #expect(DataLocations.claudeCredentialsFile.path == "\(home)/.claude/.credentials.json")
        #expect(DataLocations.antigravityApplications.first?.path == "/Applications/Antigravity.app")
        #expect(DataLocations.antigravityData.path == "\(home)/.gemini/antigravity")
        #expect(DataLocations.snapshotCacheFile.path.hasSuffix("AERES Bar/snapshots.json"))
        #expect(AppInfo.userAgent.hasPrefix("AERESBar/"))
    }
}

@Suite("Variáveis de ambiente", .serialized)
struct EnvironmentOverrideTests {
    @Test("CODEX_HOME e CLAUDE_CONFIG_DIR são respeitados")
    func overrides() {
        setenv("CODEX_HOME", "/tmp/codex-home", 1)
        setenv("CLAUDE_CONFIG_DIR", "/tmp/claude-config", 1)
        defer {
            unsetenv("CODEX_HOME")
            unsetenv("CLAUDE_CONFIG_DIR")
        }
        #expect(DataLocations.codexHome.path == "/tmp/codex-home")
        #expect(DataLocations.claudeProjectRoots.first?.path == "/tmp/claude-config/projects")
    }

    @Test("GH_CONFIG_DIR e OLLAMA_HOST são respeitados")
    func githubAndOllama() {
        let saved = ["GH_CONFIG_DIR", "OLLAMA_HOST"].map { ($0, ProcessInfo.processInfo.environment[$0]) }
        defer {
            for (name, value) in saved {
                if let value { setenv(name, value, 1) } else { unsetenv(name) }
            }
        }
        setenv("GH_CONFIG_DIR", "/tmp/gh-config", 1)
        setenv("OLLAMA_HOST", "0.0.0.0:8080", 1)
        #expect(DataLocations.githubCLIHostsFile.path == "/tmp/gh-config/hosts.yml")
        #expect(DataLocations.ollamaServer.absoluteString == "http://0.0.0.0:8080")
    }
}

@Suite("Endereço do servidor do Ollama")
struct OllamaServerAddressTests {
    @Test(
        "Mesmas regras do cliente do Ollama",
        arguments: [
            (nil, "http://127.0.0.1:11434"),
            ("  ", "http://127.0.0.1:11434"),
            ("0.0.0.0", "http://0.0.0.0:11434"),
            ("192.168.0.10:8080", "http://192.168.0.10:8080"),
            (":9000", "http://127.0.0.1:9000"),
            ("http://ollama.local", "http://ollama.local:80"),
            ("https://ollama.example.com/proxy", "https://ollama.example.com:443/proxy"),
            ("ftp://ollama.local", "http://127.0.0.1:11434"),
        ] as [(String?, String)]
    )
    func address(raw: String?, expected: String) {
        #expect(DataLocations.ollamaServer(from: raw).absoluteString == expected)
    }
}

@Suite("Chaves de API no Chaves do macOS")
struct KeychainSecretStoreTests {
    private func answering(_ status: Int32, _ stdout: String = "") -> ScriptedCommandRunner {
        ScriptedCommandRunner { _ in CommandOutput(status: status, stdout: Data(stdout.utf8)) }
    }

    @Test("Lê a chave guardada pelo `security`")
    func readsStoredKey() throws {
        let runner = answering(0, "sk-or-v1-abcdef123456\n")
        let store = KeychainSecretStore(runner: runner, environment: ["OPENROUTER_API_KEY": "from-env-123"])
        #expect(store.secret(for: .openRouter) == "sk-or-v1-abcdef123456")
        let call = try #require(runner.calls.first)
        #expect(call.executable == "/usr/bin/security")
        #expect(call.arguments == ["find-generic-password", "-s", "AERES Bar", "-a", "openrouter", "-w"])
    }

    @Test("Sem chave guardada, usa a variável de ambiente da ferramenta")
    func environmentFallback() {
        let missing = answering(44)
        #expect(
            KeychainSecretStore(runner: missing, environment: ["OLLAMA_API_KEY": "ollama-env-key"]).secret(for: .ollama) == "ollama-env-key"
        )
        #expect(KeychainSecretStore(runner: missing, environment: ["OLLAMA_API_KEY": ""]).secret(for: .ollama) == nil)
        #expect(KeychainSecretStore(runner: missing, environment: [:]).secret(for: .openRouter) == nil)
    }

    @Test("Grava pela entrada padrão, nunca nos argumentos")
    func writesThroughStandardInput() throws {
        let runner = answering(0)
        try KeychainSecretStore(runner: runner, environment: [:]).setSecret("  sk-or-v1-abcdef123456\n", for: .openRouter)
        let call = try #require(runner.calls.first)
        #expect(call.executable == "/usr/bin/security")
        #expect(call.arguments == ["-i"])
        let input = String(decoding: try #require(call.input), as: UTF8.self)
        #expect(input == "add-generic-password -U -s \"AERES Bar\" -a openrouter -w \"sk-or-v1-abcdef123456\"\n")
    }

    @Test(
        "Recusa chaves que não parecem chaves, sem chamar o `security`",
        arguments: [
            "", "curta", "tem espaço no meio", "aspas\"no-meio", "barra\\invertida", "acentuação-não", String(repeating: "a", count: 4_097),
        ]
    )
    func rejectsMalformedKeys(key: String) {
        let runner = answering(0)
        #expect(throws: SecretStoreError.invalidFormat) {
            try KeychainSecretStore(runner: runner, environment: [:]).setSecret(key, for: .ollama)
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("Falhas do `security` viram erro; apagar o que não existe não é erro")
    func failures() throws {
        #expect(throws: SecretStoreError.keychainFailure) {
            try KeychainSecretStore(runner: answering(1), environment: [:]).setSecret("sk-or-v1-abcdef123456", for: .openRouter)
        }
        #expect(throws: SecretStoreError.keychainFailure) {
            try KeychainSecretStore(runner: ScriptedCommandRunner { _ in nil }, environment: [:]).setSecret(
                "sk-or-v1-abcdef123456", for: .openRouter)
        }
        try KeychainSecretStore(runner: answering(0), environment: [:]).deleteSecret(for: .ollama)
        try KeychainSecretStore(runner: answering(44), environment: [:]).deleteSecret(for: .ollama)
        #expect(throws: SecretStoreError.keychainFailure) {
            try KeychainSecretStore(runner: answering(1), environment: [:]).deleteSecret(for: .ollama)
        }
        #expect(throws: SecretStoreError.keychainFailure) {
            try KeychainSecretStore(runner: ScriptedCommandRunner { _ in nil }, environment: [:]).deleteSecret(for: .ollama)
        }
    }

    @Test("make uninstall apaga a chave de todas as contas")
    func uninstallCoversEveryAccount() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/uninstall.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("for account in") })
        let listed = Set(line.dropFirst("for account in".count).split(separator: ";")[0].split(separator: " ").map(String.init))
        #expect(listed == Set(SecretAccount.allCases.map(\.rawValue)))
    }

    @Test("Contas de chave e seus provedores")
    func accounts() {
        #expect(SecretAccount(provider: .openrouter) == .openRouter)
        #expect(SecretAccount(provider: .ollama) == .ollama)
        #expect(SecretAccount(provider: .claude) == nil)
        for account in SecretAccount.allCases {
            #expect(SecretAccount(provider: account.provider) == account)
            #expect(account.keysPage?.scheme == "https")
            #expect(!account.environmentVariables.isEmpty && account.environmentVariables.allSatisfy { $0.hasSuffix("_API_KEY") })
        }
    }
}

@Suite("Login do GitHub para o Copilot")
struct GitHubTokenSourceTests {
    let executable = "/usr/bin/true"  // any executable path stands in for `gh`; the runner is scripted

    @Test("hosts.yml: o token do host github.com, preferindo o da conta ativa")
    func hostsFile() {
        let yaml = """
            # gh hosts
            github.example.com:
                oauth_token: enterprise-token
            github.com:
                users:
                    octocat:
                        oauth_token: nested-token

                git_protocol: https
                oauth_token: "active-token"
                user: octocat
            """
        #expect(LocalGitHubTokenSource.hostsToken(in: yaml) == "active-token")
        #expect(LocalGitHubTokenSource.hostsToken(in: "github.com:\n    user: octocat\n") == nil)
        #expect(LocalGitHubTokenSource.hostsToken(in: "github.example.com:\n    oauth_token: x\n") == nil)
    }

    @Test("Arquivos dos plugins do Copilot")
    func copilotFiles() {
        let apps = #"{"github.com:Iv1.0000000000000000": {"user": "octocat", "oauth_token": "apps-token", "githubAppId": "Iv1.0"}}"#
        #expect(LocalGitHubTokenSource.copilotToken(in: Data(apps.utf8)) == "apps-token")
        #expect(LocalGitHubTokenSource.copilotToken(in: Data(#"{"github.com": {"oauth_token": "hosts-token"}}"#.utf8)) == "hosts-token")
        #expect(LocalGitHubTokenSource.copilotToken(in: Data(#"{"example.com": {"oauth_token": "x"}}"#.utf8)) == nil)
        #expect(LocalGitHubTokenSource.copilotToken(in: Data("[]".utf8)) == nil)
    }

    @Test("Ordem de busca: gh, hosts.yml, plugins do Copilot e variáveis de ambiente")
    func lookupOrder() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let hosts = folder.url.appendingPathComponent("hosts.yml")
        let apps = folder.url.appendingPathComponent("apps.json")
        let failingCLI = ScriptedCommandRunner { _ in CommandOutput(status: 1, stdout: Data()) }
        func source(_ runner: ScriptedCommandRunner, environment: [String: String] = [:]) -> LocalGitHubTokenSource {
            LocalGitHubTokenSource(
                runner: runner, cliCandidates: [executable], hostsFile: hosts, copilotFiles: [apps], environment: environment)
        }

        let cli = ScriptedCommandRunner { _ in CommandOutput(status: 0, stdout: Data("cli-token\n".utf8)) }
        #expect(source(cli).token() == "cli-token")
        #expect(cli.calls.first?.arguments == ["auth", "token", "--hostname", "github.com"])

        #expect(source(failingCLI, environment: ["GITHUB_TOKEN": "env-token"]).token() == "env-token")
        #expect(source(failingCLI, environment: ["GH_TOKEN": "", "GITHUB_TOKEN": ""]).token() == nil)

        try folder.write(#"{"github.com": {"oauth_token": "plugin-token"}}"#, to: "apps.json")
        #expect(source(failingCLI, environment: ["GH_TOKEN": "env-token"]).token() == "plugin-token")

        try folder.write("github.com:\n    oauth_token: hosts-token\n", to: "hosts.yml")
        #expect(source(failingCLI).token() == "hosts-token")
    }
}
