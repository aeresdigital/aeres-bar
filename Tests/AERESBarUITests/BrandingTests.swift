import AppKit
import SwiftUI
import Testing

@testable import AERESBarCore
@testable import AERESBarUI

@Suite("Parser de caminhos SVG")
struct SVGPathTests {
    @Test(
        "As três marcas oficiais são lidas e cabem na sua viewBox",
        arguments: [
            (ProviderID.claude, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.codex, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.antigravity, CGRect(x: 0, y: 0, width: 112, height: 112)),
        ])
    func officialMarks(provider: ProviderID, viewBox: CGRect) throws {
        let path = try SVGPath.parse(BrandMark.pathData(for: provider))
        let bounds = path.boundingBoxOfPath
        #expect(!bounds.isEmpty)
        #expect(viewBox.insetBy(dx: -0.5, dy: -0.5).contains(bounds))
        // The mark fills a good part of its canvas.
        #expect(bounds.width > viewBox.width * 0.6)
        #expect(!BrandMark.path(for: provider).isEmpty)
    }

    @Test("Comandos absolutos e relativos, com repetição implícita")
    func basicCommands() throws {
        let absolute = try SVGPath.parse("M0 0 L10 0 10 10 H0 V5 Z")
        #expect(absolute.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 10))
        let relative = try SVGPath.parse("m5 5l10 0 0 10h-10z")
        #expect(relative.boundingBoxOfPath == CGRect(x: 5, y: 5, width: 10, height: 10))
        // Compact numbers: "-.5.25" is -0.5 then 0.25; exponents are numbers, not commands.
        let compact = try SVGPath.parse("M0,0l-.5.25L1e1 2E-1")
        #expect(compact.currentPoint == CGPoint(x: 10, y: 0.2))
    }

    @Test("Curvas cúbicas, quadráticas e suaves")
    func curves() throws {
        let path = try SVGPath.parse("M0 0C0 10 10 10 10 0S20-10 20 0Q25 10 30 0T40 0")
        #expect(path.currentPoint == CGPoint(x: 40, y: 0))
        let bounds = path.boundingBoxOfPath
        #expect(bounds.minX == 0 && bounds.maxX == 40)
        #expect(bounds.minY < 0 && bounds.maxY > 0)
    }

    @Test("Arcos elípticos, inclusive com flags compactos")
    func arcs() throws {
        // Half circle of radius 5 from (0,0) to (10,0), bulging upwards (y < 0 in SVG).
        let half = try SVGPath.parse("M0 0A5 5 0 0 1 10 0")
        let bounds = half.boundingBoxOfPath
        #expect(abs(bounds.minY + 5) < 0.05)
        #expect(abs(bounds.width - 10) < 0.05)
        #expect(half.currentPoint == CGPoint(x: 10, y: 0))

        let compact = try SVGPath.parse("M0 0a2.97 2.97 0 01-.104-.729")
        #expect(abs(compact.currentPoint.x + 0.104) < 1e-9)
        #expect(abs(compact.currentPoint.y + 0.729) < 1e-9)

        // Radii too small to reach the end point are scaled up; zero radii draw a line.
        #expect(try SVGPath.parse("M0 0A1 1 0 0 0 10 0").currentPoint == CGPoint(x: 10, y: 0))
        #expect(try SVGPath.parse("M0 0A0 5 0 0 0 10 0").boundingBoxOfPath.height == 0)
    }

    @Test("Erros de sintaxe")
    func errors() {
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("10 10") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 0 L10") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 0 A5 5 0 2 1 10 0") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 0 Z 5 5") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M0 0 X 5 5") }
    }
}

@Suite("Imagens das marcas")
@MainActor
struct BrandImageTests {
    @Test("Imagem modelo da barra de menus, com 1×, 2× e 3×", arguments: ProviderID.allCases)
    func template(provider: ProviderID) throws {
        let image = BrandImage.template(for: provider)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.representations.count == 3)
        #expect(BrandImage.template(for: provider) === image)  // cached
    }

    @Test("A marca ocupa o quadro sem vazar", arguments: ProviderID.allCases)
    func coverage(provider: ProviderID) throws {
        let rep = try #require(BrandImage.render(provider, pointSize: 16, scale: 2))
        #expect(rep.pixelsWide == 32 && rep.pixelsHigh == 32)
        var inked = 0
        var edgeTouched = false
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                inked += 1
                if x == 0 || y == 0 || x == rep.pixelsWide - 1 || y == rep.pixelsHigh - 1 { edgeTouched = true }
            }
        }
        let share = Double(inked) / Double(rep.pixelsWide * rep.pixelsHigh)
        #expect(share > 0.12 && share < 0.75, "cobertura \(share)")
        #expect(edgeTouched, "a marca deve preencher o quadro")
    }

    @Test("Cores de marca e de alerta")
    func palette() {
        #expect(BrandPalette.color(for: .warning) == .systemOrange)
        #expect(BrandPalette.color(for: .critical) == .systemRed)
        #expect(BrandMark.aspectRatio(for: .antigravity) > 1)
        #expect(abs(BrandMark.aspectRatio(for: .codex) - 1) < 0.1)
    }
}

/// Serves a fixed snapshot.
actor StaticProvider: UsageProvider {
    nonisolated let id: ProviderID
    let snapshot: ProviderSnapshot

    init(_ snapshot: ProviderSnapshot) {
        id = snapshot.provider
        self.snapshot = snapshot
    }

    func snapshot(previous: ProviderSnapshot?) async -> ProviderSnapshot { snapshot }
}

@Suite("Renderização do painel")
@MainActor
struct PanelRenderingTests {
    @Test("Gera as imagens do painel e da barra para todos os provedores")
    func renderPreviews() async throws {
        let now = Date()
        let claude = ProviderSnapshot(
            provider: .claude,
            status: .ok,
            plan: "Max 5x",
            windows: [
                UsageWindow(
                    id: "session", title: "Sessão (5h)", usedPercent: 82, resetsAt: now.addingTimeInterval(4_000), windowSeconds: 18_000,
                    isPrimary: true),
                UsageWindow(
                    id: "weekly_all", title: "Semanal · todos os modelos", usedPercent: 97, resetsAt: now.addingTimeInterval(300_000),
                    windowSeconds: 604_800),
            ],
            tokens: TokenSummary(
                session: TokenCounts(input: 5, output: 10, cacheRead: 100, requests: 1), today: TokenCounts(input: 10, output: 20),
                week: TokenCounts(input: 99)),
            details: [DetailRow(label: "Uso extra", value: "desativado")],
            limitsUpdatedAt: now
        )
        let antigravity = ProviderSnapshot(
            provider: .antigravity,
            status: .stale,
            issue: .sourceUnavailable,
            message: "O Antigravity está fechado — abra-o para atualizar as cotas.",
            models: [ModelQuota(label: "Gemini", remainingFraction: 0.5, resetsAt: nil)]
        )
        let store = UsageStore(providers: [StaticProvider(claude), StaticProvider(antigravity)])
        await store.refreshAllAndWait()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AERESBarUITests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "AERESBarUITests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let files = try PreviewRenderer.render(store: store, settings: AppSettings(defaults: defaults), into: folder)
        #expect(files.count == 8)
        for file in files {
            let image = try #require(NSImage(contentsOf: file))
            #expect(image.size.width > 0)
        }
        let panel = try #require(NSImage(contentsOf: folder.appendingPathComponent("panel-claude-dark.png")))
        #expect(panel.representations.first?.pixelsWide == Int(PanelRootView.width * 2))
    }
}

@Suite("Dados de exemplo")
@MainActor
struct DemoDataTests {
    @Test("Cobrem os três provedores e os estados de alerta")
    func demoStore() async {
        let store = DemoData.store()
        await store.refreshAllAndWait()
        #expect(store.providerIDs == ProviderID.allCases)
        for provider in ProviderID.allCases {
            #expect(store.snapshots[provider]?.status == .ok)
            #expect(store.snapshots[provider]?.windows.isEmpty == false)
        }
        let alerts = ProviderID.allCases.compactMap { BarPresenter.value(for: store.snapshots[$0], config: .init(), now: Date()).alert }
        #expect(alerts == [.warning, .critical])
    }
}
