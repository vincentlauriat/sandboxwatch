import XCTest
@testable import SandboxWatchKit

final class StatusRowTests: XCTestCase {
    private func response(_ json: String) throws -> SnapshotResponse {
        try SandboxJSON.decoder.decode(SnapshotResponse.self, from: Data(json.utf8))
    }

    private func json(ageSeconds: Double, apps: String, budget: String, governance: String) -> String {
        """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": \(ageSeconds),
          "snapshot": {
            "identity": { "status": "ok", "data": { "subscriptionId": "sub-1", "resourceGroup": "rg" }, "message": null, "durationMs": 1 },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": \(apps),
            "budget": \(budget),
            "governance": \(governance),
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """
    }

    private let twoAppsOneStopped = #"""
    { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": null, "httpsOnly": true, "url": null }, { "name": "web", "state": "Stopped", "runtime": null, "httpsOnly": true, "url": null } ], "message": null, "durationMs": 1 }
    """#
    private let okBudget = #"{ "status": "ok", "data": { "amount": 50, "spend": 12.5, "percentage": 25, "thresholds": [] }, "message": null, "durationMs": 1 }"#
    private let okGovernance = #"{ "status": "ok", "data": {}, "message": null, "durationMs": 1 }"#
    private let deniedSection = #"{ "status": "denied", "data": null, "message": "AuthorizationFailed", "durationMs": 1 }"#

    func testAppsColumnCountsRunningOutOfTotal() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.apps, "1/2 up")
    }

    func testAgeIsHumanReadable() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 3900, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.age, "1h5m")
    }

    func testBudgetShowsThePercentage() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.budget, "25%")
    }

    // A denied section must never print as "0/0 up" or "0%". It prints why it is missing —
    // the client-side half of the rule the server guards with a test.
    func testDeniedSectionsPrintTheirReasonNotAZero() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: deniedSection, budget: deniedSection, governance: okGovernance)))

        XCTAssertEqual(row.apps, "denied")
        XCTAssertEqual(row.budget, "denied")
        XCTAssertNotEqual(row.apps, "0/0 up")
    }

    func testSectionsColumnNamesWhatDidNotCollect() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: deniedSection)))
        XCTAssertEqual(row.sections, "governance")
        XCTAssertNotNil(row.problem)
    }

    func testAllCollectedSectionsColumnSaysSo() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.sections, "all")
        XCTAssertNil(row.problem)
    }

    func testUnreachableSandboxStillGetsARow() {
        let row = StatusRow.unreachable(sandbox: "dev", failure: .transport("connection refused"))
        XCTAssertEqual(row.sandbox, "dev")
        XCTAssertEqual(row.age, "—")
        XCTAssertTrue(row.problem!.contains("connection refused"))
    }

    func testTableAlignsColumns() {
        let rows = [
            StatusRow(sandbox: "dev", age: "2m", apps: "1/2 up", budget: "25%", sections: "all", problem: nil),
            StatusRow(sandbox: "production", age: "1h5m", apps: "3/3 up", budget: "80%", sections: "governance", problem: "governance denied"),
        ]
        let lines = renderTable(rows).split(separator: "\n").map(String.init)

        XCTAssertTrue(lines[0].hasPrefix("SANDBOX"))
        // Every column starts at the same offset on every line.
        let offsets = lines.map { $0.range(of: "up")?.lowerBound }
        XCTAssertEqual(lines[1].distance(from: lines[1].startIndex, to: offsets[1]!),
                       lines[2].distance(from: lines[2].startIndex, to: offsets[2]!))
    }
}
