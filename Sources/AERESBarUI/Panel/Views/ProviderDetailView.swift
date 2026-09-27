import AERESBarCore
import AppKit
import SwiftUI

/// Everything about one provider: limits with countdowns, tokens and extra details.
struct ProviderDetailView: View {
    let provider: ProviderID
    let snapshot: ProviderSnapshot?
    let now: Date

    private var accent: Color { BrandPalette.accent(for: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let message = snapshot?.message {
                Notice(text: message, isProblem: snapshot?.status != .stale)
            }
            if provider == .antigravity, snapshot?.issue == .sourceUnavailable,
                let application = AntigravityInstallation().applicationURL
            {
                Button("Abrir o Antigravity") {
                    NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration())
                }
                .controlSize(.small)
            }

            let windows = snapshot?.windows ?? []
            if !windows.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(windows) { window in
                        WindowRow(window: window, accent: accent, now: now)
                    }
                }
            } else if snapshot == nil || snapshot?.status == .loading {
                LoadingRow()
            }

            if let tokens = snapshot?.tokens {
                Divider().opacity(0.5)
                if tokens.isEmpty {
                    Text("Nenhum token registrado nos logs dos últimos 7 dias.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    TokenTable(tokens: tokens, now: now)
                }
            }

            if let details = snapshot?.details, !details.isEmpty {
                Divider().opacity(0.5)
                DetailList(rows: details)
            }

            if let models = snapshot?.models, !models.isEmpty {
                Divider().opacity(0.5)
                ModelList(models: models, now: now)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandLogo(provider: provider)
                .padding(7)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.displayName).font(.system(size: 14, weight: .semibold))
                    if let plan = snapshot?.plan {
                        PlanBadge(text: plan, color: accent)
                    }
                }
                Text(UsagePresentation.statusLine(for: snapshot, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            StatusBadge(status: snapshot?.status ?? .loading)
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let accent: Color
    let now: Date

    var body: some View {
        let used = window.effectiveUsed(at: now)
        let alert = AlertLevel(usedPercent: used)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(window.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Formatting.percent(used))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(alert.map { Color(nsColor: BrandPalette.color(for: $0)) } ?? .primary)
                Text("usado")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            UsageBar(fraction: used / 100, tint: alert.map { Color(nsColor: BrandPalette.color(for: $0)) } ?? accent)
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .semibold))
                Text(UsagePresentation.resetDescription(for: window, now: now))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            if let subtitle = window.subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsagePresentation.accessibilityLabel(for: window, now: now))
    }
}

struct TokenTable: View {
    let tokens: TokenSummary
    let now: Date

    var body: some View {
        let columns = UsagePresentation.tokenColumns(for: tokens)
        let rows = UsagePresentation.tokenRows(for: columns)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tokens (logs locais)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = tokens.lastActivity {
                    Text("último uso \(Formatting.relative(last, now: now))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text(" ").gridColumnAlignment(.leading)
                    ForEach(columns) { column in
                        Text(column.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(rows) { metric in
                    GridRow {
                        Text(metric.label)
                            .font(.system(size: 11.5, weight: metric.isEmphasized ? .semibold : .regular))
                            .foregroundStyle(metric.isEmphasized ? .primary : .secondary)
                        ForEach(columns) { column in
                            Text(Formatting.tokens(metric.value(in: column.counts)))
                                .font(.system(size: 11.5, weight: metric.isEmphasized ? .semibold : .regular).monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}

struct DetailList: View {
    let rows: [DetailRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.system(size: 11.5))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

struct ModelList: View {
    let models: [ModelQuota]
    let now: Date

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Cota por modelo (\(models.count))")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(models) { model in
                    HStack(spacing: 8) {
                        Text(model.label)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(UsagePresentation.remainingDescription(for: model, now: now))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
