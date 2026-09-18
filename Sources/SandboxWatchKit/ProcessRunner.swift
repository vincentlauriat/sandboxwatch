import Foundation

/// What a finished process left behind.
public struct ProcessResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }

    /// stdout with its trailing newline removed — what `--query id -o tsv` is for.
    public var trimmedOutput: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The third seam, beside `HTTPClient` and `TokenStore`.
///
/// It exists so the guards can be proved without spawning `az`. A batch that can stop a running
/// web app must be testable without ever reaching Azure.
public protocol ProcessRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> ProcessResult
}

/// The real one, and — like `KeychainTokenStore` and `URLSessionHTTPClient` — the one the suite
/// never executes. It is proved by use.
public final class SystemProcessRunner: ProcessRunner, @unchecked Sendable {
    public init() {}

    /// An argv array, never a shell command string. A sandbox name and an app name come from the
    /// command line; a string handed to `sh -c` would let one of them become a second command.
    public func run(_ executable: String, _ arguments: [String]) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()

        // Read before waiting: a child that fills a 64 KB pipe buffer blocks forever if nobody
        // drains it, and `waitUntilExit` would never return.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self))
    }
}
