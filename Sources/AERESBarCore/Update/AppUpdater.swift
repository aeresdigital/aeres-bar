import Foundation
import Observation

/// Keeps the app current without people downloading and reinstalling it.
///
/// On launch and every hour after, the app reads the release feed (`UpdateFeed`). A newer build
/// shows up at the top of the panel and in the menu; nothing pops up over people's work.
/// Accepting downloads the zip, checks its Ed25519 signature against the key compiled into the
/// app, unpacks it next to the app, checks the app inside, and hands over to a helper that swaps
/// the apps once this one quits and opens the new one.
///
/// The app is not notarized. A file the app downloads itself carries no quarantine flag, so the
/// new version opens without Gatekeeper's warning, which is why nothing is installed unless the
/// signature checks out.
@MainActor
@Observable
public final class AppUpdater {
    public enum Phase: Equatable, Sendable {
        case idle
        /// A check people asked for ("Procurar atualizações…").
        case checking
        case available(UpdateManifest)
        case downloading(UpdateManifest)
        case installing(UpdateManifest)
        /// Installing failed; the build, when known, can be tried again.
        case failed(UpdateFailure, UpdateManifest?)
    }

    public enum CheckResult: Equatable, Sendable {
        case upToDate
        case available(UpdateManifest)
        case failed(UpdateFailure)
        /// A check, download or installation is already under way.
        case busy
    }

    public static let checkInterval: Duration = .seconds(60 * 60)

    public private(set) var phase: Phase = .idle
    public let currentVersion: String
    /// Off outside an installed app (`swift run`, tests): there is no app to replace.
    public let isEnabled: Bool

    private let source: any UpdateSource
    private let installer: any UpdateInstalling
    private let currentBuild: Int
    private let system: OperatingSystemVersion
    private let publicKey: String
    private let quit: @MainActor () -> Void
    /// A build people answered "Agora não" to: automatic checks stay quiet about it until the next launch.
    @ObservationIgnored private var postponedBuild: Int?
    @ObservationIgnored private var periodicCheck: Task<Void, Never>?
    @ObservationIgnored private var installTask: Task<Void, Never>?

    public init(
        source: any UpdateSource,
        installer: any UpdateInstalling,
        currentVersion: String,
        currentBuild: Int,
        isEnabled: Bool,
        system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        publicKey: String = UpdateFeed.publicKey,
        quit: @escaping @MainActor () -> Void
    ) {
        self.source = source
        self.installer = installer
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.isEnabled = isEnabled
        self.system = system
        self.publicKey = publicKey
        self.quit = quit
    }

    /// The build being offered, installed, or that failed to install.
    public var pendingUpdate: UpdateManifest? {
        switch phase {
        case .available(let manifest), .downloading(let manifest), .installing(let manifest): manifest
        case .failed(_, let manifest): manifest
        case .idle, .checking: nil
        }
    }

    public var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: true
        case .idle, .available, .failed: false
        }
    }

    // MARK: Checking

    /// Reports a swap that failed after the last update, then checks after `delay` and every
    /// `interval` from then on.
    public func start(after delay: Duration = .seconds(10), every interval: Duration = checkInterval) {
        guard isEnabled, periodicCheck == nil else { return }
        periodicCheck = Task { [weak self] in
            if await self?.installer.consumeFailedSwap() == true { self?.phase = .failed(.swapFailed, nil) }
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                await self?.check(userInitiated: false)
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        periodicCheck?.cancel()
        periodicCheck = nil
    }

    /// Automatic checks say nothing about failures (offline, GitHub down), about a build people
    /// postponed, or over an installation that failed; a check people asked for always answers.
    @discardableResult
    public func check(userInitiated: Bool) async -> CheckResult {
        guard isEnabled else { return .failed(.developmentBuild) }
        guard !isBusy else { return .busy }
        let previous = phase
        if userInitiated { phase = .checking }
        let manifest: UpdateManifest
        do {
            manifest = try await source.latest()
        } catch {
            if userInitiated { phase = previous }
            return .failed(error as? UpdateFailure ?? .other(error.localizedDescription))
        }
        let isUpdate = manifest.isUpdate(over: currentBuild, system: system)
        if userInitiated {
            phase = isUpdate ? .available(manifest) : .idle
        } else if !isBusy {
            // An installation may have started while the feed was being read.
            switch phase {
            case .idle where isUpdate && postponedBuild != manifest.build, .available where isUpdate:
                phase = .available(manifest)
            case .available:
                phase = .idle
            case .idle, .checking, .downloading, .installing, .failed:
                break
            }
        }
        return isUpdate ? .available(manifest) : .upToDate
    }

    // MARK: Installing

    /// Downloads, verifies and installs the pending build, then quits so the helper can swap the
    /// apps and open the new one. Returns the work under way, for callers that report its outcome.
    @discardableResult
    public func install() -> Task<Void, Never>? {
        if let installTask { return installTask }
        guard !isBusy, let manifest = pendingUpdate else { return nil }
        let task = Task { [weak self] in
            await self?.performInstall(manifest)
            self?.installTask = nil
        }
        installTask = task
        return task
    }

    /// Stops a download under way; the build stays on offer.
    public func cancel() {
        installTask?.cancel()
    }

    /// "Agora não", or closing a failure. A download under way keeps going.
    public func dismiss() {
        switch phase {
        case .available(let manifest), .failed(_, .some(let manifest)):
            postponedBuild = manifest.build
            phase = .idle
        case .failed(_, .none):
            phase = .idle
        case .idle, .checking, .downloading, .installing:
            break
        }
    }

    private func performInstall(_ manifest: UpdateManifest) async {
        phase = .downloading(manifest)
        do {
            let target = try await installer.installTarget()
            let zip = try await source.download(manifest)
            try Task.checkCancellation()
            guard UpdateSignature.isValid(manifest.signature, for: zip, publicKey: publicKey) else { throw UpdateFailure.badSignature }
            phase = .installing(manifest)
            let update = try await installer.prepare(zip, for: manifest, replacing: target)
            try await installer.launch(update)
            Log.app.notice("Atualizando para \(manifest.version, privacy: .public); o app fecha e abre de novo")
            quit()
        } catch is CancellationError {
            phase = .available(manifest)
        } catch {
            let failure = error as? UpdateFailure ?? .other(error.localizedDescription)
            Log.app.error("Atualização para \(manifest.version, privacy: .public) falhou: \(failure.message, privacy: .public)")
            phase = .failed(failure, manifest)
        }
    }
}
