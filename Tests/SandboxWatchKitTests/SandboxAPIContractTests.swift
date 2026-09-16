import XCTest
@testable import SandboxWatchKit

final class SandboxAPIContractTests: XCTestCase {
    private let base = URL(string: "https://sandbox-dev.azurewebsites.net")!

    func testRouteURLs() {
        XCTAssertEqual(SandboxAPI.url(.snapshot, base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/snapshot")
        XCTAssertEqual(SandboxAPI.url(.apps, base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/apps")
        XCTAssertEqual(SandboxAPI.url(.healthz, base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/healthz")
        XCTAssertEqual(SandboxAPI.url(.changes(limit: 50), base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/changes?limit=50")
    }

    // A base URL with a trailing slash is what a human pastes from a browser. Producing
    // `//api/v1/snapshot` would 404 against the very server we are diagnosing.
    func testTrailingSlashInBaseURLIsHarmless() {
        let slashed = URL(string: "https://sandbox-dev.azurewebsites.net/")!
        XCTAssertEqual(SandboxAPI.url(.snapshot, base: slashed).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/snapshot")
    }

    // The server clamps out-of-range limits rather than rejecting them; the client clamps too,
    // so the URL it prints in an error is the limit the server actually used.
    func testChangeLimitIsClampedNotRejected() {
        XCTAssertEqual(SandboxAPI.url(.changes(limit: 0), base: base).query, "limit=1")
        XCTAssertEqual(SandboxAPI.url(.changes(limit: 9999), base: base).query, "limit=500")
    }

    func testOnlyHealthzGoesWithoutAToken() {
        XCTAssertTrue(SandboxAPI.requiresToken(.snapshot))
        XCTAssertTrue(SandboxAPI.requiresToken(.apps))
        XCTAssertTrue(SandboxAPI.requiresToken(.changes(limit: 50)))
        XCTAssertTrue(SandboxAPI.requiresToken(.refresh))
        XCTAssertFalse(SandboxAPI.requiresToken(.healthz))
    }

    func testDocumentedStatusCodesMapToModelledFailures() {
        XCTAssertNil(SandboxAPI.failure(forStatus: 200, body: Data()))
        XCTAssertEqual(SandboxAPI.failure(forStatus: 401, body: Data()), .unauthorised)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 503, body: Data()), .noSnapshot)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 404, body: Data()), .notFound)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 418, body: Data()), .unexpected(status: 418))
    }

    func testServerErrorKeepsTheDocumentedMessage() {
        let body = Data(#"{"error":"InternalError","message":"collector crashed"}"#.utf8)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 500, body: body), .serverError("collector crashed"))
    }

    // 503 is the "not collected yet" case the server documents as retryable. Saying so in the
    // message is what stops an operator from redeploying a working app.
    func testNoSnapshotExplainsItselfAsTemporary() {
        XCTAssertTrue(APIFailure.noSnapshot.explanation.lowercased().contains("not collected"))
        XCTAssertFalse(APIFailure.noSnapshot.explanation.lowercased().contains("redeploy"))
    }
}
