import AERESBarCore
import AERESBarUI
import AppKit
import Foundation

@main
@MainActor
enum AERESBarApp {
    private static var delegate: AppDelegate?

    static func main() {
        switch CLICommand.parse(CommandLine.arguments) {
        case .runApp:
            let app = NSApplication.shared
            let delegate = AppDelegate()
            self.delegate = delegate
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        case .dump:
            CommandLineTool.dump()
        case .renderPreview(let directory, let demo):
            CommandLineTool.renderPreviews(into: URL(fileURLWithPath: directory, isDirectory: true), demo: demo)
        case .loginItem(let action):
            CommandLineTool.loginItem(action)
        case .version:
            print("\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))")
        case .help:
            print(CLICommand.usage)
        case .invalid(let reason):
            FileHandle.standardError.write(Data("erro: \(reason)\n\n\(CLICommand.usage)\n".utf8))
            exit(64)  // EX_USAGE
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would duplicate every menu bar item.
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleIdentifier)
            .filter { $0.processIdentifier != me }
        guard others.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        let coordinator = AppCoordinator(store: LiveEnvironment.makeStore(persistent: true), settings: AppSettings())
        coordinator.start()
        self.coordinator = coordinator
    }
}
