import AERESBarCore
import AppKit
import SwiftUI

/// The panel: every enabled provider at once, compact, with full details on demand.
/// Countdowns tick every second.
struct PanelRootView: View {
    static let width: CGFloat = 400

    let store: UsageStore
    let settings: AppSettings
    @Bindable var state: PanelState
    let actions: PanelActions

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(now: timeline.date)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func content(now: Date) -> some View {
        let providers = store.providerIDs
        let shown = providers.filter { store.snapshots[$0]?.status != .notInstalled }
        let absent = providers.filter { store.snapshots[$0]?.status == .notInstalled }
        return VStack(spacing: 0) {
            PanelHeader(
                subtitle: UsagePresentation.updatedLine(for: providers.compactMap { store.snapshots[$0] }, now: now),
                isRefreshing: store.isRefreshing,
                actions: actions
            )
            Divider().opacity(0.6)
            if shown.isEmpty {
                Text("Nenhum provedor encontrado neste Mac.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            ForEach(shown) { provider in
                ProviderSection(
                    provider: provider,
                    snapshot: store.snapshots[provider],
                    now: now,
                    isExpanded: state.expanded.contains(provider),
                    onToggle: { state.toggle(provider) }
                )
                if provider != shown.last {
                    Divider().opacity(0.35).padding(.horizontal, 14)
                }
            }
            if let line = UsagePresentation.unconfiguredLine(for: absent) {
                Divider().opacity(0.6)
                UnconfiguredFooter(text: line, action: actions.openMenu)
            }
        }
    }
}

struct PanelHeader: View {
    let subtitle: String
    let isRefreshing: Bool
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name).font(.system(size: 13, weight: .semibold))
                Text(isRefreshing ? "Atualizando…" : subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            RefreshButton(isRefreshing: isRefreshing, action: actions.refresh)
            IconButton(symbol: "gearshape", help: "Ajustes", action: actions.openMenu)
            IconButton(symbol: "power", help: "Sair do \(AppInfo.name)", action: actions.quit)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
    }
}

struct UnconfiguredFooter: View {
    let text: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill").font(.system(size: 10))
                Text(text).lineLimit(2)
                Spacer(minLength: 4)
                Text("Configurar").fontWeight(.medium)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
