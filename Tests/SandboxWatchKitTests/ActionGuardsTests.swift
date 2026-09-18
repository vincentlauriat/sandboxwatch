import XCTest
@testable import SandboxWatchKit

/// The only batch that can break something real. Each of these proves a guard fails **closed**:
/// the refusal is returned *and* nothing reached a web app. A guard that refuses after spawning
/// `az` has already done the damage it exists to prevent.
final class ActionGuardsTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!
    /// The real subscription behind `sandboxmgr`, so a test that accidentally passed would be
    /// passing against the truth rather than against a placeholder.
    private let subscription = "3e0041cf-c56e-447a-917f-15d5ac615f6f"

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "t", http: mock)
    }

    private func snapshotJSON(ageSeconds: Double = 12, subscriptionId: String) -> String {
        """
        {
          "collectedAt": "2026-09-18T08:00:00.000Z",
          "ageSeconds": \(ageSeconds),
          "snapshot": {
            "identity": { "available": true, "subscriptionId": "\(subscriptionId)", "resourceGroup": "rg-dev-vincent-sandbox" },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": null, "httpsOnly": true, "url": null } ], "message": null, "durationMs": 1 },
            "budget": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "governance": { "status": "ok", "data": {}, "message": null, "durationMs": 1 },
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """
    }

    /// Everything satisfied, unless a test overrides one piece.
    private func healthyWorld(
        refreshHeaders: [String: String] = [:],
        subscriptionId: String? = nil
    ) -> (MockHTTPClient, MockProcessRunner) {
        let http = MockHTTPClient()
        let json = snapshotJSON(subscriptionId: subscriptionId ?? subscription)
        http.stub(path: "/api/v1/snapshot", status: 200, json: json)
        http.stub(path: "/api/v1/refresh", status: 200, json: json, headers: refreshHeaders)

        let az = MockProcessRunner()
        az.script(["az", "account", "show"], stdout: "\(subscription)\n")
        return (http, az)
    }

    private func check(
        _ http: MockHTTPClient, _ az: MockProcessRunner
    ) async -> Result<ActionContext, ActionRefusal> {
        await ActionGuards.check(sandbox: "dev", app: "api", client: client(http), runner: az)
    }

    // The executable is `/usr/bin/env`, so the argv has to name `az` itself. Asserting only the
    // subcommand let `env account show` — a command that does not exist — pass a whole suite.
    func testThePreflightArgvNamesAzItself() async {
        let (http, az) = healthyWorld()

        _ = await check(http, az)

        XCTAssertEqual(az.invocations.first, [
            "az", "account", "show", "--query", "id", "--output", "tsv", "--only-show-errors",
        ])
    }

    // MARK: - Guard 1, subscription

    // `az` points wherever `az account set` last left it, which has nothing to do with the sandbox
    // you are looking at. Without this, `sbw restart api` restarts a same-named web app elsewhere.
    func testAMismatchedSubscriptionRefusesAndNamesBothValues() async {
        let (http, az) = healthyWorld()
        az.script(["az", "account", "show"], stdout: "11111111-2222-3333-4444-555555555555\n")

        let result = await check(http, az)

        guard case .failure(.wrongSubscription(let expected, let actual)) = result else {
            return XCTFail("expected a subscription refusal, got \(result)")
        }
        XCTAssertEqual(expected, subscription)
        XCTAssertEqual(actual, "11111111-2222-3333-4444-555555555555")
        XCTAssertFalse(az.didTouchAWebApp, "refused, but az had already been let near a web app")
    }

    // MARK: - Guard 3, non-interactivity — runs first

    // The measured shape, 2026-09-18: exit 1, empty stdout, this exact stderr, and no device-code
    // flow. It runs before anything else because it is the cheapest and most certain refusal, and
    // because nothing should touch the network until `az` has proved it can answer at all.
    func testNotBeingLoggedInRefusesBeforeAnythingElseRuns() async {
        let (http, az) = healthyWorld()
        az.script(["az", "account", "show"], exitCode: 1,
                  stderr: "ERROR: Please run 'az login' to setup account.")

        let result = await check(http, az)

        guard case .failure(.notLoggedIn(let detail)) = result else {
            return XCTFail("expected a login refusal, got \(result)")
        }
        XCTAssertTrue(detail.contains("az login"), detail)
        XCTAssertFalse(az.didTouchAWebApp)
        XCTAssertTrue(http.requestedPaths.isEmpty, "the network was touched before az could answer")
    }

    // MARK: - Guard 2, freshness

    func testAFailedRefreshRefusesRatherThanActingOnAStaleSnapshot() async {
        let (http, az) = healthyWorld()
        http.stub(path: "/api/v1/refresh", status: 503, json: #"{"error":"NoSnapshot"}"#)

        let result = await check(http, az)

        guard case .failure(.couldNotConfirmFreshness) = result else {
            return XCTFail("expected a freshness refusal, got \(result)")
        }
        XCTAssertFalse(az.didTouchAWebApp)
    }

    // The one that is easy to skip and must not be. Two actions in quick succession mean the
    // second refresh silently no-ops; a confirmation that said nothing about it would imply
    // freshly verified state — the single thing this guard exists to guarantee.
    func testTheSkippedRefreshHeaderReachesTheContext() async {
        let (http, az) = healthyWorld(refreshHeaders: ["X-Refresh-Skipped": "true"])

        let result = await check(http, az)

        guard case .success(let context) = result else {
            return XCTFail("expected a context, got \(result)")
        }
        XCTAssertTrue(context.refreshSkipped)
    }

    func testAHeaderWithUnexpectedCasingIsStillRead() async {
        // URLSession does not promise a casing, and an exact-match lookup here would be a silent
        // bug in the one guard that must never be silent.
        let (http, az) = healthyWorld(refreshHeaders: ["x-refresh-skipped": "true"])

        guard case .success(let context) = await check(http, az) else {
            return XCTFail("expected a context")
        }
        XCTAssertTrue(context.refreshSkipped)
    }

    // MARK: - All three satisfied

    func testAllThreeSatisfiedYieldsAContextCarryingAgeAndState() async {
        let (http, az) = healthyWorld()

        guard case .success(let context) = await check(http, az) else {
            return XCTFail("expected a context")
        }
        XCTAssertEqual(context.ageSeconds, 12)
        XCTAssertEqual(context.appState, "Running")
        XCTAssertEqual(context.resourceGroup, "rg-dev-vincent-sandbox")
        XCTAssertEqual(context.subscriptionId, subscription)
        XCTAssertFalse(context.refreshSkipped)
    }

    func testAnAppThatIsNotInTheSnapshotIsRefused() async {
        // Restarting a name the sandbox does not know is either a typo or the wrong sandbox.
        // Both deserve a refusal rather than an `az` error five seconds later.
        let (http, az) = healthyWorld()

        let result = await ActionGuards.check(
            sandbox: "dev", app: "does-not-exist", client: client(http), runner: az)

        guard case .failure(.unknownApp(let name)) = result else {
            return XCTFail("expected an unknown-app refusal, got \(result)")
        }
        XCTAssertEqual(name, "does-not-exist")
        XCTAssertFalse(az.didTouchAWebApp)
    }

    func testASnapshotWithoutAnAvailableIdentityIsRefused() async {
        // `identity.available == false` means the collector could not resolve which subscription
        // it is watching. Comparing against an unknown is not a check.
        let (http, az) = healthyWorld()
        http.stub(path: "/api/v1/refresh", status: 200, json: """
        {
          "collectedAt": "2026-09-18T08:00:00.000Z",
          "ageSeconds": 12,
          "snapshot": {
            "identity": { "available": false, "subscriptionId": "", "resourceGroup": "" },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "budget": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "governance": { "status": "ok", "data": {}, "message": null, "durationMs": 1 },
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """)

        let result = await check(http, az)

        guard case .failure(.identityUnavailable) = result else {
            return XCTFail("expected an identity refusal, got \(result)")
        }
        XCTAssertFalse(az.didTouchAWebApp)
    }
}
