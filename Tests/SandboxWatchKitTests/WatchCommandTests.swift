import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class WatchCommandTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!
    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "sbw-watch-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "t", http: mock)
    }

    private let healthyJSON = """
    {
      "collectedAt": "2026-09-16T08:00:00.000Z",
      "ageSeconds": 60,
      "snapshot": {
        "identity": { "available": true, "subscriptionId": "sub-1", "resourceGroup": "rg" },
        "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "apps": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "budget": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "governance": { "status": "ok", "data": {}, "message": null, "durationMs": 1 },
        "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
      }
    }
    """

    func testFirstPollSaysNothing() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)

        let line = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: LiaisonStore(directory: directory),
            at: Date(timeIntervalSince1970: 1_789_000_000))

        XCTAssertNil(line)
    }

    func testTwoFailedPollsAnnounceTheTransitionOnce() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        let store = LiaisonStore(directory: directory)
        let t0 = Date(timeIntervalSince1970: 1_789_000_000)

        _ = try await WatchCommands.pollOnce(sandbox: "dev", client: client(mock), liaison: store, at: t0)

        mock.stub(path: "/api/v1/snapshot", status: 401, json: "{}")
        let first = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: store, at: t0.addingTimeInterval(300))
        let second = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: store, at: t0.addingTimeInterval(600))
        let third = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: store, at: t0.addingTimeInterval(900))

        XCTAssertNil(first, "one reading is not evidence")
        XCTAssertNotNil(second)
        XCTAssertTrue(second!.contains("token"), "the line names what changed: \(second!)")
        XCTAssertNil(third, "a steady state is not announced again")
    }
}
