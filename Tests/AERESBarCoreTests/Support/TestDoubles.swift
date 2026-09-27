import Foundation
import os

@testable import AERESBarCore

/// Loads files from `Fixtures/`.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil, subdirectory: "Fixtures")
        else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

/// A controllable clock for providers and the store.
final class TestClock: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        current = OSAllocatedUnfairLock(initialState: start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    var provider: @Sendable () -> Date { { [self] in now } }
}

/// Answers HTTP requests from a closure and records them.
final class MockHTTPClient: HTTPClient {
    typealias Responder = @Sendable (URLRequest) throws -> HTTPResponse

    private let responder: OSAllocatedUnfairLock<Responder>
    private let log = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

    init(_ responder: @escaping Responder) {
        self.responder = OSAllocatedUnfairLock(initialState: responder)
    }

    /// Always answers `status` with `body`.
    convenience init(status: Int, body: Data = Data(), headers: [String: String] = [:]) {
        self.init { _ in HTTPResponse(status: status, body: body, headers: headers) }
    }

    func respond(with responder: @escaping Responder) {
        self.responder.withLock { $0 = responder }
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        log.withLock { $0.append(request) }
        let responder = responder.withLock { $0 }
        return try responder(request)
    }
}

/// Returns canned command output by executable path.
struct ScriptedCommandRunner: CommandRunner {
    var outputs: [String: CommandOutput]

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandOutput? {
        outputs[executable]
    }
}

/// Serves a fixed credential and counts how often it was asked for.
final class StubCredentialSource: ClaudeCredentialSource {
    private let state: OSAllocatedUnfairLock<(credentials: ClaudeCredentials?, loads: Int)>

    init(_ credentials: ClaudeCredentials?) {
        state = OSAllocatedUnfairLock(initialState: (credentials, 0))
    }

    func load() -> ClaudeCredentials? {
        state.withLock { state in
            state.loads += 1
            return state.credentials
        }
    }

    func replace(with credentials: ClaudeCredentials?) {
        state.withLock { $0.credentials = credentials }
    }

    var loads: Int { state.withLock { $0.loads } }
}

enum TestError: Error {
    case offline
}

/// A throwaway directory, removed by the caller with `remove()`.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("AERESBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ text: String, to relativePath: String) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func append(_ text: String, to relativePath: String) throws {
        let file = url.appendingPathComponent(relativePath)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}

/// Calendar pinned to São Paulo, so day boundaries in tests do not depend on the machine.
extension Calendar {
    static var saoPaulo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        return calendar
    }
}

func iso(_ string: String) -> Date? {
    Timestamp.parse(string)
}
