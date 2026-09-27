import Foundation

/// Adds up token usage from Codex rollouts (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) and
/// remembers the latest `rate_limits` logged, used when the API is unreachable.
///
/// Newer Codex versions log one `token_usage_record` per response; older ones only log
/// `token_count` events (often duplicated). A file with records ignores its `token_count` events.
/// Not thread-safe: owned by ``CodexProvider``.
final class CodexLogScanner {
    struct RateLimitSample {
        var time: Date
        var windows: [UsageWindow]
        var plan: String?
    }

    struct Tag {
        var file: String
        var fromRecord: Bool
    }

    private static let horizon: TimeInterval = 8 * 86_400
    private static let needles = [Array(#""token_usage_record""#.utf8), Array(#""token_count""#.utf8)]

    private let home: URL
    private let reader = JSONLTailReader()
    private var ledger = TokenLedger<Tag>()
    private var filesWithRecords = Set<String>()
    private(set) var latestRateLimits: RateLimitSample?

    init(home: URL) {
        self.home = home
    }

    func update(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.horizon)
        var seen = Set<String>()
        for folder in ["sessions", "archived_sessions"] {
            let root = home.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            for file in RecentFiles.jsonl(under: root, modifiedAfter: cutoff, namePrefix: "rollout-") {
                seen.insert(file.path)
                reader.readNewLines(at: file.path, fileSize: file.size, needles: Self.needles) { line in
                    ingest(line, file: file.path)
                }
            }
        }
        reader.prune(keeping: seen)
        ledger.prune(before: cutoff.timeIntervalSince1970)
        filesWithRecords.formIntersection(seen)
    }

    func summary(now: Date, calendar: Calendar, sessionStart: Date?, weekStart: Date?) -> TokenSummary {
        let files = filesWithRecords
        return ledger.summary(now: now, calendar: calendar, sessionStart: sessionStart, weekStart: weekStart) { tag in
            tag.fromRecord || !files.contains(tag.file)
        }
    }

    private func ingest(_ line: UnsafeRawBufferPointer, file: String) {
        guard let object = JSON.object(Data(line)),
            let payload = JSON.dict(object["payload"]),
            let time = Timestamp.parse(object["timestamp"] as? String)
        else { return }
        let type = object["type"] as? String

        if type == "token_usage_record", let usage = JSON.dict(payload["usage"]) {
            let key = JSON.string(payload["response_id"]) ?? "\(file)#\(JSON.int(object["ordinal"]))"
            ledger.record(key, at: time.timeIntervalSince1970, counts: Self.counts(usage), tag: Tag(file: file, fromRecord: true))
            filesWithRecords.insert(file)
            return
        }

        guard type == "event_msg", payload["type"] as? String == "token_count" else { return }
        if let info = JSON.dict(payload["info"]),
            let last = JSON.dict(info["last_token_usage"]),
            let total = JSON.dict(info["total_token_usage"])
        {
            // The same totals are often logged twice; the running total identifies each step.
            let key = "\(file)#\(JSON.int(total["total_tokens"]))"
            if !ledger.contains(key) {
                ledger.record(key, at: time.timeIntervalSince1970, counts: Self.counts(last), tag: Tag(file: file, fromRecord: false))
            }
        }
        if let rateLimits = JSON.dict(payload["rate_limits"]), time > (latestRateLimits?.time ?? .distantPast) {
            let windows = CodexUsageParser.windows(fromLog: rateLimits, loggedAt: time)
            if !windows.isEmpty {
                latestRateLimits = RateLimitSample(time: time, windows: windows, plan: JSON.string(rateLimits["plan_type"]))
            }
        }
    }

    /// OpenAI counts cached input inside `input_tokens`; split it out so totals are not doubled.
    static func counts(_ usage: [String: Any]) -> TokenCounts {
        let input = JSON.int(usage["input_tokens"])
        let cached = JSON.int(usage["cached_input_tokens"])
        let cacheWrite = JSON.int(usage["cache_write_input_tokens"])
        return TokenCounts(
            input: max(0, input - cached - cacheWrite),
            output: JSON.int(usage["output_tokens"]),
            cacheRead: cached,
            cacheWrite: cacheWrite,
            requests: 1
        )
    }
}
