import AppKit
import SwiftUI
import Testing

@testable import AERESBarCore
@testable import AERESBarUI

@Suite("Anéis do resumo")
@MainActor
struct SummaryRingsTests {
    /// Renders one ring at 2× and returns the color at a point given in points from the ring's centre.
    private func sampler(_ ring: SummaryRing, diameter: CGFloat = 52) throws -> (CGFloat, CGFloat) -> NSColor {
        let renderer = ImageRenderer(content: RingGauge(ring: ring, diameter: diameter).environment(\.colorScheme, .light))
        renderer.scale = 2
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        let centre = CGPoint(x: CGFloat(rep.pixelsWide) / 4, y: diameter / 2)  // the ring sits at the top, centred
        return { dx, dy in
            let color = rep.colorAt(x: Int((centre.x + dx) * 2), y: Int((centre.y + dy) * 2))
            return color?.usingColorSpace(.sRGB) ?? .clear
        }
    }

    private func ring(_ fraction: Double?, alert: AlertLevel? = nil) -> SummaryRing {
        SummaryRing(provider: .claude, fraction: fraction, text: "50%", alert: alert, description: "Claude Code")
    }

    @Test("O arco sai das 12 h no sentido horário, em verde; o resto é só o trilho")
    func halfRing() throws {
        let color = try sampler(ring(0.5))
        let radius: CGFloat = 26 - 3.5  // the stroke's middle: 7 pt wide, inside the 52 pt ring
        let right = color(radius, 0)  // 3 o'clock: inside the arc
        #expect(right.alphaComponent > 0.9)
        #expect(right.greenComponent > right.redComponent + 0.2 && right.greenComponent > right.blueComponent + 0.2)
        let left = color(-radius, 0)  // 9 o'clock: the track only
        #expect(left.alphaComponent < 0.3)
        #expect(color(0, radius).alphaComponent > 0.9)  // 6 o'clock: where half an arc ends, round cap included
    }

    @Test("Alerta pinta o anel de vermelho; sem dados, fica só o trilho")
    func alertAndEmpty() throws {
        let critical = try sampler(ring(1, alert: .critical))(-(26 - 3.5), 0)
        #expect(critical.redComponent > critical.greenComponent + 0.3)
        #expect(critical.alphaComponent > 0.9)

        let empty = try sampler(ring(nil))(26 - 3.5, 0)
        #expect(empty.alphaComponent < 0.3)
    }

    @Test("Até seis anéis por linha; mais que isso quebra em linhas equilibradas")
    func rows() {
        #expect([1, 5, 6, 7, 11, 12, 13].map(SummaryRow.perRow) == [1, 5, 6, 4, 6, 6, 5])
        #expect(SummaryRow.perRow(for: 0) == 1)
    }

    @Test("Painel mais alto que a tela rola abaixo do cabeçalho")
    func scrollsWhenTall() async throws {
        let temporary = try TemporarySettings()
        defer { temporary.remove() }
        let store = DemoData.store()
        await store.refreshAllAndWait()
        func height(limit: CGFloat) -> CGFloat {
            let state = PanelState()
            state.maxScrollHeight = limit
            let view = PanelRootView(store: store, settings: temporary.settings, state: state, actions: PanelActions())
            return ImageRenderer(content: view).nsImage?.size.height ?? 0
        }
        let full = height(limit: .infinity)
        let capped = height(limit: 200)
        #expect(full > 500)
        #expect(capped < 280)  // the header plus the 200 pt the content may take
        #expect(capped > 200)
    }

    @Test("Os anéis encolhem para caber seis na largura do painel")
    func diameters() {
        #expect(SummaryRow.diameter(for: 3) == 52)
        #expect(SummaryRow.diameter(for: 6) == 46)
        #expect(SummaryRow.diameter(for: 12) == 34)
        #expect(SummaryRow.diameter(for: 0) == 52)
    }

    @Test("A linha de anéis aparece no topo do painel e some sem provedores com limites")
    func rowInPanel() async throws {
        let temporary = try TemporarySettings()
        defer { temporary.remove() }
        func height(_ snapshots: [ProviderSnapshot]) async -> CGFloat {
            let store = UsageStore(providers: snapshots.map(StaticProvider.init))
            await store.refreshAllAndWait()
            let view = PanelRootView(store: store, settings: temporary.settings, state: PanelState(), actions: PanelActions())
            return ImageRenderer(content: view).nsImage?.size.height ?? 0
        }
        let limits = [UsageWindow(id: "w", title: "Semanal", usedPercent: 30, windowSeconds: 604_800)]
        let withRing = await height([ProviderSnapshot(provider: .claude, status: .ok, windows: limits, limitsUpdatedAt: Date())])
        let withoutRing = await height([ProviderSnapshot(provider: .claude, status: .ok, limitsUpdatedAt: Date())])
        // The ring row (about 85 pt) comes on top of the one-line difference in the section below.
        #expect(withRing - withoutRing > 60)
    }
}
