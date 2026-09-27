import Foundation

/// Brazilian Portuguese formatting for numbers, durations and dates.
public enum Formatting {
    public static let locale = Locale(identifier: "pt_BR")

    /// "74%"; values between 0 and 1 read "<1%" and between 99 and 100 read "99%",
    /// so nothing looks empty or full before it is.
    public static func percent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        if clamped > 0 && clamped < 1 { return "<1%" }
        if clamped > 99 && clamped < 100 { return "99%" }
        return "\(Int(clamped.rounded()))%"
    }

    /// Short token counts: 1234 → "1,2K", 3_400_000 → "3,4M".
    public static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case ..<1_000: return "\(count)"
        case ..<999_500: return scaled(value / 1_000, suffix: "K")
        case ..<999_500_000: return scaled(value / 1_000_000, suffix: "M")
        default: return scaled(value / 1_000_000_000, suffix: "B")
        }
    }

    private static func scaled(_ value: Double, suffix: String) -> String {
        var text = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        text = text.replacingOccurrences(of: ".", with: ",")
        if text.hasSuffix(",0") { text.removeLast(2) }
        return text + suffix
    }

    /// "R$ 110,00".
    public static func money(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency).locale(locale))
    }

    /// "3d 13h", "1h 17min", "12min", "45s".
    public static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)min" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)min" }
        return "\(total)s"
    }

    /// Tight variant for the menu bar: "3d13h", "1h07", "45m".
    public static func compactCountdown(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return String(format: "%dh%02d", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// "hoje às 05:10", "amanhã às 03:00", "ontem às 22:15", "qua. 30/09 às 13:00".
    public static func moment(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = clock(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return "hoje às \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "amanhã às \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "ontem às \(time)"
        }
        return "\(day(date, calendar: calendar)) às \(time)"
    }

    /// "agora", "há 12 s", "há 3 min", "há 2 h", "há 4 d".
    public static func relative(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 10 { return "agora" }
        if seconds < 60 { return "há \(seconds) s" }
        if seconds < 3_600 { return "há \(seconds / 60) min" }
        if seconds < 86_400 { return "há \(seconds / 3_600) h" }
        return "há \(seconds / 86_400) d"
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: locale,
            timeZone: calendar.timeZone,
            calendar: calendar
        )
        return date.formatted(style)
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(weekday: .abbreviated) \(day: .twoDigits)/\(month: .twoDigits)",
            locale: locale,
            timeZone: calendar.timeZone,
            calendar: calendar
        )
        return date.formatted(style)
    }
}
