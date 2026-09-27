import Foundation

/// What a vendor CLI's output says.
public enum CommandOutcome: Equatable, Sendable {
    case reading(KeyedReading)
    /// Logged in, but without a plan to show.
    case noPlan(String)
    case unreadable
}

/// A service read through the vendor's official CLI, with the CLI's own login. For some
/// subscriptions (Volcengine Ark's and Alibaba Model Studio's coding plans) that is the only way
/// short of asking for account-wide access keys.
public struct CommandService: Sendable {
    public var provider: ProviderID
    public var name: String
    public var source: String
    /// Executable names, looked for in the usual install folders, and a variable that may point at one.
    public var executables: [String]
    public var pathVariable: String?
    /// The CLI is only run once its own login folder exists: a login is needed anyway, and it
    /// makes sure the program found is the vendor's.
    public var loginFolders: [URL]
    public var arguments: [String]
    public var installHint: String
    public var loginHint: String
    public var read: @Sendable (Data) -> CommandOutcome

    public init(
        provider: ProviderID, name: String, source: String, executables: [String], pathVariable: String?, loginFolders: [URL],
        arguments: [String], installHint: String, loginHint: String, read: @escaping @Sendable (Data) -> CommandOutcome
    ) {
        self.provider = provider
        self.name = name
        self.source = source
        self.executables = executables
        self.pathVariable = pathVariable
        self.loginFolders = loginFolders
        self.arguments = arguments
        self.installHint = installHint
        self.loginHint = loginHint
        self.read = read
    }
}

/// Runs a ``CommandService``'s CLI, reusing recent output like the HTTP providers do.
public actor CommandUsageProvider: UsageProvider {
    public nonisolated let id: ProviderID

    private let service: CommandService
    private let runner: any CommandRunner
    private let searchDirectories: [URL]
    private let environment: [String: String]
    private let policy: FetchPolicy
    private let now: @Sendable () -> Date
    private var state = FetchState<KeyedReading>()

    public init(
        service: CommandService,
        runner: any CommandRunner = ProcessCommandRunner(),
        searchDirectories: [URL] = DataLocations.cliSearchDirectories,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        policy: FetchPolicy = FetchPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.id = service.provider
        self.service = service
        self.runner = runner
        self.searchDirectories = searchDirectories
        self.environment = environment
        self.policy = policy
        self.now = now
    }

    public func snapshot(previous: ProviderSnapshot?, reason: RefreshReason) async -> ProviderSnapshot {
        let now = now()
        var snapshot = previous ?? ProviderSnapshot(provider: id)
        snapshot.checkedAt = now

        guard let executable = locate() else {
            snapshot.markFailed(ProviderIssue(.notInstalled, service.installHint))
            return snapshot
        }
        guard service.loginFolders.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            snapshot.markFailed(ProviderIssue(.notSignedIn, service.loginHint))
            return snapshot
        }
        switch read(executable, now: now, reason: reason) {
        case .success(let fetch):
            snapshot.plan = fetch.value.plan
            snapshot.windows = fetch.value.windows
            snapshot.details = fetch.value.details
            snapshot.markFresh(at: fetch.at, source: service.source)
        case .failure(let issue):
            snapshot.markFailed(issue)
            Log.providers.notice("\(self.service.name, privacy: .public): \(issue.kind.rawValue, privacy: .public)")
        }
        return snapshot
    }

    private func read(_ executable: String, now: Date, reason: RefreshReason) -> Result<(value: KeyedReading, at: Date), ProviderIssue> {
        if let cached = state.reusable(now: now, reason: reason, policy: policy) { return .success(cached) }
        guard let output = runner.run(executable, service.arguments, timeout: 25) else {
            return .failure(ProviderIssue(.network, "O \(service.name) não respondeu a tempo. Mostrando os últimos dados."))
        }
        guard output.status == 0 else { return .failure(ProviderIssue(.notSignedIn, service.loginHint)) }
        switch service.read(output.stdout) {
        case .reading(let reading):
            state.record(reading, at: now)
            return .success((reading, now))
        case .noPlan(let message):
            return .failure(ProviderIssue(.notSignedIn, message))
        case .unreadable:
            return .failure(ProviderIssue(.invalidResponse, "O \(service.name) respondeu num formato inesperado."))
        }
    }

    /// The CLI's path: the variable pointing at it, then the usual install folders.
    private func locate() -> String? {
        if let variable = service.pathVariable, let path = environment[variable], FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        for directory in searchDirectories {
            for name in service.executables {
                let path = directory.appendingPathComponent(name).path
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }
}
