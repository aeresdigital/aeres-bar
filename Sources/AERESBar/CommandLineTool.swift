import AERESBarCore
import AERESBarUI
import AppKit
import Foundation

/// Command-line modes: diagnostics and documentation assets.
@MainActor
enum CommandLineTool {
    /// Prints every snapshot as JSON. The second pass shows the cost of an incremental refresh.
    static func dump() {
        run {
            let store = LiveEnvironment.makeStore(persistent: false)
            let clock = ContinuousClock()
            let first = await clock.measure { await store.refreshAllAndWait() }
            let second = await clock.measure { await store.refreshAllAndWait() }

            var output: [String: ProviderSnapshot] = [:]
            for (provider, snapshot) in store.snapshots { output[provider.rawValue] = snapshot }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write(try encoder.encode(output))
            FileHandle.standardOutput.write(Data("\n".utf8))
            report(
                "1ª leitura: \(first.formatted(.units(allowed: [.seconds, .milliseconds]))) · incremental: \(second.formatted(.units(allowed: [.seconds, .milliseconds])))"
            )
            report("Abrir ao iniciar o macOS: \(LoginItem.statusDescription)")
        }
    }

    static func renderPreviews(into directory: URL, demo: Bool) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        run {
            let store = demo ? DemoData.store() : LiveEnvironment.makeStore(persistent: false)
            await store.refreshAllAndWait()
            let files = try PreviewRenderer.render(store: store, settings: AppSettings(), into: directory)
            for file in files { print(file.path) }
        }
    }

    static func loginItem(_ action: CLICommand.LoginItemAction) {
        do {
            switch action {
            case .on: try LoginItem.setEnabled(true)
            case .off: try LoginItem.setEnabled(false)
            case .status: break
            }
            print("Abrir ao iniciar o macOS: \(LoginItem.statusDescription)")
        } catch {
            report("erro: \(error.localizedDescription)")
            exit(1)
        }
    }

    /// Runs async work on the main actor, then exits with its outcome.
    private static func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await work()
                exit(0)
            } catch {
                report("erro: \(error)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }
}
