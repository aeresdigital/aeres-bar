import Foundation
import os

/// Result of running a command-line tool.
public struct CommandOutput: Sendable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data = Data()) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var text: String { String(decoding: stdout, as: UTF8.self) }

    /// Standard output without surrounding whitespace, or `nil` when the command failed or printed nothing.
    public var trimmedOutput: String? {
        guard status == 0 else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// Runs command-line tools (`ps`, `lsof`, `security`, `gh`). Injected so tests can script the answers.
public protocol CommandRunner: Sendable {
    /// Runs `executable` directly (no shell), feeding `input` to its standard input.
    /// Returns `nil` if it cannot start or exceeds `timeout`.
    func run(_ executable: String, _ arguments: [String], input: Data?, timeout: TimeInterval) -> CommandOutput?
}

extension CommandRunner {
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandOutput? {
        run(executable, arguments, input: nil, timeout: timeout)
    }
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], input: Data?, timeout: TimeInterval) -> CommandOutput? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Scripts started with `#!/usr/bin/env node` look their interpreter up in PATH, and a GUI
        // app's PATH is minimal: add the tool's own folder (nvm keeps node next to it) and the
        // usual install folders.
        var environment = ProcessInfo.processInfo.environment
        let folders = [URL(fileURLWithPath: executable).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (folders + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        process.environment = environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = input == nil ? FileHandle.nullDevice : inPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain both pipes concurrently (before feeding stdin): a full pipe would otherwise block the child forever.
        let stdout = PipeDrain(outPipe.fileHandleForReading)
        let stderr = PipeDrain(errPipe.fileHandleForReading)
        if let input {
            // Secrets go through stdin, never through arguments that other processes can list.
            try? inPipe.fileHandleForWriting.write(contentsOf: input)
            try? inPipe.fileHandleForWriting.close()
        }
        let deadline = DispatchTime.now() + timeout
        guard stdout.wait(until: deadline), stderr.wait(until: deadline) else {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return CommandOutput(status: process.terminationStatus, stdout: stdout.data, stderr: stderr.data)
    }
}

/// Reads a pipe to its end on a background queue.
private final class PipeDrain: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: Data())
    private let done = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [buffer, done] in
            let data = handle.readDataToEndOfFile()
            buffer.withLock { $0 = data }
            done.signal()
        }
    }

    func wait(until deadline: DispatchTime) -> Bool {
        done.wait(timeout: deadline) == .success
    }

    var data: Data { buffer.withLock { $0 } }
}
