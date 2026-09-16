import XCTest
@testable import SandboxWatchKit

final class CursorStoreTests: XCTestCase {
    private var directory: String!
    private var store: CursorStore!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "sbw-cursors-\(UUID().uuidString)"
        store = CursorStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    func testMissingCursorIsNilNotAnError() throws {
        XCTAssertNil(try store.mark(for: "dev"))
    }

    func testRoundTrips() throws {
        let mark = ChangeMark(at: Date(timeIntervalSince1970: 1789545600), type: "role_added", subject: "alice")
        try store.setMark(mark, for: "dev")
        XCTAssertEqual(try store.mark(for: "dev"), mark)
    }

    func testCursorsAreScopedPerSandbox() throws {
        let a = ChangeMark(at: Date(timeIntervalSince1970: 1), type: "x", subject: "a")
        let b = ChangeMark(at: Date(timeIntervalSince1970: 2), type: "y", subject: "b")
        try store.setMark(a, for: "dev")
        try store.setMark(b, for: "prod")
        XCTAssertEqual(try store.mark(for: "dev"), a)
        XCTAssertEqual(try store.mark(for: "prod"), b)
    }

    // A sandbox name reaches this from the command line. Letting it become a path would write
    // outside the cursor directory.
    func testSandboxNameCannotEscapeTheDirectory() {
        let mark = ChangeMark(at: Date(), type: "x", subject: "y")
        XCTAssertThrowsError(try store.setMark(mark, for: "../../etc/passwd"))
        XCTAssertThrowsError(try store.mark(for: "../../etc/passwd"))
    }

    // A truncated or hand-edited file is a fresh start, not a crash that blocks every command.
    func testUnreadableCursorReadsAsNoCursor() throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "{ not json".write(toFile: directory + "/dev.json", atomically: true, encoding: .utf8)
        XCTAssertNil(try store.mark(for: "dev"))
    }
}
