import AERESBarCore
import SwiftUI

struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                if clamped > 0 {
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(6, proxy.size.width * clamped))
                }
            }
        }
        .frame(height: 6)
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

struct StatusBadge: View {
    let status: SnapshotStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(UsagePresentation.statusBadge(for: status))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .ok: .green
        case .stale: .yellow
        case .error: .orange
        case .notInstalled, .loading: .gray
        }
    }
}

struct Notice: View {
    let text: String
    let isProblem: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isProblem ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(isProblem ? Color.orange : Color.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Lendo limites…")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}
