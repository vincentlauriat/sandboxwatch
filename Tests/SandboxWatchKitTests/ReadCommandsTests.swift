import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class ReadCommandsTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "t", http: mock)
    }

    private func healthySnapshot(ageSeconds: Double = 60) -> String {
        """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": \(ageSeconds),
          "snapshot": {
            "identity": { "status": "ok", "data": { "subscriptionId": "sub-1", "resourceGroup": "rg" }, "message": null, "durationMs": 1 },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": null, "httpsOnly": true, "url": null } ], "message": null, "durationMs": 1 },
            "budget": { "status": "ok", "data": { "amount": 50, "spend": 5, "percentage": 10, "thresholds": [] }, "message": null, "durationMs": 1 },
            "governance": { "status": "ok", "data": {}, "message": null, "durationMs": 1 },
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """
    }

    func testStatusRendersOneRowPerSandbox() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthySnapshot())

        let output = await ReadCommands.status(sandboxes: ["dev", "prod"]) { _ in self.client(mock) }

        XCTAssertTrue(output.contains("SANDBOX"))
        XCTAssertTrue(output.contains("dev"))
        XCTAssertTrue(output.contains("prod"))
    }

    // One unreachable sandbox must not take the others down with it: `--all` is exactly the
    // moment you are looking for the one that is broken.
    func testStatusKeepsGoingWhenOneSandboxIsUnreachable() async {
        let good = MockHTTPClient()
        good.stub(path: "/api/v1/snapshot", status: 200, json: healthySnapshot())
        let bad = MockHTTPClient()
        bad.fail(path: "/api/v1/snapshot", message: "connection refused")

        let output = await ReadCommands.status(sandboxes: ["dev", "broken"]) { name in
            self.client(name == "dev" ? good : bad)
        }

        XCTAssertTrue(output.contains("dev"))
        XCTAssertTrue(output.contains("broken"))
        XCTAssertTrue(output.contains("connection refused"))
    }

    func testDoctorPrintsHeadlineAndNextStep() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 503, json: #"{"error":"NoSnapshot"}"#)

        let output = await ReadCommands.doctor(sandbox: "dev", client: client(mock))

        XCTAssertTrue(output.contains("has not completed a collection"))
        XCTAssertTrue(output.contains("do not redeploy"))
    }

    func testChangesPrintsNewEventsNewestFirst() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: """
        { "limit": 50, "events": [
          {"at":"2026-09-16T09:00:00.000Z","type":"role_added","subject":"alice"},
          {"at":"2026-09-16T08:00:00.000Z","type":"probe_status_changed","subject":"api"}
        ] }
        """)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")
        // Seed the cursor at the older event so the newer one is the only thing reported.
        try cursors.setMark(
            ChangeMark(at: ISO8601DateFormatter().date(from: "2026-09-16T08:00:00Z")!,
                       type: "probe_status_changed", subject: "api"),
            for: "dev")

        let output = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: true)

        XCTAssertTrue(output.contains("role_added"))
        XCTAssertFalse(output.contains("probe_status_changed"))
    }

    // The overflow signal must reach the operator. A quiet truncation is the failure mode a
    // change-detection tool can least afford.
    func testChangesSaysSoWhenThePageDidNotReachBackFarEnough() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: """
        { "limit": 500, "events": [
          {"at":"2026-09-16T09:00:00.000Z","type":"role_added","subject":"alice"}
        ] }
        """)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")
        try cursors.setMark(
            ChangeMark(at: ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z")!,
                       type: "gone", subject: "gone"),
            for: "dev")

        let output = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 500, advance: true)

        XCTAssertTrue(output.lowercased().contains("older events were not returned"))
    }

    func testChangesOnAQuietSandboxSaysNothingChanged() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: #"{ "limit": 50, "events": [] }"#)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")

        let output = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: true)

        XCTAssertTrue(output.lowercased().contains("nothing"))
    }

    func testChangesAdvancesTheCursorOnlyWhenAsked() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: """
        { "limit": 50, "events": [ {"at":"2026-09-16T09:00:00.000Z","type":"role_added","subject":"alice"} ] }
        """)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")

        _ = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: false)
        XCTAssertNil(try cursors.mark(for: "dev"))

        _ = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: true)
        XCTAssertNotNil(try cursors.mark(for: "dev"))
    }
}
