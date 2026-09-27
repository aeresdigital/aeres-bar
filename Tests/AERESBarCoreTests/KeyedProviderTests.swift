import Foundation
import Testing
import os

@testable import AERESBarCore

@Suite("Provedor com chave de API")
struct KeyedUsageProviderTests {
    let clock = TestClock()

    /// A made-up service with an international and a mainland host, answering `{"used": <percent>}`
    /// on `/usage` and its balance as plain text on `/balance`.
    private func service(
        errorInBody: @escaping @Sendable (Data) -> ProviderIssue? = { _ in nil },
        localCredential: @escaping @Sendable (Date) -> KeyedService.LocalCredential? = { _ in nil }
    ) -> KeyedService {
        KeyedService(
            provider: .openrouter,
            account: .openRouter,
            name: "Teste",
            source: "API de teste",
            regions: [
                KeyedService.Region("global", "https://global.example.test/v1"), KeyedService.Region("china", "https://cn.example.test/v1"),
            ],
            request: { base, key in KeyedService.get(base.appendingPathComponent("usage"), key: key) },
            extras: { base, key in [KeyedService.get(base.appendingPathComponent("balance"), key: key)] },
            read: { answer, _ in
                guard let used = JSON.object(answer.main).flatMap({ JSON.double($0["used"]) }) else { return nil }
                let balance = answer.extras.first.flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) + " (\(answer.region.name))" }
                return KeyedReading(
                    windows: [UsageWindow(id: "w", title: "Mensal", usedPercent: used)],
                    details: balance.map { [DetailRow(label: "Saldo", value: $0)] } ?? []
                )
            },
            errorInBody: errorInBody,
            localCredential: localCredential
        )
    }

    private func provider(_ http: MockHTTPClient, service: KeyedService? = nil) -> KeyedUsageProvider {
        KeyedUsageProvider(
            service: service ?? self.service(), http: http, secrets: MemorySecretStore([.openRouter: "key-12345678"]), now: clock.provider)
    }

    private func answer(_ request: URLRequest, global: Int, china: Int) throws -> HTTPResponse {
        let host = request.url?.host() ?? ""
        let status = host.hasPrefix("global") ? global : china
        guard status > 0 else { throw TestError.offline }
        let body = request.url?.lastPathComponent == "balance" ? "12,50" : #"{"used": 40}"#
        return HTTPResponse(status: status, body: Data(body.utf8))
    }

    @Test("Chave de outra região: tenta a próxima e passa a usar só ela")
    func regionFallback() async throws {
        let http = MockHTTPClient { [self] in try answer($0, global: 401, china: 200) }
        let keyed = provider(http)
        let snapshot = await keyed.snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.windows.first?.usedPercent == 40)
        #expect(snapshot.details == [DetailRow(label: "Saldo", value: "12,50 (china)")])  // the reading knows the region
        #expect(snapshot.source == "API de teste")
        #expect(
            http.requests.map { $0.url?.absoluteString } == [
                "https://global.example.test/v1/usage", "https://cn.example.test/v1/usage", "https://cn.example.test/v1/balance",
            ])
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer key-12345678")

        clock.advance(by: 61)
        _ = await keyed.snapshot(previous: snapshot)
        #expect(http.requests.count == 5)
        #expect(http.requests.suffix(2).allSatisfy { $0.url?.host() == "cn.example.test" })
    }

    @Test("Uma região fora do ar não impede a outra")
    func unreachableRegion() async {
        let http = MockHTTPClient { [self] in try answer($0, global: 0, china: 200) }
        #expect(await provider(http).snapshot(previous: nil).status == .ok)
    }

    @Test(
        "Todas recusam: chave recusada; nenhuma responde: sem conexão", arguments: [(401, ProviderIssue.Kind.unauthorized), (0, .network)])
    func everyRegionFails(status: Int, expected: ProviderIssue.Kind) async {
        let http = MockHTTPClient { [self] in try answer($0, global: status, china: status) }
        let snapshot = await provider(http).snapshot(previous: nil)
        #expect(snapshot.issue == expected)
        #expect(http.requests.count == 2)
    }

    @Test("Erro no corpo de uma resposta 200")
    func errorInBody() async {
        let refusing = service { _ in ProviderIssue(.unauthorized, "") }
        let http = MockHTTPClient { [self] in try answer($0, global: 200, china: 200) }
        #expect(await provider(http, service: refusing).snapshot(previous: nil).issue == .unauthorized)
        #expect(http.requests.count == 2)  // tried both regions

        let throttled = MockHTTPClient { [self] in try answer($0, global: 200, china: 200) }
        let keyed = provider(throttled, service: service { _ in ProviderIssue(.rateLimited, "") })
        #expect(await keyed.snapshot(previous: nil).issue == .rateLimited)
        _ = await keyed.snapshot(previous: nil, reason: .manual)
        #expect(throttled.requests.count == 1)  // the pause holds, even for the button

        let noPlan = provider(MockHTTPClient(status: 200), service: service { _ in ProviderIssue(.notSignedIn, "Sem plano ativo.") })
        let snapshot = await noPlan.snapshot(previous: nil)
        #expect(snapshot.issue == .notSignedIn)
        #expect(snapshot.message == "Sem plano ativo.")  // its own message, not a generic one
    }

    @Test("Resposta ilegível não fica em cache; extras que falham são ignorados")
    func invalidAndExtras() async {
        let http = MockHTTPClient(status: 200, body: Data("<html>".utf8))
        let keyed = provider(http)
        #expect(await keyed.snapshot(previous: nil).issue == .invalidResponse)

        http.respond { request in
            request.url?.lastPathComponent == "balance"
                ? HTTPResponse(status: 500, body: Data()) : HTTPResponse(status: 200, body: Data(#"{"used": 7}"#.utf8))
        }
        let snapshot = await keyed.snapshot(previous: nil)
        #expect(snapshot.status == .ok)
        #expect(snapshot.windows.first?.usedPercent == 7)
        #expect(snapshot.details.isEmpty)
    }

    @Test("HTTP inesperado vira mensagem com o código")
    func unexpectedStatus() async {
        let snapshot = await provider(MockHTTPClient(status: 502)).snapshot(previous: nil)
        #expect(snapshot.issue == .invalidResponse)
        #expect(snapshot.message == "O Teste respondeu HTTP 502. Mostrando os últimos dados.")
    }

    @Test("Sem chave salva, usa o login da ferramenta; login vencido pede novo login")
    func localCredentials() async throws {
        let token = TokenBox("cli-token-1")
        let tool = service(localCredential: { _ in token.value.map { .token($0) } ?? .expired(message: "Rode /login na ferramenta.") })
        let http = MockHTTPClient(status: 200, body: Data(#"{"used": 12}"#.utf8))
        let keyed = KeyedUsageProvider(service: tool, http: http, secrets: MemorySecretStore(), now: clock.provider)

        let first = await keyed.snapshot(previous: nil)
        #expect(first.status == .ok)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer cli-token-1")

        // The tool renews its token: same account, so the last reading stays while offline.
        token.value = "cli-token-2"
        http.respond { _ in throw TestError.offline }
        clock.advance(by: 61)
        let offline = await keyed.snapshot(previous: first)
        #expect(offline.status == .stale)
        #expect(offline.windows.first?.usedPercent == 12)

        token.value = nil
        let expired = await keyed.snapshot(previous: offline)
        #expect(expired.issue == .credentialsExpired)
        #expect(expired.message == "Rode /login na ferramenta.")
    }

    @Test("Uma chave salva tem prioridade sobre o login da ferramenta")
    func savedKeyWins() async {
        let tool = service(localCredential: { _ in .token("cli-token") })
        let http = MockHTTPClient(status: 200, body: Data(#"{"used": 1}"#.utf8))
        let keyed = KeyedUsageProvider(
            service: tool, http: http, secrets: MemorySecretStore([.openRouter: "saved-key-123"]), now: clock.provider)
        _ = await keyed.snapshot(previous: nil)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer saved-key-123")
    }
}

/// A token a test can change between refreshes.
private final class TokenBox: Sendable {
    private let stored: OSAllocatedUnfairLock<String?>

    init(_ value: String?) {
        stored = OSAllocatedUnfairLock(initialState: value)
    }

    var value: String? {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}
