import AERESBarCore
import AppKit
import SwiftUI

/// The update at the top of the panel: a new version on offer, its download and installation,
/// or why it failed, with the Terminal command when only a reinstall fixes it.
struct UpdateNotice: View {
    let updater: AppUpdater

    var body: some View {
        if let notice = UpdatePresentation.notice(for: updater.phase, currentVersion: updater.currentVersion) {
            let tint = notice.isProblem ? Color.orange : Color.accentColor
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: notice.isProblem ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title).font(.system(size: 11.5, weight: .semibold))
                        Text(notice.detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                if needsReinstall {
                    Text(UpdateFeed.installCommand)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                actions
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var needsReinstall: Bool {
        if case .failed(let failure, _) = updater.phase { return failure.needsReinstall }
        return false
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            switch updater.phase {
            case .available:
                Button("Agora não") { updater.dismiss() }
                Button("Instalar") { updater.install() }.keyboardShortcut(.defaultAction)
            case .downloading:
                ProgressView().controlSize(.small)
                Button("Cancelar") { updater.cancel() }
            case .installing:
                ProgressView().controlSize(.small)
            case .failed(let failure, let manifest):
                Button("Fechar") { updater.dismiss() }
                if failure.needsReinstall {
                    Button("Copiar comando") { Pasteboard.copy(UpdateFeed.installCommand) }.keyboardShortcut(.defaultAction)
                } else if manifest != nil {
                    Button("Tentar de novo") { updater.install() }.keyboardShortcut(.defaultAction)
                }
            case .idle, .checking:
                EmptyView()
            }
        }
        .controlSize(.small)
    }
}

enum Pasteboard {
    @MainActor
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
