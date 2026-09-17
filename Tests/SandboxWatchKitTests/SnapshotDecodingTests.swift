import XCTest
@testable import SandboxWatchKit

final class SnapshotDecodingTests: XCTestCase {
    /// Copied from a real `GET /api/v1/snapshot` response, with governance flipped to denied —
    /// the shape the founding incident produces.
    ///
    /// **Copied, not written.** Batch 1's fixtures were composed from the spec, so they agreed
    /// with a model that had also been composed from the spec, and 99 green tests proved only
    /// that the client was consistent with its own belief. `budget` is a list, a probe's key is
    /// `app`, a plan counts `sites`, a role carries `roleDefinitionId`, and `detail` mixes
    /// strings, numbers and nulls — none of which the invented fixtures contained.
    static let json = """
    {
      "collectedAt": "2026-09-16T08:00:00.000Z",
      "ageSeconds": 142.7,
      "snapshot": {
        "identity": { "available": true, "subscriptionId": "sub-1", "resourceGroup": "rg-sandbox" },
        "resources": { "status": "ok", "data": [ { "name": "api", "type": "Microsoft.Web/sites", "location": "westeurope", "tags": {} } ], "message": null, "durationMs": 120 },
        "plans": { "status": "ok", "data": [ { "name": "plan-1", "tier": "Basic", "size": "B1", "sites": 2, "status": "Ready", "location": "westeurope" } ], "message": null, "durationMs": 90 },
        "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "plan": "plan-1", "runtime": "NODE|20-lts", "httpsOnly": true, "alwaysOn": false, "url": "https://api.azurewebsites.net", "location": "westeurope" } ], "message": null, "durationMs": 110 },
        "budget": { "status": "ok", "data": [ { "name": "monthly", "amount": 50, "currency": "EUR", "spent": 12.5, "percent": 25, "timeGrain": "Monthly", "thresholds": [80, 100] } ], "message": null, "durationMs": 300 },
        "governance": { "status": "denied", "data": null, "message": "AuthorizationFailed", "durationMs": 45 },
        "probes": { "status": "ok", "data": [ { "app": "api", "url": "https://api.azurewebsites.net", "httpStatus": 200, "latencyMs": 87, "error": null } ], "message": null, "durationMs": 400 }
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
        XCTAssertEqual(snapshot.probes.fold(ok: { $0.first?.httpStatus }, unavailable: { _ in nil }), 200)
        XCTAssertEqual(snapshot.plans.fold(ok: { $0.first?.sites }, unavailable: { _ in nil }), 2)
        // A list on the wire: one budget today, several possible.
        XCTAssertEqual(snapshot.budget.fold(ok: { $0.first?.percent }, unavailable: { _ in nil }), 25)
        // Not a Section: identity is configuration and can never be denied.
        XCTAssertEqual(snapshot.identity.subscriptionId, "sub-1")
        XCTAssertEqual(snapshot.identity.resourceGroup, "rg-sandbox")
        XCTAssertTrue(snapshot.identity.available)
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
