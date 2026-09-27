import Foundation
import Testing

@testable import AERESBarCore

@Suite("Leitura incremental de JSONL")
struct JSONLTailReaderTests {
    private func collect(_ reader: JSONLTailReader, _ file: URL, needles: [[UInt8]] = [Array("{".utf8)]) throws -> [String] {
        let size = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64)
        var lines: [String] = []
        reader.readNewLines(at: file.path, fileSize: size, needles: needles) { lines.append(String(decoding: $0, as: UTF8.self)) }
        return lines
    }

    @Test("Só entrega linhas completas e novas")
    func incremental() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = try folder.write("{\"a\":1}\n{\"b\":2}\n{\"partial\"", to: "log.jsonl")
        let reader = JSONLTailReader(chunkSize: 5)  // tiny chunks exercise line reassembly

        #expect(try collect(reader, file) == [#"{"a":1}"#, #"{"b":2}"#])
        #expect(try collect(reader, file).isEmpty)

        try folder.append(":3}\n{\"c\":4}\n", to: "log.jsonl")
        #expect(try collect(reader, file) == [#"{"partial":3}"#, #"{"c":4}"#])
    }

    @Test("Filtra por agulha e recomeça se o arquivo encolher")
    func needlesAndTruncation() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = try folder.write("{\"type\":\"user\"}\n{\"type\":\"assistant\"}\n", to: "log.jsonl")
        let reader = JSONLTailReader()
        #expect(try collect(reader, file, needles: [Array("assistant".utf8)]) == [#"{"type":"assistant"}"#])

        try "{\"type\":\"assistant\",\"n\":2}\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try collect(reader, file, needles: [Array("assistant".utf8)]) == [#"{"type":"assistant","n":2}"#])
    }

    @Test("Linhas muito maiores que o buffer, e quebras exatamente no fim de uma leitura")
    func longLinesAndBoundaries() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let long = "{\"payload\":\"" + String(repeating: "x", count: 10_000) + "\"}"
        let file = try folder.write("{\"a\":1}\n\(long)\n{\"b\":2}\n", to: "log.jsonl")
        let reader = JSONLTailReader(chunkSize: 8)  // "{"a":1}\n" fills the first read exactly

        let lines = try collect(reader, file)
        #expect(lines.count == 3)
        #expect(lines.first == #"{"a":1}"#)
        #expect(lines.dropFirst().first == long)
        #expect(lines.last == #"{"b":2}"#)

        try folder.append("{\"c\":3}\n", to: "log.jsonl")
        #expect(try collect(reader, file) == [#"{"c":3}"#])
    }

    @Test("Arquivo que sumiu é ignorado")
    func missingFile() {
        let reader = JSONLTailReader()
        var lines = 0
        reader.readNewLines(at: "/nonexistent/\(UUID().uuidString).jsonl", fileSize: 100, needles: [Array("{".utf8)]) { _ in lines += 1 }
        #expect(lines == 0)
    }
}

@Suite("Leitura rasa de objetos JSON")
struct ShallowJSONTests {
    @Test("Encontra membros de primeiro nível sem se confundir com conteúdo aninhado")
    func members() {
        let json =
            #"{"message":{"content":[{"type":"text","text":"{\"type\":\"assistant\"}"}],"usage":{"input_tokens":3}},"type":"assistant","n":42,"ok":true}"#
        var found: [String: String] = [:]
        Array(json.utf8).withUnsafeBytes { buffer in
            ShallowJSON.members(of: buffer, objectAt: 0) { key, value in
                found[Bytes.string(buffer, key)] = Bytes.string(buffer, value)
            }
        }
        #expect(found["type"] == #""assistant""#)
        #expect(found["n"] == "42")
        #expect(found["ok"] == "true")
        #expect(found["message"]?.hasSuffix(#""usage":{"input_tokens":3}}"#) == true)
    }

    @Test("Utilitários de bytes")
    func bytes() {
        Array("abc-needle-xyz".utf8).withUnsafeBytes { buffer in
            #expect(Bytes.find(buffer, Array("needle".utf8)) == 4)
            #expect(Bytes.find(buffer, Array("zzz".utf8)) == nil)
            #expect(Bytes.contains(buffer, Array("xyz".utf8)))
            #expect(Bytes.equals(buffer, 4..<10, Array("needle".utf8)))
            #expect(ShallowJSON.stringContents(buffer, 0..<3) == nil)
        }
    }
}

@Suite("Tokens do Claude Code nos logs")
struct ClaudeLogScannerTests {
    private func stamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    private func line(
        id: String, request: String, at date: Date, input: Int, output: Int, cacheRead: Int, cacheWrite: Int,
        content: String = #"[{"type":"text","text":"oi"}]"#
    ) -> String {
        #"{"parentUuid":"p","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"\#(id)","type":"message","role":"assistant","content":\#(content),"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"iterations":[{"input_tokens":999999,"output_tokens":999999}]}},"requestId":"\#(request)","type":"assistant","uuid":"u","timestamp":"\#(stamp(date))"}"#
            + "\n"
    }

    @Test("Deduplica blocos da mesma resposta, ignora outros tipos e lê só o que é novo")
    func scan() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let now = Date()
        // A tool payload with its own "usage" key and escaped JSON must not confuse the scanner.
        let tricky =
            #"[{"type":"tool_use","id":"toolu_1","name":"X","input":{"usage":{"input_tokens":5},"text":"{\"type\":\"assistant\",\"usage\":{}}"}}]"#
        try folder.write(
            #"{"type":"user","message":{"role":"user","content":"oi"},"timestamp":"\#(stamp(now))"}"# + "\n"
                + line(id: "msg_1", request: "req_1", at: now, input: 10, output: 100, cacheRead: 1_000, cacheWrite: 50)
                + line(id: "msg_1", request: "req_1", at: now, input: 10, output: 100, cacheRead: 1_000, cacheWrite: 50, content: tricky)
                + line(
                    id: "msg_old", request: "req_old", at: now.addingTimeInterval(-10 * 86_400), input: 7, output: 7, cacheRead: 7,
                    cacheWrite: 7),
            to: "projects/-Users-me-app/session.jsonl"
        )
        let scanner = ClaudeLogScanner(roots: [folder.url.appendingPathComponent("projects")])
        #expect(scanner.hasLogs)
        scanner.update(now: now)
        var summary = scanner.summary(now: now, calendar: .current, sessionStart: now.addingTimeInterval(-3_600), weekStart: nil)
        #expect(summary.today == TokenCounts(input: 10, output: 100, cacheRead: 1_000, cacheWrite: 50, requests: 1))
        #expect(summary.week.total == 1_160)
        #expect(summary.session?.total == 1_160)
        #expect(summary.weekIsRolling)

        let later = now.addingTimeInterval(1)
        try folder.append(
            line(id: "msg_2", request: "req_2", at: later, input: 1, output: 2, cacheRead: 3, cacheWrite: 4),
            to: "projects/-Users-me-app/session.jsonl")
        scanner.update(now: later)
        summary = scanner.summary(now: later, calendar: .current, sessionStart: nil, weekStart: nil)
        #expect(summary.today.requests == 2)
        #expect(summary.today.total == 1_170)
        #expect(summary.session == nil)
        #expect(summary.lastActivity.map { abs($0.timeIntervalSince(later)) < 0.01 } == true)
    }

    @Test("Sem pasta de logs")
    func missingRoot() {
        let scanner = ClaudeLogScanner(roots: [URL(fileURLWithPath: "/nonexistent/projects")])
        #expect(!scanner.hasLogs)
        scanner.update(now: Date())
        #expect(scanner.summary(now: Date(), calendar: .current, sessionStart: nil, weekStart: nil).isEmpty)
    }
}

@Suite("Tokens do Codex nos rollouts")
struct CodexLogScannerTests {
    @Test("Prefere registros por resposta e guarda o último limite")
    func scan() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let now = Date()
        let t1 = now.addingTimeInterval(-120).formatted(.iso8601)
        let t2 = now.addingTimeInterval(-60).formatted(.iso8601)

        // Newer CLI: per-response records plus token_count events for the same turns.
        try folder.write(
            [
                #"{"timestamp":"\#(t1)","type":"token_usage_record","payload":{"response_id":"resp_a","usage":{"input_tokens":1000,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":50,"total_tokens":1050}}}"#,
                #"{"timestamp":"\#(t1)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1050},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50}},"rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1790000000},"plan_type":"plus"}}}"#,
                #"{"timestamp":"\#(t2)","type":"token_usage_record","payload":{"response_id":"resp_b","usage":{"input_tokens":2000,"cached_input_tokens":0,"output_tokens":10,"total_tokens":2010}}}"#,
            ].joined(separator: "\n") + "\n",
            to: "sessions/2026/09/27/rollout-new.jsonl"
        )
        // Older CLI: only token_count, logged twice.
        let legacy =
            #"{"timestamp":"\#(t2)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":300},"last_token_usage":{"input_tokens":200,"cached_input_tokens":100,"output_tokens":100}},"rate_limits":{"primary":{"used_percent":30.0,"window_minutes":300,"resets_in_seconds":600}}}}"#
        try folder.write(legacy + "\n" + legacy + "\n", to: "sessions/2026/09/27/rollout-old.jsonl")
        try folder.write(#"{"type":"token_count"}"# + "\n", to: "sessions/2026/09/27/notes.jsonl")  // not a rollout

        let scanner = CodexLogScanner(home: folder.url)
        scanner.update(now: now)
        let summary = scanner.summary(now: now, calendar: .current, sessionStart: nil, weekStart: nil)
        #expect(summary.today.requests == 3)
        #expect(summary.today.cacheRead == 900)
        #expect(summary.today.input == 200 + 2_000 + 100)
        #expect(summary.today.output == 160)
        #expect(summary.today.total == 1_050 + 2_010 + 300)

        let latest = try #require(scanner.latestRateLimits)
        #expect(latest.windows.first?.usedPercent == 30)
        #expect(latest.windows.first?.title == "Sessão (5h)")
    }
}
