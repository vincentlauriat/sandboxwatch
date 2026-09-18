import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class ActionCommandsTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!
    private let subscription = "3e0041cf-c56e-447a-917f-15d5ac615f6f"
    private var journalPath: String!

    override func setUp() {
        super.setUp()
        journalPath = NSTemporaryDirectory() + "sbw-actions-\(UUID().uuidString)/actions.jsonl"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: (journalPath as NSString).deletingLastPathComponent)
        super.tearDown()
    }

    private func snapshotJSON(subscriptionId: String) -> String {
        """
        {
          "collectedAt": "2026-09-18T08:00:00.000Z", "ageSeconds": 9,
          "snapshot": {
            "identity": { "available": true, "subscriptionId": "\(subscriptionId)", "resourceGroup": "rg" },
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

    private func world(subscriptionId: String? = nil) -> (MockHTTPClient, MockProcessRunner) {
        let http = MockHTTPClient()
        let json = snapshotJSON(subscriptionId: subscriptionId ?? subscription)
        http.stub(path: "/api/v1/snapshot", status: 200, json: json)
        http.stub(path: "/api/v1/refresh", status: 200, json: json)

        let az = MockProcessRunner()
        az.script(["az", "account", "show"], stdout: "\(subscription)\n")
        az.script(["az", "webapp"], exitCode: 0, stdout: "{}")
        return (http, az)
    }

    private func perform(
        _ http: MockHTTPClient, _ az: MockProcessRunner, confirmed: Bool = true, app: String = "api"
    ) async -> String {
        await ActionCommands.perform(
            sandbox: "dev", app: app, action: .restart,
            client: SandboxAPIClient(baseURL: base, token: "t", http: http),
            runner: az, journal: ActionJournal(path: journalPath), confirmed: confirmed)
    }

    func testAConfirmedActionRunsAndIsJournalled() async {
        let (http, az) = world()

        let output = await perform(http, az)

        XCTAssertTrue(az.didTouchAWebApp)
        XCTAssertTrue(output.contains("restart"), output)
        let records = ActionJournal(path: journalPath).records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].outcome, .performed(exitCode: 0))
    }

    func testAnUnconfirmedActionDoesNotRun() async {
        let (http, az) = world()

        let output = await perform(http, az, confirmed: false)

        XCTAssertFalse(az.didTouchAWebApp, "an unconfirmed action reached az")
        XCTAssertTrue(output.lowercased().contains("cancelled"), output)
    }

    // Both halves matter: nothing ran, and the refusal is on the record.
    func testARefusedGuardIsJournalledAndNoAzRuns() async {
        let (http, az) = world(subscriptionId: "11111111-2222-3333-4444-555555555555")

        let output = await perform(http, az)

        XCTAssertFalse(az.didTouchAWebApp)
        XCTAssertTrue(output.contains("11111111-2222-3333-4444-555555555555"), output)
        let records = ActionJournal(path: journalPath).records()
        XCTAssertEqual(records.count, 1)
        guard case .refused(let why) = records[0].outcome else {
            return XCTFail("the refusal was not journalled: \(records[0].outcome)")
        }
        XCTAssertTrue(why.contains("subscription"), why)
    }

    // The freshness guard's whole purpose: a confirmation must never imply state it did not check.
    func testTheConfirmationShowsTheAgeAndTheCurrentState() async {
        let (http, az) = world()

        let output = await ActionCommands.describe(
            sandbox: "dev", app: "api", action: .restart,
            client: SandboxAPIClient(baseURL: base, token: "t", http: http), runner: az)

        XCTAssertTrue(output.contains("Running"), output)
        XCTAssertTrue(output.contains("9"), "the age must be shown: \(output)")
    }

    func testASkippedRefreshIsSaidOutLoudInTheConfirmation() async {
        let http = MockHTTPClient()
        let json = snapshotJSON(subscriptionId: subscription)
        http.stub(path: "/api/v1/snapshot", status: 200, json: json)
        http.stub(path: "/api/v1/refresh", status: 200, json: json,
                  headers: ["X-Refresh-Skipped": "true"])
        let az = MockProcessRunner()
        az.script(["az", "account", "show"], stdout: "\(subscription)\n")

        let output = await ActionCommands.describe(
            sandbox: "dev", app: "api", action: .restart,
            client: SandboxAPIClient(baseURL: base, token: "t", http: http), runner: az)

        XCTAssertTrue(output.lowercased().contains("not refreshed"), output)
    }
}
