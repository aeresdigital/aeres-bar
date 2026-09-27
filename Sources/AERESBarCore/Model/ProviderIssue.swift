/// A refresh failure that still lets the app show cached data, with an explanation for the user.
public struct ProviderIssue: Error, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The tool is not installed on this Mac.
        case notInstalled
        /// Installed, but not signed in.
        case notSignedIn
        /// The stored credential has expired; the tool renews it when used.
        case credentialsExpired
        /// The provider rejected the credential.
        case unauthorized
        /// Too many requests; the provider asked us to slow down.
        case rateLimited
        /// No connection or the request failed in transit.
        case network
        /// The provider answered with something we could not read.
        case invalidResponse
        /// The data source exists but is not reachable right now (e.g. Antigravity is closed).
        case sourceUnavailable
    }

    public var kind: Kind
    public var message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}
