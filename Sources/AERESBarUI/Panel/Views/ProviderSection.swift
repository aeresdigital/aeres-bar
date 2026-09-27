import AERESBarCore
import AppKit
import SwiftUI

/// One provider in the panel. Collapsed: one line per limit plus today's tokens.
/// Expanded (click the header): countdowns in full, the token table and every detail.
struct ProviderSection: View {
    let provider: ProviderID
    let snapshot: ProviderSnapshot?
    let now: Date
    let isExpanded: Bool
    let onToggle: @MainActor () -> Void

    private var accent: Color { BrandPalette.accent(for: provider) }

    var body: some View {
        let windows = snapshot?.windows ?? []
        VStack(alignment: .leading, spacing: 7) {
            header(windows: windows)

            if let message = snapshot?.message {
                Notice(text: message, isProblem: snapshot?.status == .error)
            }
            if provider == .antigravity, snapshot?.issue == .sourceUnavailable,
                let application = AntigravityInstallation().applicationURL
            {
                Button("Abrir o Antigravity") {
                    NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration())
                }
                .controlSize(.small)
            }
            if windows.isEmpty, snapshot == nil || snapshot?.status == .loading {
                LoadingRow()
            }

            if isExpanded {
                ForEach(windows) { window in
                    WindowRow(window: window, accent: accent, now: now)
                }
                if let tokens = snapshot?.tokens, !tokens.isEmpty {
                    TokenTable(tokens: tokens, now: now)
                }
                if let details = snapshot?.details, !details.isEmpty {
                    DetailList(rows: details)
                }
                if let models = snapshot?.models, !models.isEmpty {
                    ModelList(models: models, now: now)
                }
                if let source = snapshot?.source {
                    Text("Fonte: \(source)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                ForEach(windows) { window in
                    CompactWindowRow(window: window, accent: accent, now: now)
                }
                if let line = snapshot?.tokens.flatMap(UsagePresentation.tokenLine) {
                    Text(line)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                if windows.isEmpty, let first = snapshot?.details.first {
                    Text("\(first.label): \(first.value)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func header(windows: [UsageWindow]) -> some View {
        let used = BarPresenter.mostCritical(windows, now: now)?.effectiveUsed(at: now)
        let alert = used.flatMap(AlertLevel.init(usedPercent:))
        return Button(action: onToggle) {
            HStack(spacing: 7) {
                BrandLogo(provider: provider).frame(width: 15, height: 15)
                Text(provider.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if let plan = snapshot?.plan {
                    PlanBadge(text: plan, color: accent)
                }
                if let status = snapshot?.status, status == .stale || status == .error {
                    Text(UsagePresentation.statusBadge(for: status))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if let used {
                    Text(Formatting.percent(used))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(alert.map { Color(nsColor: BrandPalette.color(for: $0)) } ?? .primary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Recolher detalhes" : "Ver detalhes")
        .accessibilityLabel("\(provider.displayName), \(used.map(Formatting.percent) ?? "sem dados")")
        .accessibilityHint(isExpanded ? "Recolhe os detalhes" : "Mostra os detalhes")
    }
}

/// One limit on a single line: name, bar, percentage and time left (full text on hover).
struct CompactWindowRow: View {
    let window: UsageWindow
    let accent: Color
    let now: Date

    var body: some View {
        let used = window.effectiveUsed(at: now)
        let alertColor = AlertLevel(usedPercent: used).map { Color(nsColor: BrandPalette.color(for: $0)) }
        HStack(spacing: 8) {
            Text(window.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            UsageBar(fraction: used / 100, tint: alertColor ?? accent, height: 5)
            Text(Formatting.percent(used))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(alertColor ?? .primary)
                .frame(width: 36, alignment: .trailing)
            Text(UsagePresentation.compactReset(for: window, now: now))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .trailing)
        }
        .help(UsagePresentation.resetDescription(for: window, now: now))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsagePresentation.accessibilityLabel(for: window, now: now))
    }
}
