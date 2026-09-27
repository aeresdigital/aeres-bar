import CryptoKit
import Foundation

/// Reads the newest build from the release feed and downloads it.
public protocol UpdateSource: Sendable {
    func latest() async throws -> UpdateManifest
    /// The zip the manifest points to.
    func download(_ manifest: UpdateManifest) async throws -> Data
}

/// Where builds are published. The source repository is private, so every build also goes to a
/// public repository that holds only releases: the DMG for new installs, and the zip plus a
/// signed `update.json` for installed apps.
public struct UpdateFeed: UpdateSource {
    public static let repository = "aeresdigital/aeres-bar-releases"
    public static let releasesPage = github("releases/latest")
    public static let manifestURL = github("releases/latest/download/update.json")
    /// Installs without the quarantine flag a browser download carries (`scripts/install_release.sh`).
    public static let installCommand = "curl -fsSL https://github.com/\(repository)/releases/latest/download/install.sh | sh"
    /// Pair of the private key in the `UPDATE_SIGNING_KEY` secret (`scripts/sign_update.swift`).
    /// Changing it means installed apps stop accepting updates until they are reinstalled by hand.
    public static let publicKey = "vZP63QjsXmW+z1TA//fg/ITFfSEt/hPcXdQ8XJ/ZppE="
    /// `defaults write com.aeresdigital.aeresbar UpdateFeedURL <url>` points the app at another
    /// feed, for testing; the signature check still applies.
    public static let overrideKey = "UpdateFeedURL"

    public let manifestURL: URL
    private let http: any HTTPClient

    public init(manifestURL: URL = Self.manifestURL, http: any HTTPClient) {
        self.manifestURL = manifestURL
        self.http = http
    }

    /// The feed set in `defaults` for testing, or the published one.
    public static func configuredManifestURL(defaults: UserDefaults) -> URL {
        defaults.string(forKey: overrideKey).flatMap(URL.init(string:)).flatMap { $0.scheme == nil ? nil : $0 } ?? manifestURL
    }

    public func latest() async throws -> UpdateManifest {
        let data = try await fetch(manifestURL, accept: "application/json")
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data), manifest.build > 0,
            Self.sameOrigin(manifest.url, manifestURL)
        else { throw UpdateFailure.invalidManifest }
        return manifest
    }

    public func download(_ manifest: UpdateManifest) async throws -> Data {
        try await fetch(manifest.url, accept: "application/octet-stream")
    }

    private func fetch(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw UpdateFailure.unreachable(error.localizedDescription)
        }
        guard response.status == 200 else { throw UpdateFailure.http(response.status) }
        return response.body
    }

    /// The zip must come from where the feed is (GitHub's redirect to its download host happens
    /// after that), so a tampered `update.json` cannot send the app anywhere else.
    static func sameOrigin(_ url: URL, _ feed: URL) -> Bool {
        url.scheme == feed.scheme && url.host() == feed.host() && url.port == feed.port
    }

    private static func github(_ path: String) -> URL {
        URL(string: "https://github.com/\(repository)/\(path)") ?? URL(fileURLWithPath: "/")
    }
}

/// Checks the Ed25519 signature the release workflow puts on each zip.
public enum UpdateSignature {
    public static func isValid(_ signature: String, for data: Data, publicKey: String = UpdateFeed.publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
            let signatureData = Data(base64Encoded: signature)
        else { return false }
        return key.isValidSignature(signatureData, for: data)
    }
}
