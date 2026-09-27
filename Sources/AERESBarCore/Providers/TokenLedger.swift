import Foundation

/// Token usage events keyed by response, summarised over the periods the panel shows.
/// `Tag` carries provider-specific metadata used to filter events when summarising.
struct TokenLedger<Tag> {
    struct Event {
        var time: TimeInterval
        var counts: TokenCounts
        var tag: Tag
    }

    private(set) var events: [String: Event] = [:]

    /// Stores an event. With `keepLargest`, a repeated key keeps the largest figures seen
    /// (a streamed response is logged once per content block, each with the same usage).
    mutating func record(_ key: String, at time: TimeInterval, counts: TokenCounts, tag: Tag, keepLargest: Bool = false) {
        guard keepLargest, var existing = events[key] else {
            events[key] = Event(time: time, counts: counts, tag: tag)
            return
        }
        existing.counts.input = max(existing.counts.input, counts.input)
        existing.counts.output = max(existing.counts.output, counts.output)
        existing.counts.cacheRead = max(existing.counts.cacheRead, counts.cacheRead)
        existing.counts.cacheWrite = max(existing.counts.cacheWrite, counts.cacheWrite)
        events[key] = existing
    }

    func contains(_ key: String) -> Bool { events[key] != nil }

    mutating func prune(before cutoff: TimeInterval) {
        events = events.filter { $0.value.time >= cutoff }
    }

    /// Totals for today, the running session and the week. Without `weekStart`, the week is the last 7 days.
    func summary(
        now: Date,
        calendar: Calendar,
        sessionStart: Date?,
        weekStart: Date?,
        including include: (Tag) -> Bool = { _ in true }
    ) -> TokenSummary {
        let dayStart = calendar.startOfDay(for: now).timeIntervalSince1970
        let weekFrom = (weekStart ?? now.addingTimeInterval(-7 * 86_400)).timeIntervalSince1970
        let sessionFrom = sessionStart?.timeIntervalSince1970

        var summary = TokenSummary(session: sessionFrom == nil ? nil : TokenCounts(), weekIsRolling: weekStart == nil)
        var latest: TimeInterval = 0
        for event in events.values where include(event.tag) {
            latest = max(latest, event.time)
            if event.time >= dayStart { summary.today.add(event.counts) }
            if event.time >= weekFrom { summary.week.add(event.counts) }
            if let sessionFrom, event.time >= sessionFrom { summary.session?.add(event.counts) }
        }
        summary.lastActivity = latest > 0 ? Date(timeIntervalSince1970: latest) : nil
        return summary
    }
}
