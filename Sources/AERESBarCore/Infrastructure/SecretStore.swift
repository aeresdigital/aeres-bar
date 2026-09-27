import Foundation

/// API keys the user gives AERES Bar (services that have no local login to reuse).
public enum SecretAccount: String, CaseIterable, Sendable {
    case openRouter = "openrouter"
    case ollama = "ollama"

    public var provider: ProviderID {
        switch self {
        case .openRouter: .openrouter
        case .ollama: .ollama
        }
    }

    public var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama Cloud"
        }
    }

    /// Environment variable the vendor's own tools read, used as a fallback.
    public var environmentVariable: String {
        switch self {
        case .openRouter: "OPENROUTER_API_KEY"
        case .ollama: "OLLAMA_API_KEY"
        }
    }

    /// Where the user creates a key.
    public var keysPage: URL? {
        switch self {
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")
        case .ollama: URL(string: "https://ollama.com/settings/keys")
        }
    }

    /// The account for a provider, if that provider needs a key.
    public init?(provider: ProviderID) {
        guard let account = Self.allCases.first(where: { $0.provider == provider }) else { return nil }
        self = account
    }
}

/// Stores and reads API keys.
public protocol SecretStore: Sendable {
    func secret(for account: SecretAccount) -> String?
    func setSecret(_ secret: String, for account: SecretAccount) throws
    func deleteSecret(for account: SecretAccount) throws
}

public enum SecretStoreError: Error, Equatable {
    /// The key has characters that cannot be part of an API key (spaces, quotes, line breaks).
    case invalidFormat
    case keychainFailure
}

/// Keeps keys in the login Keychain through `/usr/bin/security`.
///
/// Going through the `security` tool (as Claude Code and the GitHub CLI do) means the item trusts
/// that tool rather than this app's code signature, so reading it never prompts — not even after
/// an update changes the app's signature. The key travels through stdin, never through arguments
/// that other processes could list.
public struct KeychainSecretStore: SecretStore {
    public static let service = "AERES Bar"

    private let runner: any CommandRunner
    private let environment: [String: String]

    public init(runner: any CommandRunner = ProcessCommandRunner(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.runner = runner
        self.environment = environment
    }

    /// The stored key, or the vendor's environment variable when nothing is stored.
    public func secret(for account: SecretAccount) -> String? {
        if let stored = runner.run(
            "/usr/bin/security",
            ["find-generic-password", "-s", Self.service, "-a", account.rawValue, "-w"],
            timeout: 8
        )?.trimmedOutput {
            return stored
        }
        return environment[account.environmentVariable].flatMap { $0.isEmpty ? nil : $0 }
    }

    public func setSecret(_ secret: String, for account: SecretAccount) throws {
        let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(value) else { throw SecretStoreError.invalidFormat }
        let command = "add-generic-password -U -s \"\(Self.service)\" -a \(account.rawValue) -w \"\(value)\"\n"
        guard runner.run("/usr/bin/security", ["-i"], input: Data(command.utf8), timeout: 8)?.status == 0 else {
            throw SecretStoreError.keychainFailure
        }
    }

    public func deleteSecret(for account: SecretAccount) throws {
        guard
            let output = runner.run(
                "/usr/bin/security", ["delete-generic-password", "-s", Self.service, "-a", account.rawValue], timeout: 8)
        else { throw SecretStoreError.keychainFailure }
        // 44 = errSecItemNotFound: nothing to delete is fine.
        guard output.status == 0 || output.status == 44 else { throw SecretStoreError.keychainFailure }
    }

    /// API keys are printable ASCII without whitespace or quotes (e.g. `sk-or-v1-…`).
    static func isValid(_ key: String) -> Bool {
        (8...512).contains(key.count)
            && key.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 32 && $0.value < 127 && $0 != "\"" && $0 != "\\" }
    }
}
