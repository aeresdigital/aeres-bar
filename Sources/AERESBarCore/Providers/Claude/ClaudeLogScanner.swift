import Foundation

/// Adds up token usage from Claude Code transcripts (`~/.claude/projects/**/*.jsonl`).
///
/// Only files touched in the last 8 days are read, incrementally. Each assistant response is
/// logged once per content block with the same usage, so events are keyed by message id and
/// request id. Not thread-safe: owned by ``ClaudeProvider``.
final class ClaudeLogScanner {
    private static let horizon: TimeInterval = 8 * 86_400
    private static let needles = [Array(#""type":"assistant""#.utf8)]
    private static let keyType = Array("type".utf8)
    private static let keyTimestamp = Array("timestamp".utf8)
    private static let keyRequestID = Array("requestId".utf8)
    private static let keyMessage = Array("message".utf8)
    private static let keyID = Array("id".utf8)
    private static let keyUsage = Array("usage".utf8)
    private static let valueAssistant = Array(#""assistant""#.utf8)

    private let roots: [URL]
    private let reader = JSONLTailReader()
    private var ledger = TokenLedger<Void>()

    init(roots: [URL]) {
        self.roots = roots
    }

    var hasLogs: Bool {
        roots.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func update(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.horizon)
        var seen = Set<String>()
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            for file in RecentFiles.jsonl(under: root, modifiedAfter: cutoff) {
                seen.insert(file.path)
                reader.readNewLines(at: file.path, fileSize: file.size, needles: Self.needles) { line in
                    ingest(line)
                }
            }
        }
        reader.prune(keeping: seen)
        ledger.prune(before: cutoff.timeIntervalSince1970)
    }

    func summary(now: Date, calendar: Calendar, sessionStart: Date?, weekStart: Date?) -> TokenSummary {
        ledger.summary(now: now, calendar: calendar, sessionStart: sessionStart, weekStart: weekStart)
    }

    private func ingest(_ line: UnsafeRawBufferPointer) {
        var isAssistant = false
        var timestamp: Range<Int>?
        var requestID: Range<Int>?
        var message: Range<Int>?
        ShallowJSON.members(of: line, objectAt: 0) { key, value in
            if Bytes.equals(line, key, Self.keyType) {
                isAssistant = Bytes.equals(line, value, Self.valueAssistant)
            } else if Bytes.equals(line, key, Self.keyTimestamp) {
                timestamp = value
            } else if Bytes.equals(line, key, Self.keyRequestID) {
                requestID = value
            } else if Bytes.equals(line, key, Self.keyMessage) {
                message = value
            }
        }
        guard isAssistant, let message, let timestamp, timestamp.count > 2,
            let date = Timestamp.parse(UnsafeRawBufferPointer(rebasing: line[(timestamp.lowerBound + 1)..<(timestamp.upperBound - 1)]))
        else { return }

        var messageID: Range<Int>?
        var usage: Range<Int>?
        ShallowJSON.members(of: line, objectAt: message.lowerBound) { key, value in
            if Bytes.equals(line, key, Self.keyID) {
                messageID = value
            } else if Bytes.equals(line, key, Self.keyUsage) {
                usage = value
            }
        }
        guard let usage, let fields = JSON.object(Bytes.data(line, usage)) else { return }

        let counts = TokenCounts(
            input: JSON.int(fields["input_tokens"]),
            output: JSON.int(fields["output_tokens"]),
            cacheRead: JSON.int(fields["cache_read_input_tokens"]),
            cacheWrite: JSON.int(fields["cache_creation_input_tokens"]),
            requests: 1
        )
        guard counts.total > 0 else { return }

        let idText = messageID.flatMap { ShallowJSON.stringContents(line, $0) } ?? ""
        let requestText = requestID.flatMap { ShallowJSON.stringContents(line, $0) } ?? ""
        let key =
            idText.isEmpty && requestText.isEmpty
            ? "t:\(date.timeIntervalSince1970):\(counts.total)"
            : "\(idText)|\(requestText)"
        ledger.record(key, at: date.timeIntervalSince1970, counts: counts, tag: (), keepLargest: true)
    }
}
