import AERESBarCore
import SwiftUI

/// The whole panel: provider tabs, details and footer. Countdowns tick every second.
struct PanelRootView: View {
    static let width: CGFloat = 360

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
        let provider = state.selected
        let snapshot = store.snapshots[provider]
        return VStack(spacing: 0) {
            ProviderTabs(selected: $state.selected, snapshots: store.snapshots, now: now)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider().opacity(0.6)
            ProviderDetailView(provider: provider, snapshot: snapshot, now: now)
                .padding(16)
            Divider().opacity(0.6)
            FooterBar(snapshot: snapshot, isRefreshing: store.refreshing.contains(provider), actions: actions)
        }
    }
}

struct ProviderTabs: View {
    @Binding var selected: ProviderID
    let snapshots: [ProviderID: ProviderSnapshot]
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProviderID.allCases) { provider in
                let isSelected = provider == selected
                let accent = BrandPalette.accent(for: provider)
                let alert = BarPresenter.value(for: snapshots[provider], config: .init(), now: now).alert
                Button {
                    selected = provider
                } label: {
                    HStack(spacing: 6) {
                        BrandLogo(provider: provider).frame(width: 14, height: 14)
                        Text(provider.shortName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        if let alert {
                            Circle().fill(Color(nsColor: BrandPalette.color(for: alert))).frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? accent.opacity(0.16) : Color.primary.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct FooterBar: View {
    let snapshot: ProviderSnapshot?
    let isRefreshing: Bool
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 2) {
            Text(isRefreshing ? "Atualizando…" : snapshot?.source ?? AppInfo.name)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            FooterButton(symbol: "arrow.clockwise", help: "Atualizar agora", spinning: isRefreshing, action: actions.refresh)
            FooterButton(symbol: "gearshape", help: "Ajustes", action: actions.openMenu)
            FooterButton(symbol: "power", help: "Sair do \(AppInfo.name)", action: actions.quit)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
    }
}

struct FooterButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: @MainActor () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
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
