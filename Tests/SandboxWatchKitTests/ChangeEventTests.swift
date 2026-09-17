import XCTest
@testable import SandboxWatchKit

final class ChangeEventTests: XCTestCase {
    private func decode(_ json: String) throws -> ChangeEvent {
        try SandboxJSON.decoder.decode(ChangeEvent.self, from: Data(json.utf8))
    }

    func testDecodesTheDocumentedEvent() throws {
        let event = try decode("""
        {
          "at": "2026-09-16T08:00:00.000Z",
          "type": "collector_access_lost",
          "subject": "governance",
          "detail": { "status": "denied", "message": "AuthorizationFailed" },
          "collector": "governance"
        }
        """)

        XCTAssertEqual(event.type, "collector_access_lost")
        XCTAssertEqual(event.subject, "governance")
        XCTAssertEqual(event.collector, "governance")
        XCTAssertEqual(event.detail?["message"]?.text, "AuthorizationFailed")
    }

    func testDetailAcceptsTheValueTypesTheServerActuallySends() throws {
        // A real probe transition: `{"from": 200, "to": null}`. Declaring detail as
        // [String: String] made every `sbw changes` call against a live log fail outright.
        let event = try decode("""
        {
          "at": "2026-09-16T08:00:00.000Z",
          "type": "probe_status_changed",
          "subject": "api",
          "detail": { "from": 200, "to": null, "message": "timeout", "httpsOnly": false },
          "collector": "probes"
        }
        """)

        XCTAssertEqual(event.detail?["from"], .number(200))
        XCTAssertEqual(event.detail?["to"], .null)
        XCTAssertEqual(event.detail?["message"], .string("timeout"))
        XCTAssertEqual(event.detail?["httpsOnly"], .bool(false))
    }

    func testAWholeNumberIsShownWithoutADecimalPoint() throws {
        // 200 must read as "200", not "200.0", in `sbw changes` output.
        XCTAssertEqual(JSONValue.number(200).text, "200")
        XCTAssertEqual(JSONValue.number(12.5).text, "12.5")
        // Null has no text: the caller skips it rather than printing the word "null".
        XCTAssertNil(JSONValue.null.text)
    }

    func testEventWithoutDetailStillDecodes() throws {
        let event = try decode(#"{"at":"2026-09-16T08:00:00Z","type":"resource_added","subject":"api"}"#)
        XCTAssertNil(event.detail)
        XCTAssertNil(event.collector)
    }

    // The founding incident of the whole project: a Contributor role moved over a weekend,
    // every `az` command failing at once, half an hour spent on wrong readings. Losing or
    // regaining collector access does not share a severity lane with a probe flapping.
    func testLosingCollectorAccessIsCritical() throws {
        XCTAssertEqual(try decode(#"{"at":"2026-09-16T08:00:00Z","type":"collector_access_lost","subject":"governance"}"#).severity, .critical)
        XCTAssertEqual(try decode(#"{"at":"2026-09-16T08:00:00Z","type":"collector_access_restored","subject":"governance"}"#).severity, .critical)
    }

    func testRoleAndLockChangesAreNotable() throws {
        for type in ["role_added", "role_removed", "lock_added", "lock_removed", "budget_threshold_crossed"] {
            let event = try decode(#"{"at":"2026-09-16T08:00:00Z","type":"\#(type)","subject":"x"}"#)
            XCTAssertEqual(event.severity, .notable, type)
        }
    }

    func testEverythingElseIsInformational() throws {
        XCTAssertEqual(try decode(#"{"at":"2026-09-16T08:00:00Z","type":"probe_status_changed","subject":"api"}"#).severity, .informational)
        XCTAssertEqual(try decode(#"{"at":"2026-09-16T08:00:00Z","type":"plan_tier_changed","subject":"plan-1"}"#).severity, .informational)
    }

    func testSeveritiesOrder() {
        XCTAssertTrue(ChangeSeverity.informational < ChangeSeverity.notable)
        XCTAssertTrue(ChangeSeverity.notable < ChangeSeverity.critical)
    }

    // The mark is the cursor's identity. `at` alone is not enough — see ChangeCursorTests.
    func testMarkCombinesTimeTypeAndSubject() throws {
        let event = try decode(#"{"at":"2026-09-16T08:00:00Z","type":"role_added","subject":"alice"}"#)
        XCTAssertEqual(event.mark.type, "role_added")
        XCTAssertEqual(event.mark.subject, "alice")
        XCTAssertEqual(event.mark.at, event.at)
    }

    // MARK: - The server judges the content; the client reads its verdict

    func testTheServersSeverityIsUsedWhenItSendsOne() throws {
        // The rule the whole device rests on: a fact is computed where it is known, once.
        // Promoting a type on the server must reclassify it here with no client release.
        let event = try decode("""
        {
          "at": "2026-09-16T08:00:00.000Z",
          "type": "probe_status_changed",
          "subject": "api",
          "severity": "critical"
        }
        """)

        XCTAssertEqual(event.severity, .critical, "the local table would have said informational")
    }

    func testAnUnknownSeverityIsNotableNeverInformational() throws {
        // The forbidden direction of error: a value this client does not understand must stay
        // visible, and must never be quiet enough to disappear behind a blank marker.
        let event = try decode("""
        {"at":"2026-09-16T08:00:00.000Z","type":"role_added","subject":"p","severity":"emergency"}
        """)

        XCTAssertEqual(event.severity, .notable)
    }

    func testAnOlderServerFallsBackToTheDatedTable() throws {
        // No `severity` field: a server predating 2026-09-17. Treating that absence as
        // "unknown -> notable" would demote collector_access_lost in the one case that matters.
        let event = try decode("""
        {"at":"2026-09-16T08:00:00.000Z","type":"collector_access_lost","subject":"governance"}
        """)

        XCTAssertEqual(event.severity, .critical)
    }

    func testTheFallbackTableCarriesExactlyTheTwelveTypesTheServerEmits() {
        XCTAssertEqual(SandboxAPI.eventTypes.count, 12)
        XCTAssertFalse(SandboxAPI.eventTypes.contains("deny_assignment_added"))
        XCTAssertFalse(SandboxAPI.eventTypes.contains("deny_assignment_removed"))
        XCTAssertEqual(SandboxAPI.fallbackSeverity(forType: "collector_access_lost"), .critical)
        XCTAssertEqual(SandboxAPI.fallbackSeverity(forType: "role_added"), .notable)
        XCTAssertEqual(SandboxAPI.fallbackSeverity(forType: "probe_status_changed"), .informational)
        XCTAssertEqual(SandboxAPI.fallbackSeverity(forType: "something_new"), .notable)
    }
}
