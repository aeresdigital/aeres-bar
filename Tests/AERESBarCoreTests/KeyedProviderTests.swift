import Foundation
import Testing

@testable import AERESBarCore

@Suite("Provedor com chave de API")
struct KeyedUsageProviderTests {
    let clock = TestClock()

    /// A made-up service with an international and a mainland host, answering `{"used": <percent>}`
    /// on `/usage` and its balance as plain text on `/balance`.
    private func service(errorInBody: @escaping @Sendable (Data) -> ProviderIssue.Kind? = { _ in nil }) -> KeyedService {
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
            read: { main, extras, _ in
                guard let used = JSON.object(main).flatMap({ JSON.double($0["used"]) }) else { return nil }
                let balance = extras.first.flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) }
                return KeyedReading(
                    windows: [UsageWindow(id: "w", title: "Mensal", usedPercent: used)],
                    details: balance.map { [DetailRow(label: "Saldo", value: $0)] } ?? []
                )
            },
            errorInBody: errorInBody
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
        #expect(snapshot.details == [DetailRow(label: "Saldo", value: "12,50")])
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
        let refusing = service { _ in .unauthorized }
        let http = MockHTTPClient { [self] in try answer($0, global: 200, china: 200) }
        #expect(await provider(http, service: refusing).snapshot(previous: nil).issue == .unauthorized)
        #expect(http.requests.count == 2)  // tried both regions

        let throttled = MockHTTPClient { [self] in try answer($0, global: 200, china: 200) }
        let keyed = provider(throttled, service: service { _ in .rateLimited })
        #expect(await keyed.snapshot(previous: nil).issue == .rateLimited)
        _ = await keyed.snapshot(previous: nil, reason: .manual)
        #expect(throttled.requests.count == 1)  // the pause holds, even for the button
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
}
