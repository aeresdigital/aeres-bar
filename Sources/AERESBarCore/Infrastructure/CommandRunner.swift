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
}

/// Runs command-line tools (`ps`, `lsof`, `security`). Injected so tests can script the answers.
public protocol CommandRunner: Sendable {
    /// Runs `executable` directly (no shell). Returns `nil` if it cannot start or exceeds `timeout`.
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandOutput?
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandOutput? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        // Drain both pipes concurrently: a full pipe would otherwise block the child forever.
        let stdout = PipeDrain(outPipe.fileHandleForReading)
        let stderr = PipeDrain(errPipe.fileHandleForReading)
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
