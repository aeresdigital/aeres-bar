import AERESBarCore
import AppKit
import SwiftUI

/// Renders the panel and the menu bar item to PNG files (documentation, visual checks).
@MainActor
public enum PreviewRenderer {
    public enum RenderError: Error {
        case renderingFailed(String)
    }

    /// Writes the panel (compact and with the first provider expanded) and the menu bar item,
    /// in dark and light appearance. Returns the files written.
    @discardableResult
    public static func render(store: UsageStore, settings: AppSettings, into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            let background = scheme == .dark ? Color(white: 0.15) : Color(white: 0.97)

            for expanded in [false, true] {
                let state = PanelState()
                if expanded, let first = store.providerIDs.first { state.expanded = [first] }
                let panel = PanelRootView(store: store, settings: settings, state: state, actions: PanelActions())
                    .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .environment(\.colorScheme, scheme)
                let name = expanded ? "panel-expanded-\(suffix).png" : "panel-\(suffix).png"
                written.append(try write(panel, to: directory.appendingPathComponent(name)))
            }

            let bar = MenuBarPreview(store: store, settings: settings)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .environment(\.colorScheme, scheme)
            written.append(try write(bar, to: directory.appendingPathComponent("menubar-\(suffix).png")))
        }
        return written
    }

    private static func write(_ view: some View, to url: URL) throws -> URL {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = false
        guard let image = renderer.cgImage,
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw RenderError.renderingFailed(url.lastPathComponent) }
        try png.write(to: url)
        return url
    }
}

/// The single menu bar item as it looks in the menu bar.
struct MenuBarPreview: View {
    let store: UsageStore
    let settings: AppSettings

    var body: some View {
        let overall = BarPresenter.overall(for: store.snapshots, providers: store.providerIDs, config: settings.barConfig, now: Date())
        let icon =
            settings.barIconStyle == .meters
            ? MeterImage.template(levels: overall.levels.map(\.usedPercent))
            : BrandImage.template(for: overall.critical ?? .claude)
        HStack(spacing: 4) {
            Image(nsImage: icon)
                .renderingMode(.template)
                .foregroundStyle(.primary)
            if settings.showPercentInBar {
                Text(overall.text)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(overall.alert.map { Color(nsColor: BrandPalette.color(for: $0)) } ?? .primary)
            }
        }
    }
}
