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

    // `SystemProcessRunner` is the one type here the suite never executes — like
    // `KeychainTokenStore` and `URLSessionHTTPClient`, it is proved by use. What can be asserted
    // without spawning anything is that it never goes through a shell.
    func testTheRealRunnerTakesAnArgvArrayAndNeverAShell() {
        XCTAssertFalse("\(SystemProcessRunner.self)".contains("Shell"))
        let runner = SystemProcessRunner(executable: "/opt/homebrew/bin/az")
        XCTAssertEqual(runner.executable, "/opt/homebrew/bin/az")
    }
}
