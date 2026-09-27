import Foundation

/// A running Antigravity language server.
public struct LanguageServerProcess: Equatable, Sendable {
    public var pid: Int32
    /// Required in the `X-Codeium-Csrf-Token` header of every request.
    public var csrfToken: String
    /// Ports given on the command line (the agent app passes `--https_server_port 0`, i.e. random).
    public var declaredPorts: [Int]
}

/// Finds Antigravity's language servers (Antigravity and Antigravity IDE each start one)
/// and the ports they listen on, using `ps` and `lsof`.
public struct LanguageServerLocator: Sendable {
    private let runner: any CommandRunner

    public init(runner: any CommandRunner = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func runningServers() -> [LanguageServerProcess] {
        guard let output = runner.run("/bin/ps", ["-axww", "-o", "pid=,command="], timeout: 5) else { return [] }
        return Self.parseProcessList(output.text)
    }

    /// Declared ports first, then whatever the process listens on.
    public func candidatePorts(for server: LanguageServerProcess) -> [Int] {
        var ports = server.declaredPorts
        if let output = runner.run("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(server.pid)", "-iTCP", "-sTCP:LISTEN", "-Fn"], timeout: 5) {
            for port in Self.parseListeningPorts(output.text) where !ports.contains(port) {
                ports.append(port)
            }
        }
        return ports
    }

    /// Parses `ps -axww -o pid=,command=` output.
    public static func parseProcessList(_ text: String) -> [LanguageServerProcess] {
        var servers: [LanguageServerProcess] = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = Int32(line[..<space]) else { continue }
            let command = line[space...].trimmingCharacters(in: .whitespaces)
            // The executable path may contain spaces ("Antigravity IDE.app"); flags start at " --".
            let executable = command.components(separatedBy: " --").first ?? command
            guard (executable as NSString).lastPathComponent.hasPrefix("language_server"),
                command.range(of: "antigravity", options: .caseInsensitive) != nil,
                let csrf = argument("csrf_token", in: command)
            else { continue }
            let ports = ["https_server_port", "http_server_port", "server_port", "extension_server_port"]
                .compactMap { argument($0, in: command).flatMap(Int.init) }
                .filter { $0 > 0 }
            servers.append(LanguageServerProcess(pid: pid, csrfToken: csrf, declaredPorts: ports))
        }
        return servers
    }

    /// Parses `lsof -Fn` output ("n127.0.0.1:64999", "n*:65000", "n[::1]:1234").
    public static func parseListeningPorts(_ text: String) -> [Int] {
        var ports: [Int] = []
        for line in text.split(separator: "\n") where line.hasPrefix("n") {
            guard let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) else { continue }
            if !ports.contains(port) { ports.append(port) }
        }
        return ports
    }

    /// Value of `--name value` or `--name=value`.
    public static func argument(_ name: String, in command: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "--\(NSRegularExpression.escapedPattern(for: name))(?:=|\\s+)(\\S+)") else {
            return nil
        }
        let text = command as NSString
        guard let match = regex.firstMatch(in: command, range: NSRange(location: 0, length: text.length)) else { return nil }
        return text.substring(with: match.range(at: 1))
    }
}
