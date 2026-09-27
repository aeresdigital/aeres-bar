import AERESBarCore
import AppKit
import SwiftUI

/// The panel's first row: one ring per provider, in the style of the Apple Watch activity rings,
/// with the provider's mark inside and the percentage below. Clicking a ring opens that
/// provider's details further down.
struct SummaryRow: View {
    let rings: [SummaryRing]
    let expanded: Set<ProviderID>
    let onSelect: @MainActor (ProviderID) -> Void

    /// Up to six rings per row; more providers wrap into balanced rows (seven make 4 + 3).
    static let maxPerRow = 6

    var body: some View {
        let perRow = Self.perRow(for: rings.count)
        let cell = (PanelRootView.width - 16) / CGFloat(max(perRow, 1))
        let diameter = Self.diameter(for: perRow)
        VStack(spacing: 2) {
            ForEach(Array(stride(from: 0, to: rings.count, by: max(perRow, 1))), id: \.self) { start in
                HStack(spacing: 0) {
                    ForEach(rings[start..<min(start + perRow, rings.count)]) { ring in
                        cellButton(ring, diameter: diameter)
                            .frame(width: cell)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func cellButton(_ ring: SummaryRing, diameter: CGFloat) -> some View {
        Button {
            onSelect(ring.provider)
        } label: {
            RingGauge(ring: ring, diameter: diameter)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(expanded.contains(ring.provider) ? 0.07 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ring.description)
        .accessibilityLabel(ring.description)
        .accessibilityHint("Mostra os detalhes do provedor")
    }

    /// Rings per row: all in one row up to six, then as even as possible.
    static func perRow(for count: Int) -> Int {
        guard count > maxPerRow else { return max(count, 1) }
        let rows = (count + maxPerRow - 1) / maxPerRow
        return (count + rows - 1) / rows
    }

    /// As big as the Apple Watch rings allow while a full row still shares the panel's width.
    static func diameter(for perRow: Int) -> CGFloat {
        let cell = (PanelRootView.width - 16) / CGFloat(max(perRow, 1))
        return min(52, max(34, cell - 18))
    }
}

/// One ring: a gray track and an arc from 12 o'clock, clockwise, green until 80%, then orange,
/// and red from 95%, like the menu bar number.
struct RingGauge: View {
    let ring: SummaryRing
    let diameter: CGFloat

    private var tint: Color {
        ring.alert.map { Color(nsColor: BrandPalette.color(for: $0)) } ?? Color(nsColor: .systemGreen)
    }

    var body: some View {
        let lineWidth = (diameter * 0.14).rounded()
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(Color.primary.opacity(0.13), lineWidth: lineWidth)
                if let fraction = ring.fraction, fraction > 0 {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: fraction)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.5), value: fraction)
                }
                BrandLogo(provider: ring.provider, tint: .primary)
                    .frame(width: diameter * 0.4, height: diameter * 0.4)
            }
            .frame(width: diameter, height: diameter)
            Text(ring.text)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(ring.alert == nil ? Color.primary : tint)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
    }
}
