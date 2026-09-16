import XCTest
@testable import SandboxWatchKit

final class SnapshotDecodingTests: XCTestCase {
    /// A snapshot where governance is denied and everything else collected — the shape the
    /// founding incident produces.
    static let json = """
    {
      "collectedAt": "2026-09-16T08:00:00.000Z",
      "ageSeconds": 142.7,
      "snapshot": {
        "identity": { "status": "ok", "data": { "subscriptionId": "sub-1", "resourceGroup": "rg-sandbox" }, "message": null, "durationMs": 10 },
        "resources": { "status": "ok", "data": [ { "name": "api", "type": "Microsoft.Web/sites", "location": "westeurope" } ], "message": null, "durationMs": 120 },
        "plans": { "status": "ok", "data": [ { "name": "plan-1", "tier": "Basic", "size": "B1", "appCount": 2, "status": "Ready" } ], "message": null, "durationMs": 90 },
        "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": "NODE|20-lts", "httpsOnly": true, "url": "https://api.azurewebsites.net" } ], "message": null, "durationMs": 110 },
        "budget": { "status": "ok", "data": { "amount": 50, "spend": 12.5, "percentage": 25, "thresholds": [80, 100] }, "message": null, "durationMs": 300 },
        "governance": { "status": "denied", "data": null, "message": "AuthorizationFailed", "durationMs": 45 },
        "probes": { "status": "ok", "data": [ { "name": "api", "url": "https://api.azurewebsites.net", "statusCode": 200, "latencyMs": 87 } ], "message": null, "durationMs": 400 }
      }
    }
    """

    func testDecodesTheDocumentedEnvelope() throws {
        let response = try SandboxJSON.decoder.decode(
            SnapshotResponse.self, from: Data(Self.json.utf8))

        XCTAssertEqual(response.ageSeconds, 142.7, accuracy: 0.001)
        XCTAssertEqual(response.collectedAt.timeIntervalSince1970, 1789545600, accuracy: 1)
    }

    func testCollectedSectionsCarryTheirPayload() throws {
        let snapshot = try SandboxJSON.decoder
            .decode(SnapshotResponse.self, from: Data(Self.json.utf8)).snapshot

        XCTAssertEqual(snapshot.apps.fold(ok: { $0.map(\.name) }, unavailable: { _ in [] }), ["api"])
        XCTAssertEqual(snapshot.probes.fold(ok: { $0.first?.statusCode }, unavailable: { _ in nil }), 200)
        XCTAssertEqual(snapshot.budget.fold(ok: { $0.percentage }, unavailable: { _ in nil }), 25)
        // `ok` returns a non-optional String here, so the unavailable branch must match it:
        // `fold` deliberately forces both branches to agree on one type.
        XCTAssertEqual(snapshot.identity.fold(ok: { $0.subscriptionId }, unavailable: { $0 }), "sub-1")
    }

    func testDeniedGovernanceDoesNotLookLikeAnEmptyGovernance() throws {
        let snapshot = try SandboxJSON.decoder
            .decode(SnapshotResponse.self, from: Data(Self.json.utf8)).snapshot

        XCTAssertFalse(snapshot.governance.isOK)
        XCTAssertEqual(snapshot.governance.unavailableReason, "AuthorizationFailed")
    }

    func testUnavailableSectionNamesAreListed() throws {
        let snapshot = try SandboxJSON.decoder
            .decode(SnapshotResponse.self, from: Data(Self.json.utf8)).snapshot

        XCTAssertEqual(snapshot.unavailableSections, ["governance"])
    }
}
