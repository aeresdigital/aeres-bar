import Foundation

/// A verified build unpacked next to the running app, ready to take its place.
public struct PreparedUpdate: Equatable, Sendable {
    /// The new app, inside `workFolder`.
    public var app: URL
    /// The app it replaces.
    public var target: URL
    /// A temporary folder on the target's volume, so the swap is a rename.
    public var workFolder: URL
}

/// Puts a verified build in place of the running app.
public protocol UpdateInstalling: Sendable {
    /// The running app, when it can be replaced where it is.
    func installTarget() async throws -> URL
    /// Unpacks the zip (its signature already checked) next to `target` and checks the app inside.
    func prepare(_ zip: Data, for manifest: UpdateManifest, replacing target: URL) async throws -> PreparedUpdate
    /// Starts the helper that swaps the apps once this process exits, then opens the new one.
    func launch(_ update: PreparedUpdate) async throws
    /// Whether the helper left word that the last swap failed; the word is removed.
    func consumeFailedSwap() async -> Bool
}

/// Replaces the app bundle this process runs from.
public actor BundleUpdateInstaller: UpdateInstalling {
    private let bundleURL: URL
    private let bundleIdentifier: String
    private let currentBuild: Int
    private let runner: any CommandRunner
    private let failureMarker: URL
    private let processID: Int32
    private let reopensApp: Bool

    public init(
        bundleURL: URL,
        bundleIdentifier: String = AppInfo.bundleIdentifier,
        currentBuild: Int,
        runner: any CommandRunner = ProcessCommandRunner(),
        failureMarker: URL = DataLocations.updateFailureMarker,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        reopensApp: Bool = true
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.currentBuild = currentBuild
        self.runner = runner
        self.failureMarker = failureMarker
        self.processID = processID
        self.reopensApp = reopensApp
    }

    public func installTarget() throws -> URL {
        let bundle = bundleURL.resolvingSymlinksInPath()
        let folder = bundle.deletingLastPathComponent()
        let manager = FileManager.default
        // Gatekeeper runs a quarantined app opened from Downloads from a random read-only copy, and
        // a disk image is read-only: replacing either would change nothing.
        if bundle.path.contains("/AppTranslocation/") { throw UpdateFailure.translocated }
        guard manager.isWritableFile(atPath: folder.path), manager.isWritableFile(atPath: bundle.path) else {
            throw folder.path.hasPrefix("/Volumes/") ? UpdateFailure.translocated : UpdateFailure.notWritable(folder.path)
        }
        // POSIX permissions do not show macOS's protection of apps installed from a browser
        // download; a write does.
        let probe = bundle.appendingPathComponent("Contents/.update-probe")
        guard manager.createFile(atPath: probe.path, contents: Data()) else { throw UpdateFailure.protectedByMacOS }
        try? manager.removeItem(at: probe)
        return bundle
    }

    public func prepare(_ zip: Data, for manifest: UpdateManifest, replacing target: URL) throws -> PreparedUpdate {
        let manager = FileManager.default
        let work: URL
        do {
            work = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        } catch {
            throw UpdateFailure.notWritable(target.deletingLastPathComponent().path)
        }
        do {
            let archive = work.appendingPathComponent("update.zip")
            let unpacked = work.appendingPathComponent("new", isDirectory: true)
            try zip.write(to: archive)
            guard runner.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path], timeout: 120)?.status == 0 else {
                throw UpdateFailure.invalidPackage
            }
            try? manager.removeItem(at: archive)
            let apps = ((try? manager.contentsOfDirectory(atPath: unpacked.path)) ?? []).filter { $0.hasSuffix(".app") }
            guard apps.count == 1, let name = apps.first else { throw UpdateFailure.invalidPackage }
            let app = unpacked.appendingPathComponent(name, isDirectory: true)
            try validate(app, against: manifest)
            return PreparedUpdate(app: app, target: target, workFolder: work)
        } catch {
            try? manager.removeItem(at: work)
            throw error
        }
    }

    /// The app must be this one (same identifier), the build the feed announced, newer than the
    /// running one, and intact (`codesign --verify`).
    func validate(_ app: URL, against manifest: UpdateManifest) throws {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            info["CFBundleIdentifier"] as? String == bundleIdentifier,
            let executable = info["CFBundleExecutable"] as? String,
            FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/\(executable)").path),
            let build = (info["CFBundleVersion"] as? String).flatMap({ Int($0) }),
            build == manifest.build
        else { throw UpdateFailure.invalidPackage }
        guard build > currentBuild else { throw UpdateFailure.notNewer }
        guard runner.run("/usr/bin/codesign", ["--verify", "--strict", app.path], timeout: 60)?.status == 0 else {
            throw UpdateFailure.invalidPackage
        }
    }

    /// Not through `CommandRunner`, which waits for the command: the helper has to outlive the
    /// app. Paths travel as arguments, never inside the script text.
    public func launch(_ update: PreparedUpdate) throws {
        let script = update.workFolder.appendingPathComponent("swap.sh")
        try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: failureMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path, String(processID), update.app.path, update.target.path, update.workFolder.path, failureMarker.path,
            reopensApp ? "1" : "0",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    public func consumeFailedSwap() -> Bool {
        guard FileManager.default.fileExists(atPath: failureMarker.path) else { return false }
        try? FileManager.default.removeItem(at: failureMarker)
        return true
    }

    /// Waits for the app to quit, swaps the apps (putting the old one back if that fails),
    /// clears the quarantine flag and opens the result.
    static let swapScript = """
        #!/bin/sh
        # $1 pid of the running app, $2 new app, $3 app to replace, $4 work folder (removed at the
        # end), $5 note left for the next launch when the swap fails, $6 1 to open the app after.
        trap '' HUP
        pid="$1"; new="$2"; dest="$3"; work="$4"; failed="$5"; reopen="$6"
        n=0
        while kill -0 "$pid" 2>/dev/null; do
          n=$((n + 1))
          # The app did not quit within a minute: leave everything as it is.
          if [ "$n" -gt 300 ]; then rm -rf "$work"; exit 1; fi
          sleep 0.2
        done
        old="$work/previous.app"
        if mv "$dest" "$old"; then
          if mv "$new" "$dest"; then
            rm -rf "$old"
          else
            rm -rf "$dest"
            mv "$old" "$dest"
            : > "$failed"
          fi
        else
          : > "$failed"
        fi
        xattr -dr com.apple.quarantine "$dest" 2>/dev/null
        [ "$reopen" = 1 ] && open "$dest"
        [ -n "$work" ] && rm -rf "$work"
        exit 0
        """
}
