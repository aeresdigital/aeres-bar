import AppKit
import SwiftUI
import Testing

@testable import AERESBarCore
@testable import AERESBarUI

@Suite("Parser de caminhos SVG")
struct SVGPathTests {
    @Test(
        "As marcas oficiais são lidas e cabem na sua viewBox",
        arguments: [
            (ProviderID.claude, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.codex, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.antigravity, CGRect(x: 0, y: 0, width: 112, height: 112)),
            (.copilot, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.ollama, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.openrouter, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.glm, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.kimi, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.moonshot, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.minimax, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.deepseek, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.qwen, CGRect(x: 0, y: 0, width: 24, height: 24)),
            (.doubao, CGRect(x: 0, y: 0, width: 24, height: 24)),
        ])
    func officialMarks(provider: ProviderID, viewBox: CGRect) throws {
        let parts = try BrandMark.pathData(for: provider).map(SVGPath.parse)
        #expect(!parts.isEmpty)
        let bounds = parts.map(\.boundingBoxOfPath).reduce(CGRect.null) { $0.union($1) }
        #expect(!bounds.isEmpty)
        #expect(viewBox.insetBy(dx: -0.5, dy: -0.5).contains(bounds))
        // The mark fills a good part of its canvas.
        #expect(max(bounds.width, bounds.height) > viewBox.width * 0.6)
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
        var columns: Set<Int> = []
        var rows: Set<Int> = []
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let alpha = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if alpha > 0.5 { inked += 1 }
                if alpha > 0.1 {
                    columns.insert(x)
                    rows.insert(y)
                }
            }
        }
        let share = Double(inked) / Double(rep.pixelsWide * rep.pixelsHigh)
        #expect(share > 0.12 && share < 0.75, "cobertura \(share)")
        // Pointed marks (Z.ai's slanted Z) reach the edges only at their tips: measure the ink's extent.
        let extent = max((columns.max() ?? 0) - (columns.min() ?? 0), (rows.max() ?? 0) - (rows.min() ?? 0)) + 1
        #expect(extent >= rep.pixelsWide * 9 / 10, "a marca deve preencher o quadro (\(extent) px)")
    }

    @Test("Cores de marca e de alerta")
    func palette() {
        #expect(BrandPalette.color(for: .warning) == .systemOrange)
        #expect(BrandPalette.color(for: .critical) == .systemRed)
        #expect(BrandMark.aspectRatio(for: .antigravity) > 1)
        #expect(abs(BrandMark.aspectRatio(for: .codex) - 1) < 0.1)
    }
}

@Suite("Medidor da barra de menus")
@MainActor
struct MeterImageTests {
    /// Alpha at a point given in image points from the bottom-left, on a 2× rendering.
    private func alpha(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> CGFloat {
        let column = Int(x * 2)
        let row = rep.pixelsHigh - 1 - Int(y * 2)  // bitmap rows run top to bottom
        return rep.colorAt(x: column, y: row)?.alphaComponent ?? 0
    }

    @Test("Imagem modelo com 1×, 2× e 3×, reaproveitada para os mesmos níveis")
    func template() {
        let image = MeterImage.template(levels: [74, 86, nil])
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.representations.count == 3)
        #expect(MeterImage.template(levels: [74.2, 85.9, nil]) === image)  // same rounded levels
        #expect(MeterImage.template(levels: [74, 87, nil]) !== image)
    }

    @Test("Cada barra enche até o uso; sem dados, fica só o trilho")
    func fillLevels() throws {
        let rep = try #require(MeterImage.render(levels: [100, nil, 50], pointSize: 16, scale: 2))
        #expect(rep.pixelsWide == 32 && rep.pixelsHigh == 32)
        // Three 3.67 pt bars 1.5 pt apart, centred: their middles sit at x = 2.8, 8 and 13.2 pt,
        // from y = 1.5 to 14.5 pt.
        let (full, empty, half) = (CGFloat(2.8), CGFloat(8), CGFloat(13.2))
        #expect(alpha(rep, x: full, y: 13.5) > 0.9)
        #expect(alpha(rep, x: full, y: 2.5) > 0.9)
        #expect(abs(alpha(rep, x: empty, y: 13.5) - 0.32) < 0.05)
        #expect(abs(alpha(rep, x: empty, y: 2.5) - 0.32) < 0.05)
        #expect(alpha(rep, x: half, y: 2.5) > 0.9)
        #expect(abs(alpha(rep, x: half, y: 13.5) - 0.32) < 0.05)
        // Nothing is drawn between the bars.
        #expect(alpha(rep, x: 5.4, y: 8) < 0.05)
    }

    @Test("Com mais de seis provedores, a imagem alarga em vez de afinar as barras")
    func widensForManyProviders() throws {
        #expect([3, 6, 7, 11].map { MeterImage.width(for: $0, pointSize: 16) } == [16, 16, 19, 29])
        let image = MeterImage.template(levels: Array(repeating: 50, count: 11))
        #expect(image.size == NSSize(width: 29, height: 16))
        let rep = try #require(MeterImage.render(levels: Array(repeating: 100, count: 11), pointSize: 16, scale: 2))
        #expect(rep.pixelsWide == 58 && rep.pixelsHigh == 32)
    }

    @Test("Sem provedores, desenha três trilhos vazios; muitos provedores cabem no quadro")
    func placeholders() throws {
        let empty = try #require(MeterImage.render(levels: [], pointSize: 16, scale: 2))
        #expect(abs(alpha(empty, x: 8, y: 8) - 0.32) < 0.05)
        let six = try #require(MeterImage.render(levels: [10, 20, 30, 40, 50, 60], pointSize: 16, scale: 2))
        #expect(alpha(six, x: 0.2, y: 8) < 0.05 && alpha(six, x: 15.8, y: 8) < 0.05)
    }
}

@Suite("Renderização do painel")
@MainActor
struct PanelRenderingTests {
    @Test("Gera as imagens do painel (resumido e aberto) e da barra, no claro e no escuro")
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
        let openRouter = ProviderSnapshot(provider: .openrouter, status: .notInstalled, message: "Defina a chave.")
        let store = UsageStore(providers: [StaticProvider(claude), StaticProvider(antigravity), StaticProvider(openRouter)])
        await store.refreshAllAndWait()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AERESBarUITests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let temporary = try TemporarySettings()
        defer { temporary.remove() }

        let files = try PreviewRenderer.render(store: store, settings: temporary.settings, into: folder)
        #expect(
            files.map(\.lastPathComponent) == [
                "panel-dark.png", "panel-expanded-dark.png", "menubar-dark.png",
                "panel-light.png", "panel-expanded-light.png", "menubar-light.png",
            ])
        for file in files {
            let image = try #require(NSImage(contentsOf: file))
            #expect(image.size.width > 0)
        }
        // The content below the header is really drawn (a ScrollView would come out blank).
        let rendered = try #require(NSBitmapImageRep(data: try Data(contentsOf: folder.appendingPathComponent("panel-light.png"))))
        var ink = 0
        for y in stride(from: 140, to: rendered.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rendered.pixelsWide, by: 2) {
                guard let color = rendered.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent > 0.5 && color.brightnessComponent < 0.5 { ink += 1 }
            }
        }
        #expect(ink > 500, "o conteúdo abaixo do cabeçalho deve aparecer (\(ink) pontos escuros)")
        let panel = try #require(NSImage(contentsOf: folder.appendingPathComponent("panel-dark.png")))
        let expanded = try #require(NSImage(contentsOf: folder.appendingPathComponent("panel-expanded-dark.png")))
        #expect(panel.representations.first?.pixelsWide == Int(PanelRootView.width * 2))
        // Opening a provider shows its details below the summary.
        #expect((expanded.representations.first?.pixelsHigh ?? 0) > (panel.representations.first?.pixelsHigh ?? 0))

        // The logo style draws the most critical provider's mark instead of the meters.
        temporary.settings.barIconStyle = .criticalLogo
        temporary.settings.showPercentInBar = false
        #expect(try PreviewRenderer.render(store: store, settings: temporary.settings, into: folder).count == 6)
    }

    @Test("Sem nenhum provedor presente, o painel diz isso")
    func emptyPanel() async throws {
        let store = UsageStore(providers: [StaticProvider(ProviderSnapshot(provider: .claude, status: .notInstalled))])
        await store.refreshAllAndWait()
        let temporary = try TemporarySettings()
        defer { temporary.remove() }
        let view = PanelRootView(store: store, settings: temporary.settings, state: PanelState(), actions: PanelActions())
        let renderer = ImageRenderer(content: view)
        #expect((renderer.nsImage?.size.height ?? 0) > 0)
    }

    @Test("Abrir e fechar um provedor")
    func toggleSections() {
        let state = PanelState()
        state.toggle(.codex)
        state.toggle(.claude)
        #expect(state.expanded == [.codex, .claude])
        state.toggle(.codex)
        #expect(state.expanded == [.claude])
    }
}

@Suite("Dados de exemplo")
@MainActor
struct DemoDataTests {
    @Test("Cobrem provedores de todo tipo e os estados de alerta")
    func demoStore() async {
        let store = DemoData.store()
        await store.refreshAllAndWait()
        let demo = DemoData.snapshots(now: Date()).map(\.provider)
        #expect(store.providerIDs == ProviderID.allCases.filter(demo.contains))
        #expect(demo.contains(.glm) && demo.contains(.kimi) && demo.contains(.deepseek))
        for provider in demo {
            #expect(store.snapshots[provider]?.status == .ok)
            // Balance-only services (DeepSeek) have details instead of limits.
            #expect(store.snapshots[provider]?.windows.isEmpty == false || store.snapshots[provider]?.details.isEmpty == false)
        }
        let alerts = ProviderID.allCases.compactMap { BarPresenter.value(for: store.snapshots[$0], config: .init(), now: Date()).alert }
        #expect(alerts == [.warning, .critical])
        let overall = BarPresenter.overall(for: store.snapshots, providers: store.providerIDs, config: .init(), now: Date())
        #expect(overall.critical == .antigravity)
        #expect(overall.levels.count == demo.count - 1)  // DeepSeek reports a balance, not a limit
    }
}
