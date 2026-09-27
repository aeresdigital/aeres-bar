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
}
