import Foundation

/// Status, headers and body of an HTTP response.
public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data
    /// Header fields, keyed in lowercase.
    public var headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// When the server allows the next request, from `Retry-After` (seconds or an HTTP date).
    public func retryAfter(now: Date) -> Date? {
        guard let value = headers["retry-after"]?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = TimeInterval(value) { return now.addingTimeInterval(max(0, seconds)) }
        return try? Date(value, strategy: Date.FormatStyle.HTTP.httpDate)
    }
}

extension Date.FormatStyle {
    /// RFC 9110 `IMF-fixdate`, e.g. "Sun, 27 Sep 2026 04:47:13 GMT".
    enum HTTP {
        static let httpDate = Date.VerbatimFormatStyle(
            format:
                "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .gmt,
            calendar: Calendar(identifier: .gregorian)
        ).parseStrategy
    }
}

/// Sends HTTP requests. Providers depend on this protocol so tests can answer without a network.
public protocol HTTPClient: Sendable {
    /// Returns the response for any status code; throws only for transport failures.
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    /// For provider APIs: no cookies, no cache, bounded timeouts.
    public static let standard: URLSessionHTTPClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSessionHTTPClient(session: URLSession(configuration: configuration))
    }()

    /// For Antigravity's language server on 127.0.0.1, which serves a self-signed certificate.
    /// The trust override is limited to loopback hosts.
    public static let loopback: URLSessionHTTPClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration, delegate: LoopbackTrustDelegate(), delegateQueue: nil)
        return URLSessionHTTPClient(session: session)
    }()

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return HTTPResponse(status: 0, body: data) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http.statusCode, body: data, headers: headers)
    }
}

/// Accepts the self-signed certificate of servers on the loopback interface only.
final class LoopbackTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            Self.loopbackHosts.contains(space.host),
            let trust = space.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
