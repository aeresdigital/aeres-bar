import Foundation
import Testing

@testable import AERESBarCore

@Suite("Formatação pt-BR")
struct FormattingTests {
    @Test(
        "Contagem de tokens compacta",
        arguments: [
            (0, "0"), (999, "999"), (1_000, "1K"), (27_802, "27,8K"), (229_000, "229K"),
            (999_600, "1M"), (15_236_204, "15,2M"), (3_556_861_813, "3,6B"),
        ]
    )
    func tokens(count: Int, expected: String) {
        #expect(Formatting.tokens(count) == expected)
    }

    @Test(
        "Porcentagem nunca parece vazia ou cheia antes da hora",
        arguments: [(0.0, "0%"), (0.4, "<1%"), (73.5, "74%"), (99.6, "99%"), (100, "100%"), (140, "100%"), (-5, "0%")]
    )
    func percent(value: Double, expected: String) {
        #expect(Formatting.percent(value) == expected)
    }

    @Test("Contagem regressiva")
    func countdowns() {
        #expect(Formatting.countdown(45) == "45s")
        #expect(Formatting.countdown(12 * 60 + 5) == "12min")
        #expect(Formatting.countdown(3 * 3_600) == "3h")
        #expect(Formatting.countdown(4 * 3_600 + 37 * 60) == "4h 37min")
        #expect(Formatting.countdown(2 * 86_400) == "2d")
        #expect(Formatting.countdown(3 * 86_400 + 12 * 3_600 + 59) == "3d 12h")
        #expect(Formatting.countdown(-10) == "0s")
        #expect(Formatting.compactCountdown(4 * 3_600 + 7 * 60) == "4h07")
        #expect(Formatting.compactCountdown(3 * 86_400 + 13 * 3_600) == "3d13h")
        #expect(Formatting.compactCountdown(45 * 60) == "45m")
        #expect(Formatting.compactCountdown(30) == "30s")
    }

    @Test("Momento relativo ao dia")
    func moments() throws {
        let calendar = Calendar.saoPaulo
        let now = try #require(iso("2026-09-27T03:30:00Z"))  // 00:30 in São Paulo
        #expect(Formatting.moment(try #require(iso("2026-09-27T08:10:00Z")), now: now, calendar: calendar) == "hoje às 05:10")
        #expect(Formatting.moment(try #require(iso("2026-09-28T06:00:00Z")), now: now, calendar: calendar) == "amanhã às 03:00")
        #expect(Formatting.moment(try #require(iso("2026-09-27T01:15:00Z")), now: now, calendar: calendar) == "ontem às 22:15")
        #expect(Formatting.moment(try #require(iso("2026-09-30T16:00:00Z")), now: now, calendar: calendar) == "qua. 30/09 às 13:00")
    }

    @Test("Tempo decorrido")
    func relative() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Formatting.relative(now.addingTimeInterval(-3), now: now) == "agora")
        #expect(Formatting.relative(now.addingTimeInterval(-42), now: now) == "há 42 s")
        #expect(Formatting.relative(now.addingTimeInterval(-600), now: now) == "há 10 min")
        #expect(Formatting.relative(now.addingTimeInterval(-7_200), now: now) == "há 2 h")
        #expect(Formatting.relative(now.addingTimeInterval(-3 * 86_400), now: now) == "há 3 d")
    }

    @Test("Moeda")
    func money() {
        #expect(Formatting.money(110, currency: "BRL").contains("110,00"))
    }
}

@Suite("Timestamps RFC 3339")
struct TimestampTests {
    @Test("Variações de fuso e fração")
    func variants() throws {
        let expected = Date(timeIntervalSince1970: 1_790_496_600)
        #expect(Timestamp.parse("2026-09-27T08:10:00Z") == expected)
        #expect(Timestamp.parse("2026-09-27T08:10:00+00:00") == expected)
        #expect(Timestamp.parse("2026-09-27T05:10:00-03:00") == expected)
        #expect(Timestamp.parse("2026-09-27T13:40:00+0530") == expected)
        let precise = try #require(Timestamp.parse("2026-09-27T08:10:00.036849+00:00"))
        #expect(abs(precise.timeIntervalSince1970 - 1_790_496_600.036849) < 1e-5)
    }

    @Test("Rejeita entradas inválidas", arguments: [nil, "", "ontem", "2026-13-01T00:00:00Z", "2026-09-27 08:10"])
    func invalid(input: String?) {
        #expect(Timestamp.parse(input) == nil)
    }
}
