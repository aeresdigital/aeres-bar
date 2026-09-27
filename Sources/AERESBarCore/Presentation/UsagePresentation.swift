import Foundation

/// One column of the token table ("Sessão 5h", "Hoje", "Semana").
public struct TokenColumn: Equatable, Identifiable, Sendable {
    public var title: String
    public var counts: TokenCounts
    public var id: String { title }
}

/// One row of the token table.
public enum TokenMetric: String, CaseIterable, Identifiable, Sendable {
    case total, input, output, cacheRead, cacheWrite, requests

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .total: "Total"
        case .input: "Entrada"
        case .output: "Saída"
        case .cacheRead: "Cache lido"
        case .cacheWrite: "Cache gravado"
        case .requests: "Respostas"
        }
    }

    public var isEmphasized: Bool { self == .total }

    public func value(in counts: TokenCounts) -> Int {
        switch self {
        case .total: counts.total
        case .input: counts.input
        case .output: counts.output
        case .cacheRead: counts.cacheRead
        case .cacheWrite: counts.cacheWrite
        case .requests: counts.requests
        }
    }
}

/// The user-facing texts of the details panel, kept out of the views so they can be tested.
public enum UsagePresentation {
    /// "Renova em 1h 17min · hoje às 05:10", or why there is no countdown.
    public static func resetDescription(for window: UsageWindow, now: Date, calendar: Calendar = .current) -> String {
        if window.notStarted { return "A janela começa a contar no próximo uso" }
        guard let reset = window.resetsAt else { return "Sem horário de renovação informado" }
        if reset <= now {
            return "Renovou \(Formatting.moment(reset, now: now, calendar: calendar)) — aguardando nova leitura"
        }
        return "Renova em \(Formatting.countdown(reset.timeIntervalSince(now))) · "
            + Formatting.moment(reset, now: now, calendar: calendar)
    }

    /// Subtitle of the panel header.
    public static func statusLine(for snapshot: ProviderSnapshot?, now: Date, calendar: Calendar = .current) -> String {
        guard let snapshot else { return "Carregando…" }
        if let updated = snapshot.limitsUpdatedAt {
            if now.timeIntervalSince(updated) < 90 {
                return "Limites lidos \(Formatting.relative(updated, now: now))"
            }
            return "Limites de \(Formatting.moment(updated, now: now, calendar: calendar)) (\(Formatting.relative(updated, now: now)))"
        }
        switch snapshot.status {
        case .loading: return "Carregando…"
        case .notInstalled: return "Não instalado"
        case .ok, .stale, .error: return "Limites ainda não lidos"
        }
    }

    /// Short badge next to the header.
    public static func statusBadge(for status: SnapshotStatus) -> String {
        switch status {
        case .ok: "ao vivo"
        case .stale: "em cache"
        case .error: "sem dados"
        case .notInstalled: "ausente"
        case .loading: "carregando"
        }
    }

    /// Columns of the token table: the running session (if any), today and the week.
    public static func tokenColumns(for summary: TokenSummary) -> [TokenColumn] {
        var columns: [TokenColumn] = []
        if let session = summary.session { columns.append(TokenColumn(title: "Sessão 5h", counts: session)) }
        columns.append(TokenColumn(title: "Hoje", counts: summary.today))
        columns.append(TokenColumn(title: summary.weekIsRolling ? "7 dias" : "Semana", counts: summary.week))
        return columns
    }

    /// Rows worth showing: the total, plus any breakdown with a non-zero value.
    public static func tokenRows(for columns: [TokenColumn]) -> [TokenMetric] {
        TokenMetric.allCases.filter { metric in
            metric.isEmphasized || columns.contains { metric.value(in: $0.counts) > 0 }
        }
    }

    /// "35% livre" for a model quota.
    public static func remainingDescription(for model: ModelQuota, now: Date) -> String {
        guard let fraction = model.remainingFraction else { return "sem cota" }
        if let reset = model.resetsAt, reset <= now { return "100% livre" }
        return "\(Formatting.percent(fraction * 100)) livre"
    }

    /// VoiceOver description of a window row.
    public static func accessibilityLabel(for window: UsageWindow, now: Date) -> String {
        "\(window.title): \(Formatting.percent(window.effectiveUsed(at: now))) usado. \(resetDescription(for: window, now: now))"
    }
}
