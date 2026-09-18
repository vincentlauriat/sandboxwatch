import XCTest
@testable import SandboxWatchKit

/// One tab per section. The rule that governs the overview governs every tab: a section that did
/// not collect shows *why*, and never an empty list. An empty table and a refused one look
/// identical on screen, and one of them is a revoked Reader role.
final class SandboxDetailTests: XCTestCase {
    private func section<T>(_ value: T) -> Section<T> { Section(outcome: .ok(value), durationMs: 1) }
    private func denied<T>(_ message: String) -> Section<T> {
        Section(outcome: .denied(message: message), durationMs: 1)
    }

    private func snapshot(
        apps: Section<[AzureApp]>? = nil,
        probes: Section<[Probe]>? = nil,
        governance: Section<Governance>? = nil,
        budget: Section<[Budget]>? = nil
    ) -> Snapshot {
        Snapshot(
            identity: Identity(available: true, subscriptionId: "sub", resourceGroup: "rg"),
            resources: section([]),
            plans: section([]),
            apps: apps ?? section([]),
            budget: budget ?? section([]),
            governance: governance ?? section(Governance(roleAssignments: [], locks: [], denyAssignments: [])),
            probes: probes ?? section([]))
    }

    private func app(_ name: String, _ state: String) -> AzureApp {
        AzureApp(name: name, state: state, plan: nil, runtime: nil,
                 httpsOnly: nil, alwaysOn: nil, url: nil, location: nil)
    }

    // MARK: - Unavailable is never empty

    func testTheGovernanceTabShowsWhyItIsUnavailableNotAnEmptyRoleList() {
        let panel = SandboxDetail.governance(
            from: snapshot(governance: denied("AuthorizationFailed")))

        guard case .unavailable(let why) = panel else {
            return XCTFail("a denied governance section became a list: \(panel)")
        }
        XCTAssertEqual(why, "AuthorizationFailed")
    }

    func testAGovernanceSectionThatCollectedNothingIsStillCollected() {
        // Zero role assignments is a fact. "We could not look" is a different one.
        let panel = SandboxDetail.governance(from: snapshot())

        guard case .rows(let rows) = panel else { return XCTFail("expected rows, got \(panel)") }
        XCTAssertTrue(rows.isEmpty)
    }

    func testTheBudgetTabShowsSpentAgainstAmountAndNothingWhenDenied() {
        let spent = SandboxDetail.budget(from: snapshot(budget: section([
            Budget(name: "monthly", amount: 500, currency: "EUR", spent: 125,
                   percent: 25, timeGrain: "Monthly", thresholds: [90]),
        ])))
        guard case .rows(let rows) = spent else { return XCTFail("expected rows") }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].spent, 125)
        XCTAssertEqual(rows[0].amount, 500)
        XCTAssertEqual(rows[0].percent, 25)

        guard case .unavailable = SandboxDetail.budget(from: snapshot(budget: denied("denied")))
        else { return XCTFail("a denied budget became a list") }
    }

    // MARK: - Apps and probes

    // The probes section names an app; the apps section names the same app. Pairing them here
    // means the view does not have to, and cannot do it differently from the CLI.
    func testTheProbesTabPairsEachProbeWithItsApp() {
        let panel = SandboxDetail.apps(from: snapshot(
            apps: section([app("api", "Running"), app("web", "Stopped")]),
            probes: section([
                Probe(app: "api", url: "https://api", httpStatus: 200, latencyMs: 42, error: nil),
            ])))

        guard case .rows(let rows) = panel else { return XCTFail("expected rows, got \(panel)") }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].name, "api")
        XCTAssertEqual(rows[0].probe?.httpStatus, 200)
        XCTAssertEqual(rows[1].name, "web")
        XCTAssertNil(rows[1].probe, "no probe for this app, and none invented")
    }

    // An app section that collected while probes did not is a real state: the apps are known,
    // their reachability is not. Showing them without probes beats showing nothing.
    func testAppsStillListWhenTheProbesSectionIsTheOneThatFailed() {
        let panel = SandboxDetail.apps(from: snapshot(
            apps: section([app("api", "Running")]),
            probes: denied("AuthorizationFailed")))

        guard case .rows(let rows) = panel else { return XCTFail("expected rows, got \(panel)") }
        XCTAssertEqual(rows[0].name, "api")
        XCTAssertNil(rows[0].probe)
        XCTAssertEqual(rows[0].probesUnavailableReason, "AuthorizationFailed",
                       "the row must say the probe is unknown, not that the app is unprobed")
    }

    func testADeniedAppsSectionIsUnavailableWhateverTheProbesSay() {
        let panel = SandboxDetail.apps(from: snapshot(
            apps: denied("AuthorizationFailed"),
            probes: section([Probe(app: "api", url: nil, httpStatus: 200, latencyMs: nil, error: nil)])))

        guard case .unavailable = panel else { return XCTFail("expected unavailable, got \(panel)") }
    }

    // MARK: - Changes

    // One vocabulary: the tab, `sbw changes` and `sbw watch` all read the same marker.
    func testTheChangesTabCarriesSeverityMarkersMatchingSbwChanges() throws {
        let events = try [
            #"{"at":"2026-09-16T09:18:01.000Z","type":"collector_access_lost","subject":"governance","detail":{"message":"AuthorizationFailed"},"severity":"critical"}"#,
            #"{"at":"2026-09-16T10:08:04.000Z","type":"role_added","subject":"alice","severity":"notable"}"#,
        ].map { try SandboxJSON.decoder.decode(ChangeEvent.self, from: Data($0.utf8)) }

        let rows = SandboxDetail.changes(events)

        XCTAssertEqual(rows.map(\.marker), ["!!", "! "])
        XCTAssertEqual(rows[0].marker, ChangeSeverity.critical.marker)
        XCTAssertTrue(rows[0].subject.contains("AuthorizationFailed"),
                      "the detail belongs on the row: \(rows[0].subject)")
    }
}
