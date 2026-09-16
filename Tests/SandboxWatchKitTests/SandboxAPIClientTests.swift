import XCTest
@testable import SandboxWatchKit

final class SandboxAPIClientTests: XCTestCase {
    private let base = URL(string: "https://sandbox-dev.azurewebsites.net")!

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "secret-token", http: mock)
    }

    func testSnapshotSendsTheTokenHeader() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: SnapshotDecodingTests.json)

        _ = try await client(mock).snapshot()

        XCTAssertEqual(mock.requests.first?.headers[SandboxAPI.tokenHeader], "secret-token")
    }

    func testHealthzGoesWithoutTheToken() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/healthz", status: 200, json: #"{"status":"ok","uptimeSeconds":1234}"#)

        let health = try await client(mock).health()

        XCTAssertEqual(health.status, "ok")
        XCTAssertNil(mock.requests.first?.headers[SandboxAPI.tokenHeader])
    }

    func testUnauthorisedBecomesAModelledFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 401,
                  json: #"{"error":"Unauthorized","message":"Missing or invalid X-Sandbox-Token header"}"#)

        await XCTAssertThrowsAPIFailure(.unauthorised) { try await self.client(mock).snapshot() }
    }

    func testNoSnapshotYetBecomesAModelledFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 503, json: #"{"error":"NoSnapshot"}"#)

        await XCTAssertThrowsAPIFailure(.noSnapshot) { try await self.client(mock).snapshot() }
    }

    func testTransportFailureIsWrappedNotLeaked() async {
        let mock = MockHTTPClient()
        mock.fail(path: "/api/v1/snapshot", message: "connection refused")

        await XCTAssertThrowsAPIFailure(.transport("connection refused")) {
            try await self.client(mock).snapshot()
        }
    }

    // A 200 whose body does not match the contract must not read as a valid empty snapshot.
    func testMalformedBodyIsItsOwnFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: #"{"unexpected":true}"#)

        do {
            _ = try await client(mock).snapshot()
            XCTFail("expected a malformed failure")
        } catch let failure as APIFailure {
            guard case .malformed = failure else { return XCTFail("got \(failure)") }
        } catch {
            XCTFail("got \(error)")
        }
    }

    func testAppsUsesTheNarrowRoute() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/apps", status: 200, json: """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": 10,
          "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": null, "httpsOnly": true, "url": null } ], "message": null, "durationMs": 5 },
          "probes": { "status": "ok", "data": [ { "name": "api", "url": null, "statusCode": 200, "latencyMs": 12 } ], "message": null, "durationMs": 7 }
        }
        """)

        let response = try await client(mock).apps()

        XCTAssertEqual(mock.requests.first?.url.path, "/api/v1/apps")
        XCTAssertEqual(response.apps.fold(ok: { $0.count }, unavailable: { _ in -1 }), 1)
    }
}

/// Small helper so each expectation reads as one line.
func XCTAssertThrowsAPIFailure(
    _ expected: APIFailure,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch let failure as APIFailure {
        XCTAssertEqual(failure, expected, file: file, line: line)
    } catch {
        XCTFail("expected \(expected), got \(error)", file: file, line: line)
    }
}
