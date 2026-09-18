import XCTest
@testable import SandboxWatchKit

final class AzRunnerTests: XCTestCase {
    private func runner() -> MockProcessRunner {
        let mock = MockProcessRunner()
        mock.script(["az", "webapp"], exitCode: 0, stdout: "{}")
        return mock
    }

    // The whole point. A test that only checked the exit code would pass while restarting the
    // wrong app, in the wrong group, in the wrong subscription.
    func testTheArgvIsExactlyWhatWasMeasured() async throws {
        let mock = runner()

        _ = try await AzRunner.perform(
            .restart, app: "api", resourceGroup: "rg-dev-vincent-sandbox",
            subscriptionId: "sub-1", runner: mock)

        XCTAssertEqual(mock.invocations, [[
            "az", "webapp", "restart",
            "--name", "api",
            "--resource-group", "rg-dev-vincent-sandbox",
            "--subscription", "sub-1",
            "--only-show-errors",
            "--output", "json",
        ]])
    }

    // `--subscription` is what makes the subscription guard mean anything: without it, `az` acts
    // on whatever `az account set` last selected, and the guard would only have checked a value
    // it then failed to use.
    func testTheSubscriptionIsPassedExplicitlyAndNotLeftToAzureCliState() async throws {
        let mock = runner()
        _ = try await AzRunner.perform(
            .stop, app: "api", resourceGroup: "rg", subscriptionId: "sub-9", runner: mock)

        let argv = mock.invocations[0]
        let index = try XCTUnwrap(argv.firstIndex(of: "--subscription"))
        XCTAssertEqual(argv[index + 1], "sub-9")
    }

    func testEveryActionMapsToItsOwnSubcommand() async throws {
        for action in AzAction.allCases {
            let mock = runner()
            _ = try await AzRunner.perform(
                action, app: "api", resourceGroup: "rg", subscriptionId: "s", runner: mock)
            XCTAssertEqual(mock.invocations[0][2], action.rawValue)
        }
    }

    func testANonZeroExitIsReturnedNotThrown() async throws {
        // An `az` failure is a state the CLI prints and the journal records, not a crash.
        let mock = MockProcessRunner()
        mock.script(["az", "webapp"], exitCode: 3, stderr: "ERROR: Operation returned an invalid status 'Conflict'")

        let result = try await AzRunner.perform(
            .start, app: "api", resourceGroup: "rg", subscriptionId: "s", runner: mock)

        XCTAssertEqual(result.exitCode, 3)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.stderr.contains("Conflict"))
    }
}
