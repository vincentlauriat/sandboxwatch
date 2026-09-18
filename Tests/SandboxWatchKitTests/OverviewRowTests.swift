import XCTest
@testable import SandboxWatchKit

/// The overview is one line per sandbox, and it is the first thing seen. The rule the whole
/// project rests on has to hold here above all: a section that could not be collected must never
/// render as a zero. `denied` is exactly what a revoked Reader role looks like, and "0/0 up" would
/// reintroduce from the window the false alarm the server was built to prevent.
final class OverviewRowTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_789_700_000)

    private func apps(_ states: [String]) -> Section<[AzureApp]> {
        Section(outcome: .ok(states.enumerated().map { index, state in
            AzureApp(name: "app\(index)", state: state, plan: nil, runtime: nil,
                     httpsOnly: nil, alwaysOn: nil, url: nil, location: nil)
        }), durationMs: 1)
    }

    private func snapshot(
        apps appsSection: Section<[AzureApp]> = Section(outcome: .ok([]), durationMs: 1),
        budget: Section<[Budget]> = Section(outcome: .ok([]), durationMs: 1)
    ) -> Snapshot {
        Snapshot(
            identity: Identity(available: true, subscriptionId: "sub", resourceGroup: "rg"),
            resources: Section(outcome: .ok([]), durationMs: 1),
            plans: Section(outcome: .ok([]), durationMs: 1),
            apps: appsSection,
            budget: budget,
            governance: Section(outcome: .ok(Governance(roleAssignments: [], locks: [], denyAssignments: [])), durationMs: 1),
            probes: Section(outcome: .ok([]), durationMs: 1))
    }

    private func report(
        findings: [Doctor.Finding] = [.healthy(ageSeconds: 30)],
        newEvents: [ChangeEvent] = []
    ) -> SandboxWatchReport {
        SandboxWatchReport(findings: findings, transition: nil, newEvents: newEvents, overflowed: false)
    }

    // MARK: - Never a manufactured zero

    func testADeniedAppsSectionYieldsNoCountAtAllNotZeroOfZero() {
        let denied = Section<[AzureApp]>(outcome: .denied(message: "AuthorizationFailed"), durationMs: 1)

        let row = OverviewRow.make(
            sandbox: "dev", snapshot: snapshot(apps: denied), ageSeconds: 30, report: report())

        XCTAssertNil(row.apps, "a denied section must not become 0/0 up")
        XCTAssertEqual(row.appsUnavailableReason, "AuthorizationFailed")
    }

    func testADeniedBudgetYieldsNoPercentageNotZero() {
        let denied = Section<[Budget]>(outcome: .denied(message: "AuthorizationFailed"), durationMs: 1)

        let row = OverviewRow.make(
            sandbox: "dev", snapshot: snapshot(budget: denied), ageSeconds: 30, report: report())

        XCTAssertNil(row.budgetPercent, "a denied budget must not become 0%")
    }

    // A budget section that is fine but genuinely empty is a different fact from a denied one,
    // and the row must keep them apart.
    func testAnEmptyButCollectedBudgetIsNotTheSameAsADeniedOne() {
        let row = OverviewRow.make(
            sandbox: "dev", snapshot: snapshot(), ageSeconds: 30, report: report())

        XCTAssertNil(row.budgetPercent)
        XCTAssertNil(row.budgetUnavailableReason, "nothing was denied here")
    }

    func testAppsAreCountedWhenTheSectionCollected() {
        let row = OverviewRow.make(
            sandbox: "dev",
            snapshot: snapshot(apps: apps(["Running", "Stopped", "Running"])),
            ageSeconds: 30, report: report())

        XCTAssertEqual(row.apps?.up, 2)
        XCTAssertEqual(row.apps?.of, 3)
    }

    // MARK: - The unreachable sandbox

    // The one you are looking for must not be the one that disappears from the list.
    func testAnUnreachableSandboxStillProducesARowSoItCannotVanishFromTheList() {
        let row = OverviewRow.unreachable(sandbox: "broken", report: report(
            findings: [.unreachable("connection refused")]))

        XCTAssertEqual(row.sandbox, "broken")
        XCTAssertEqual(row.icon, .unreachable)
        XCTAssertNil(row.apps)
        XCTAssertNil(row.ageSeconds)
        XCTAssertTrue(row.headline.contains("connection refused"), row.headline)
    }

    // MARK: - One vocabulary

    // The window and the menu bar must not drift into two thresholds for one sandbox.
    func testTheRowsIconMatchesWhatTheMenuBarWouldShow() {
        for findings: [Doctor.Finding] in [
            [.healthy(ageSeconds: 30)],
            [.sectionsUnavailable(["budget"])],
            [.unauthorised],
            [.unreachable("down")],
        ] {
            let watch = report(findings: findings)
            let row = OverviewRow.make(
                sandbox: "dev", snapshot: snapshot(), ageSeconds: 30, report: watch)
            XCTAssertEqual(row.icon, WatchPresentation.icon(for: watch), "\(findings)")
        }
    }

    func testUnreadChangesCountsWhatThePollReported() {
        let event = try! SandboxJSON.decoder.decode(ChangeEvent.self, from: Data(
            #"{"at":"2026-09-16T09:18:01.000Z","type":"role_added","subject":"alice"}"#.utf8))

        let row = OverviewRow.make(
            sandbox: "dev", snapshot: snapshot(), ageSeconds: 30,
            report: report(newEvents: [event, event]))

        XCTAssertEqual(row.unreadChanges, 2)
    }
}
