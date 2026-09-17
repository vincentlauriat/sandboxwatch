import XCTest
@testable import SandboxWatchKit

final class DoctorTests: XCTestCase {
    private let base = URL(string: "https://sandbox-dev.azurewebsites.net")!

    private func doctor(_ mock: MockHTTPClient, staleAfter: Double = 1800) -> Doctor {
        Doctor(client: SandboxAPIClient(baseURL: base, token: "t", http: mock),
               staleAfterSeconds: staleAfter)
    }

    private func snapshotJSON(ageSeconds: Double, governance: String) -> String {
        """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": \(ageSeconds),
          "snapshot": {
            "identity": { "available": true, "subscriptionId": "sub-1", "resourceGroup": "rg" },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "budget": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "governance": \(governance),
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """
    }

    private let okGovernance = #"{ "status": "ok", "data": {}, "message": null, "durationMs": 1 }"#
    private let deniedGovernance = #"{ "status": "denied", "data": null, "message": "AuthorizationFailed", "durationMs": 1 }"#

    func testUnreachableAppIsTheOnlyFinding() async {
        let mock = MockHTTPClient()
        mock.fail(path: "/api/v1/snapshot", message: "connection refused")

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings.count, 1)
        guard case .unreachable = findings[0] else { return XCTFail("got \(findings)") }
    }

    func testRefusedTokenIsTheOnlyFinding() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 401, json: #"{"error":"Unauthorized"}"#)

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings, [.unauthorised])
    }

    // 503 means the app is up and has simply not finished a first collection. Reporting it as
    // a broken deployment is what sends someone redeploying a working app.
    func testNoSnapshotYetSaysWaitNotRedeploy() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 503, json: #"{"error":"NoSnapshot"}"#)

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings, [.notCollectedYet])
        // Not "must not contain the word redeploy": the best possible message contains it,
        // as a warning. What matters is that it tells the operator to wait and says plainly
        // that redeploying is the wrong move.
        let step = findings[0].nextStep!.lowercased()
        XCTAssertTrue(step.contains("wait"))
        XCTAssertTrue(step.contains("do not redeploy"))
    }

    func testHealthySnapshotReportsItsAge() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: snapshotJSON(ageSeconds: 120, governance: okGovernance))

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings.count, 1)
        guard case .healthy(let age) = findings[0] else { return XCTFail("got \(findings)") }
        XCTAssertEqual(age, 120, accuracy: 0.001)
    }

    // The verdict that matters most. A denied section right after granting a role is the
    // documented managed-identity propagation delay — up to 24 hours — not a failure. The
    // next step must say so, or the operator repeats the assignment that already worked.
    func testDeniedSectionsPointAtRolePropagationNotFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: snapshotJSON(ageSeconds: 60, governance: deniedGovernance))

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings, [.sectionsUnavailable(["governance"])])
        XCTAssertTrue(findings[0].nextStep!.contains("24"))
    }

    func testStaleSnapshotIsReportedBeforeItsDeniedSections() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: snapshotJSON(ageSeconds: 7200, governance: deniedGovernance))

        let findings = await doctor(mock).diagnose()

        // Both are true, and staleness comes first: a two-hour-old reading of "denied" may
        // describe a state that no longer exists.
        XCTAssertEqual(findings.count, 2)
        guard case .stale = findings[0] else { return XCTFail("got \(findings)") }
        XCTAssertEqual(findings[1], .sectionsUnavailable(["governance"]))
    }

    func testEveryFindingKnowsWhetherItIsAProblem() {
        XCTAssertFalse(Doctor.Finding.healthy(ageSeconds: 10).isProblem)
        XCTAssertTrue(Doctor.Finding.unauthorised.isProblem)
        XCTAssertTrue(Doctor.Finding.sectionsUnavailable(["governance"]).isProblem)
        XCTAssertTrue(Doctor.Finding.stale(ageSeconds: 9999).isProblem)
    }
}
