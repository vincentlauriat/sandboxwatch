import XCTest
@testable import SandboxWatchKit

final class ProcessRunnerTests: XCTestCase {
    func testTheMockRecordsExactlyTheArgumentsItWasGiven() async throws {
        let mock = MockProcessRunner()
        mock.script(["account", "show"], stdout: "sub-1\n")

        _ = try await mock.run("az", ["account", "show", "--query", "id", "-o", "tsv"])

        XCTAssertEqual(mock.invocations, [["account", "show", "--query", "id", "-o", "tsv"]])
    }

    // A mock that answers anything proves nothing. This batch restarts web apps; a test that
    // passed while the code built the wrong command line would be worse than no test.
    func testAnUnscriptedInvocationIsAFailureNotAnEmptyResult() async {
        let mock = MockProcessRunner()
        do {
            _ = try await mock.run("az", ["webapp", "restart", "--name", "api"])
            XCTFail("an unscripted call must not silently succeed")
        } catch let error as MockProcessRunner.Unscripted {
            XCTAssertTrue(error.description.contains("webapp restart"), error.description)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testALaterScriptOverridesAnEarlierOne() async throws {
        let mock = MockProcessRunner()
        mock.script(["account", "show"], exitCode: 1, stderr: "ERROR: Please run 'az login' to setup account.")
        mock.script(["account", "show"], exitCode: 0, stdout: "sub-1\n")

        let result = try await mock.run("az", ["account", "show"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "sub-1")
    }

    func testDidTouchAWebAppIsFalseUntilSomethingActuallyRuns() async throws {
        let mock = MockProcessRunner()
        mock.script(["account", "show"], stdout: "sub-1\n")
        _ = try await mock.run("az", ["account", "show"])
        XCTAssertFalse(mock.didTouchAWebApp)
    }

    // MARK: - The real runner

    // `/bin/echo` is neither the network, the Keychain, nor `az`, so running it breaks no rule —
    // and it proves what matters: the argv reaches the process as separate words, stdout comes
    // back, and the exit code is real. The previous test here asserted that a type's own name did
    // not contain "Shell", which could not fail.
    func testTheRealRunnerPassesArgvAsWordsAndCapturesStdout() async throws {
        let result = try await SystemProcessRunner().run("/bin/echo", ["one two", "three"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.trimmedOutput, "one two three",
                       "a shell would have split 'one two' into two arguments")
    }

    func testTheRealRunnerReportsANonZeroExit() async throws {
        let result = try await SystemProcessRunner().run("/bin/sh", ["-c", "exit 7"])
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.succeeded)
    }

    // The reason `run` drains the pipes before `waitUntilExit`: a child that fills the 64 KB pipe
    // buffer blocks forever if nobody is reading, and the wait never returns. 200 KB is well past
    // the buffer, so this test hangs rather than fails if that order is ever reversed.
    func testAChildThatOutwritesThePipeBufferDoesNotDeadlock() async throws {
        let result = try await SystemProcessRunner().run(
            "/bin/dd", ["if=/dev/zero", "bs=1024", "count=200"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 200 * 1024)
    }
}
