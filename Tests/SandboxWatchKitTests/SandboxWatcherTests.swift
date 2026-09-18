import XCTest
@testable import SandboxWatchKit

final class SandboxWatcherTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!
    private let t0 = Date(timeIntervalSince1970: 1_789_000_000)
    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "sbw-watcher-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "t", http: mock)
    }

    private var liaison: LiaisonStore { LiaisonStore(directory: directory + "/liaison") }
    private var cursors: CursorStore { CursorStore(directory: directory + "/cursors") }

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

    private func changesJSON(_ events: String) -> String {
        #"{"limit": 50, "events": [\#(events)]}"#
    }

    /// The first poll establishes the cursor from the newest event it sees. An empty page marks
    /// nothing, so a test that wants "an event arrived since last time" must seed a real one.
    private let baselineEvent = """
    { "at": "2026-09-16T08:00:00.000Z", "type": "probe_status_changed", "subject": "api" }
    """

    private let criticalEvent = """
    { "at": "2026-09-16T09:18:01.000Z", "type": "collector_access_lost", "subject": "governance",
      "detail": { "message": "AuthorizationFailed" }, "collector": "governance",
      "severity": "critical" }
    """

    func testAHealthySandboxWithNoNewEventsIsSilent() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(""))

        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        XCTAssertTrue(report.isSilent)
        XCTAssertNil(SandboxWatcher.render(report, sandbox: "dev", at: t0))
    }

    func testTheFirstPollEstablishesTheCursorAndAnnouncesNothing() async throws {
        // The change cursor's first-run rule, unchanged: declaring a sandbox must not replay its
        // history as an alarm.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(criticalEvent))

        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        XCTAssertTrue(report.newEvents.isEmpty)
        XCTAssertTrue(report.isSilent)
    }

    func testAnEventArrivingAfterTheCursorIsReported() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(baselineEvent))

        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON("\(criticalEvent), \(baselineEvent)"))
        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(300))

        XCTAssertEqual(report.newEvents.map(\.type), ["collector_access_lost"])
        XCTAssertEqual(report.newEvents.first?.severity, .critical)
        XCTAssertFalse(report.isSilent)

        let line = SandboxWatcher.render(report, sandbox: "dev", at: t0.addingTimeInterval(300))
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("!!"), "a critical event is marked: \(line!)")
        XCTAssertTrue(line!.contains("AuthorizationFailed"), "the detail is shown: \(line!)")
    }

    func testTheReportCarriesEveryNewEventAndLetsTheCallerFilter() async throws {
        // The Kit must not pre-filter: the CLI prints everything with markers, and the app will
        // notify on critical while only badging notable.
        let notable = """
        { "at": "2026-09-16T10:00:00.000Z", "type": "role_added", "subject": "p",
          "detail": {}, "collector": "governance", "severity": "notable" }
        """
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(baselineEvent))
        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        mock.stub(path: "/api/v1/changes", status: 200,
                  json: changesJSON("\(notable), \(criticalEvent), \(baselineEvent)"))
        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(300))

        XCTAssertEqual(report.newEvents.count, 2)
        XCTAssertEqual(report.newEvents.filter { $0.severity == .critical }.count, 1)
        XCTAssertEqual(report.newEvents.filter { $0.severity == .notable }.count, 1)
    }

    func testAnUnreachableSandboxStillReportsItsTransitionWithoutEvents() async throws {
        // `/changes` cannot answer when the app is down. That must not swallow the transition,
        // which is the whole point of polling.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(""))
        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        mock.fail(path: "/api/v1", error: SandboxWatchError("could not connect"))
        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(300))
        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(600))

        XCTAssertNotNil(report.transition)
        XCTAssertTrue(report.newEvents.isEmpty)
        XCTAssertFalse(report.isSilent)
    }

    func testTheCursorIsTheCallersAndNeverTheOneSbwChangesUses() async throws {
        // Spec 6.3, amended: three readers, three notions of "since I last looked". A watch that
        // moved the `sbw changes` cursor would make a manual run show nothing.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(criticalEvent))

        let watch = CursorStore(directory: directory + "/cursors-watch")
        let manual = CursorStore(directory: directory + "/cursors")

        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: watch, at: t0)

        XCTAssertNotNil(try watch.mark(for: "dev"))
        XCTAssertNil(try manual.mark(for: "dev"), "the manual cursor must not have moved")
    }

    // Two surfaces, two liaison stores. `poll` persists its decision unconditionally, so a shared
    // store would let whichever polled first confirm the new state — and the second would compare
    // the same set against itself, decide nothing changed, and stay silent. A missed transition is
    // the founding incident of this project, so this is the sharing bug that matters most.
    func testTwoSurfacesWithTheirOwnLiaisonStoresBothSeeTheTransition() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(""))

        let watchLiaison = LiaisonStore(directory: directory + "/liaison")
        let appLiaison = LiaisonStore(directory: directory + "/liaison-app")

        func poll(_ store: LiaisonStore, at now: Date) async throws -> LiaisonTransition? {
            try await SandboxWatcher.poll(
                sandbox: "dev", client: client(mock), liaison: store,
                cursors: CursorStore(directory: directory + "/c-\(ObjectIdentifier(store).hashValue)"),
                at: now).transition
        }

        _ = try await poll(watchLiaison, at: t0)
        _ = try await poll(appLiaison, at: t0)

        mock.stub(path: "/api/v1/snapshot", status: 401, json: "{}")
        _ = try await poll(watchLiaison, at: t0.addingTimeInterval(300))
        _ = try await poll(appLiaison, at: t0.addingTimeInterval(300))
        let watchSaw = try await poll(watchLiaison, at: t0.addingTimeInterval(600))
        let appSaw = try await poll(appLiaison, at: t0.addingTimeInterval(600))

        XCTAssertNotNil(watchSaw, "sbw watch must announce the transition")
        XCTAssertNotNil(appSaw, "and so must the app, from its own store")
        XCTAssertEqual(watchSaw, appSaw)
    }
}
