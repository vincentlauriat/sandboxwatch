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
        XCTAssertEqual(event.detail?["message"], "AuthorizationFailed")
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
}
