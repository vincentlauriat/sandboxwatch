import XCTest
@testable import SandboxWatchKit

final class ActionJournalTests: XCTestCase {
    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "sbw-journal-\(UUID().uuidString)/actions.jsonl"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        super.tearDown()
    }

    private func journal() -> ActionJournal { ActionJournal(path: path) }

    private func record(
        _ outcome: ActionRecord.Outcome, app: String = "api", at: Date = Date(timeIntervalSince1970: 1_789_700_000)
    ) -> ActionRecord {
        ActionRecord(at: at, sandbox: "dev", app: app, action: .restart, outcome: outcome)
    }

    func testAPerformedActionIsRecordedWithItsExitCode() throws {
        let journal = journal()
        try journal.append(record(.performed(exitCode: 0)))

        let records = journal.records()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].sandbox, "dev")
        XCTAssertEqual(records[0].app, "api")
        XCTAssertEqual(records[0].action, .restart)
        XCTAssertEqual(records[0].outcome, .performed(exitCode: 0))
    }

    // The spec names this one explicitly. A journal that only recorded what happened would be
    // silent about the afternoon spent wondering why nothing happened.
    func testARefusedActionIsRecordedToo() throws {
        let journal = journal()
        let refusal = ActionRefusal.wrongSubscription(expected: "sub-a", actual: "sub-b")
        try journal.append(record(.refused(refusal.headline)))

        let records = journal.records()

        XCTAssertEqual(records.count, 1)
        guard case .refused(let why) = records[0].outcome else {
            return XCTFail("expected a refusal, got \(records[0].outcome)")
        }
        XCTAssertTrue(why.contains("sub-a") && why.contains("sub-b"), why)
    }

    func testTheJournalIsAppendOnlyAndSurvivesAReopen() throws {
        try journal().append(record(.performed(exitCode: 0), app: "first"))
        try journal().append(record(.refused("nope"), app: "second"))
        try journal().append(record(.performed(exitCode: 1), app: "third"))

        // A fresh instance, as a later `sbw` invocation would be.
        let records = journal().records()

        XCTAssertEqual(records.map(\.app), ["first", "second", "third"])
    }

    func testAnUnreadableJournalIsNoJournalNeverACrash() {
        XCTAssertTrue(ActionJournal(path: "/nonexistent/place/actions.jsonl").records().isEmpty)
    }

    // One malformed line must not hide the rest. A journal is read when something has already
    // gone wrong; losing it then is losing it exactly when it is needed.
    func testAMalformedLineIsSkippedAndTheOthersSurvive() throws {
        let journal = journal()
        try journal.append(record(.performed(exitCode: 0), app: "before"))
        let handle = FileHandle(forWritingAtPath: path)!
        handle.seekToEndOfFile()
        handle.write(Data("{ not json at all\n".utf8))
        try handle.close()
        try journal.append(record(.performed(exitCode: 0), app: "after"))

        XCTAssertEqual(journal.records().map(\.app), ["before", "after"])
    }
}
