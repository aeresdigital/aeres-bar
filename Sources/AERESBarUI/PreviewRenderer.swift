import AERESBarCore
import AppKit
import SwiftUI

/// Renders the panel and the menu bar items to PNG files (documentation, visual checks).
@MainActor
public enum PreviewRenderer {
    public enum RenderError: Error {
        case renderingFailed(String)
    }

    /// Writes one panel image per provider and appearance, plus the menu bar items.
    /// Returns the files written.
    @discardableResult
    public static func render(store: UsageStore, settings: AppSettings, into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            let background = scheme == .dark ? Color(white: 0.15) : Color(white: 0.97)
            for provider in ProviderID.allCases {
                let state = PanelState()
                state.selected = provider
                let panel = PanelRootView(store: store, settings: settings, state: state, actions: PanelActions())
                    .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .environment(\.colorScheme, scheme)
                written.append(try write(panel, to: directory.appendingPathComponent("panel-\(provider.rawValue)-\(suffix).png")))
            }
            let bar = MenuBarPreview(store: store, settings: settings)
                .padding(.horizontal, 12)
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

/// The menu bar items as they look in the menu bar.
struct MenuBarPreview: View {
    let store: UsageStore
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ProviderID.allCases) { provider in
                let value = BarPresenter.value(for: store.snapshots[provider], config: settings.barConfig, now: Date())
                HStack(spacing: 4) {
                    Image(nsImage: BrandImage.template(for: provider))
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                    Text(value.text)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(value.alert.map { Color(nsColor: BrandPalette.color(for: $0)) } ?? .primary)
                }
            }
        }
    }
}
