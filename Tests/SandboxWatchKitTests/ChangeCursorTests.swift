import XCTest
@testable import SandboxWatchKit

final class ChangeCursorTests: XCTestCase {
    /// Builds an event at `t` seconds past a fixed epoch. The page the API returns is
    /// newest-first, so tests list events in descending time.
    private func event(_ t: TimeInterval, _ type: String = "probe_status_changed", _ subject: String = "api") -> ChangeEvent {
        let json = """
        {"at":"\(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1789545600 + t)))","type":"\(type)","subject":"\(subject)"}
        """
        return try! SandboxJSON.decoder.decode(ChangeEvent.self, from: Data(json.utf8))
    }

    // First run must not announce the entire history. It establishes where we are and reports
    // nothing new — otherwise adding a sandbox would fire a hundred notifications.
    func testFirstRunReportsNothingAndMarksTheNewest() {
        let page = [event(300), event(200), event(100)]
        let scan = ChangeCursor.scan(page: page, since: nil)

        XCTAssertEqual(scan.newEvents, [])
        XCTAssertFalse(scan.overflowed)
        XCTAssertEqual(scan.newest, page[0].mark)
    }

    func testEmptyLogIsNotAnOverflow() {
        let scan = ChangeCursor.scan(page: [], since: event(100).mark)
        XCTAssertEqual(scan.newEvents, [])
        XCTAssertFalse(scan.overflowed)
        XCTAssertNil(scan.newest)
    }

    func testEventsNewerThanTheMarkAreReturnedNewestFirst() {
        let page = [event(300), event(200), event(100)]
        let scan = ChangeCursor.scan(page: page, since: page[2].mark)

        XCTAssertEqual(scan.newEvents, [page[0], page[1]])
        XCTAssertFalse(scan.overflowed)
        XCTAssertEqual(scan.newest, page[0].mark)
    }

    func testNothingNewWhenTheMarkIsTheNewestEvent() {
        let page = [event(300), event(200)]
        let scan = ChangeCursor.scan(page: page, since: page[0].mark)

        XCTAssertEqual(scan.newEvents, [])
        XCTAssertFalse(scan.overflowed)
    }

    // Two events collected in the same instant. A cursor of `at` alone would either replay the
    // second one forever or drop it — which is why the mark carries type and subject.
    func testTiedTimestampsAreDistinguishedByTypeAndSubject() {
        let older = event(200, "role_added", "alice")
        let newer = event(200, "role_added", "bob")
        let page = [newer, older]

        let scan = ChangeCursor.scan(page: page, since: older.mark)

        XCTAssertEqual(scan.newEvents, [newer])
        XCTAssertFalse(scan.overflowed)
    }

    // THE cursor test. More events happened than the page could hold, so the page never
    // reaches back to the mark. Returning it as "all new" without a signal loses whatever fell
    // off the end — silently, which is the one thing a change-detection tool cannot do.
    func testPageThatDoesNotReachBackToTheMarkIsFlaggedAsOverflowed() {
        let page = [event(500), event(400), event(300)]
        let scan = ChangeCursor.scan(page: page, since: event(100).mark)

        XCTAssertTrue(scan.overflowed)
        XCTAssertEqual(scan.newEvents, page)
    }

    // The marked event itself can be gone — the log was pruned, or the mark predates it. We
    // did reach back past its time, so nothing was lost: everything strictly newer is new.
    func testReachingBackPastAPrunedMarkIsNotAnOverflow() {
        let page = [event(300), event(200), event(50)]
        let scan = ChangeCursor.scan(page: page, since: event(100).mark)

        XCTAssertFalse(scan.overflowed)
        XCTAssertEqual(scan.newEvents, [page[0], page[1]])
    }

    // Pins the one deliberate compromise: with the marked event pruned, a sibling sharing its
    // instant is treated as already seen rather than re-announced. If this test ever has to
    // change, the comment in `scan` is what to read first.
    func testTiesAtAPrunedMarkAreTreatedAsAlreadySeen() {
        let page = [event(300), event(100, "role_added", "bob")]
        let scan = ChangeCursor.scan(page: page, since: event(100, "role_added", "alice").mark)

        XCTAssertFalse(scan.overflowed)
        XCTAssertEqual(scan.newEvents, [page[0]])
    }

    func testWideningStopsAtTheServersCeiling() {
        XCTAssertEqual(ChangeCursor.nextLimit(after: 50), 200)
        XCTAssertEqual(ChangeCursor.nextLimit(after: 200), 500)
        XCTAssertNil(ChangeCursor.nextLimit(after: 500))
    }
}
