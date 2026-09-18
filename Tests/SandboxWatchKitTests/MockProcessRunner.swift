import Foundation
@testable import SandboxWatchKit

/// A `ProcessRunner` that answers only what it was told to answer.
///
/// An unscripted invocation is a failure, not an empty result: a mock that replies to anything
/// would let a test pass while the code under it built the wrong command line — which, for a batch
/// whose whole job is to restart the right web app, is the failure mode that matters.
final class MockProcessRunner: ProcessRunner, @unchecked Sendable {
    struct Unscripted: Error, CustomStringConvertible {
        let arguments: [String]
        var description: String { "no script for: \(arguments.joined(separator: " "))" }
    }

    private var scripts: [(match: [String], result: ProcessResult)] = []
    private(set) var invocations: [[String]] = []

    /// `match` is a prefix: scripting `["account", "show"]` answers any invocation starting with it.
    /// A later script wins, so a test can set a baseline and then override one call.
    func script(_ match: [String], exitCode: Int32 = 0, stdout: String = "", stderr: String = "") {
        scripts.append((match, ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr)))
    }

    func run(_ executable: String, _ arguments: [String]) async throws -> ProcessResult {
        invocations.append(arguments)
        guard let script = scripts.last(where: { arguments.starts(with: $0.match) }) else {
            throw Unscripted(arguments: arguments)
        }
        return script.result
    }

    /// The question every guard test asks: did anything reach the web app before the refusal?
    var didTouchAWebApp: Bool { invocations.contains { $0.first == "webapp" } }
}
