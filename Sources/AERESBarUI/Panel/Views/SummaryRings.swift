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

    var body: some View {
        let diameter = Self.diameter(for: rings.count)
        HStack(spacing: 0) {
            ForEach(rings) { ring in
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// As big as the Apple Watch rings allow while six still share the panel's width.
    static func diameter(for count: Int) -> CGFloat {
        let cell = (PanelRootView.width - 16) / CGFloat(max(count, 1))
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
