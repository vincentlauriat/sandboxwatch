import XCTest
@testable import SandboxWatchKit

/// What a report *means* is a decision, and decisions live in the Kit. If the app were free to
/// pick its own icon and its own notification threshold, the CLI and the menu bar would drift
/// into two vocabularies for one sandbox.
final class WatchPresentationTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_789_000_000)

    private func event(_ json: String) throws -> ChangeEvent {
        try SandboxJSON.decoder.decode(ChangeEvent.self, from: Data(json.utf8))
    }

    /// The real 2026-09-16 incident, as the server published it.
    private func collectorAccessLost() throws -> ChangeEvent {
        try event("""
        { "at": "2026-09-16T09:18:01.000Z", "type": "collector_access_lost", "subject": "governance",
          "detail": { "status": "denied", "message": "AuthorizationFailed" },
          "collector": "governance", "severity": "critical" }
        """)
    }

    private func report(
        findings: [Doctor.Finding] = [.healthy(ageSeconds: 60)],
        transition: LiaisonTransition? = nil,
        newEvents: [ChangeEvent] = [],
        overflowed: Bool = false
    ) -> SandboxWatchReport {
        SandboxWatchReport(
            findings: findings, transition: transition, newEvents: newEvents, overflowed: overflowed)
    }

    // MARK: - The icon

    func testAHealthyReportIsAHealthyIcon() {
        XCTAssertEqual(WatchPresentation.icon(for: report()), .healthy)
    }

    // An unreachable sandbox is not "a bit degraded": it is the state in which every other reading
    // is unknown. Averaging it with the rest would show a yellow icon for a dead sandbox.
    func testAnUnreachableFindingOutranksEveryOtherKind() {
        let mixed = report(findings: [
            .healthy(ageSeconds: 60),
            .sectionsUnavailable(["governance"]),
            .unreachable("connection refused"),
        ])
        XCTAssertEqual(WatchPresentation.icon(for: mixed), .unreachable)
    }

    func testARefusedTokenIsUnreachableNotDegraded() {
        // A refused token means nothing can be read. Same class as a dead app, different cause —
        // `Doctor` already tells them apart in its headline.
        XCTAssertEqual(WatchPresentation.icon(for: report(findings: [.unauthorised])), .unreachable)
    }

    func testASectionThatDidNotCollectIsDegraded() {
        let partial = report(findings: [.healthy(ageSeconds: 60), .sectionsUnavailable(["budget"])])
        XCTAssertEqual(WatchPresentation.icon(for: partial), .degraded)
    }

    // MARK: - The alerts

    func testASilentReportProducesNoAlert() {
        XCTAssertTrue(WatchPresentation.alerts(for: report(), sandbox: "dev").isEmpty)
    }

    func testATransitionAlwaysAlerts() {
        let changed = report(
            findings: [.unauthorised],
            transition: LiaisonTransition(from: [.healthy], to: [.unauthorised]))

        let alerts = WatchPresentation.alerts(for: changed, sandbox: "dev")

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].severity, .critical)
        XCTAssertTrue(alerts[0].title.contains("dev"))
        XCTAssertTrue(alerts[0].body.contains("token was refused"), "the body explains: \(alerts[0].body)")
    }

    // The half batch A1 deliberately left undone: a notification naming only an identifier sends
    // Vincent back to the terminal to find out what happened.
    func testACriticalEventAlertsAndItsBodyCarriesTheServerMessage() throws {
        let lost = report(newEvents: [try collectorAccessLost()])

        let alerts = WatchPresentation.alerts(for: lost, sandbox: "dev")

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].severity, .critical)
        XCTAssertTrue(alerts[0].body.contains("governance"))
        XCTAssertTrue(alerts[0].body.contains("AuthorizationFailed"), "the body: \(alerts[0].body)")
    }

    // A probe flapping must badge the icon, never interrupt. Notifying on everything is how a
    // supervision tool teaches its operator to ignore it.
    func testAnInformationalEventDoesNotAlert() throws {
        let flap = report(newEvents: [try event("""
        { "at": "2026-09-16T09:38:03.000Z", "type": "probe_status_changed", "subject": "api",
          "severity": "informational" }
        """)])

        XCTAssertTrue(WatchPresentation.alerts(for: flap, sandbox: "dev").isEmpty)
    }

    func testANotableEventDoesNotAlertEither() throws {
        let role = report(newEvents: [try event("""
        { "at": "2026-09-16T10:08:04.000Z", "type": "role_added", "subject": "alice",
          "severity": "notable" }
        """)])

        XCTAssertTrue(WatchPresentation.alerts(for: role, sandbox: "dev").isEmpty)
    }

    // Overflow is the one non-event that must interrupt: the app cannot tell what it missed.
    func testOverflowAlertsBecauseSilentTruncationIsTheBugBeingAvoided() {
        let truncated = report(overflowed: true)

        let alerts = WatchPresentation.alerts(for: truncated, sandbox: "dev")

        XCTAssertEqual(alerts.count, 1)
        XCTAssertTrue(alerts[0].body.lowercased().contains("not returned"), alerts[0].body)
    }

    func testEveryCriticalEventGetsItsOwnAlert() throws {
        let two = report(newEvents: [try collectorAccessLost(), try collectorAccessLost()])
        XCTAssertEqual(WatchPresentation.alerts(for: two, sandbox: "dev").count, 2)
    }
}
