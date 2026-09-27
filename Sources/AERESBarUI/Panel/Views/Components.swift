import AERESBarCore
import SwiftUI

struct UsageBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                if clamped > 0 {
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(height, proxy.size.width * clamped))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct PlanBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct Notice: View {
    let text: String
    let isProblem: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: isProblem ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(isProblem ? Color.orange : Color.secondary)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Lendo limites…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// A borderless toolbar button that highlights on hover.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: @MainActor () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

/// "Atualizar agora": a native spinner replaces the icon while refreshing, and the button is
/// disabled meanwhile. (A rotating icon animated with `repeatForever` misbehaved inside a panel
/// that redraws every second and resizes with its content.)
struct RefreshButton: View {
    let isRefreshing: Bool
    let action: @MainActor () -> Void

    var body: some View {
        ZStack {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                    .accessibilityLabel("Atualizando")
            } else {
                IconButton(symbol: "arrow.clockwise", help: "Atualizar agora", action: action)
            }
        }
        .frame(width: 26, height: 22)
        .disabled(isRefreshing)
        .animation(nil, value: isRefreshing)
    }
}
