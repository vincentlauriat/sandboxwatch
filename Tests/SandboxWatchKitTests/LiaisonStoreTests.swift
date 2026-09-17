import XCTest
@testable import SandboxWatchKit

final class LiaisonStoreTests: XCTestCase {
    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "sbw-liaison-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    func testRoundTrips() throws {
        let store = LiaisonStore(directory: directory)
        let state = LiaisonState(
            confirmed: [.healthy], candidate: [.unreachable],
            observedAt: Date(timeIntervalSince1970: 1_789_000_000))

        try store.setState(state, for: "dev")

        XCTAssertEqual(try store.state(for: "dev"), state)
    }

    func testAMissingFileIsNoState() throws {
        XCTAssertNil(try LiaisonStore(directory: directory).state(for: "dev"))
    }

    func testAnUnreadableFileIsNoStateRatherThanACrash() throws {
        // A corrupt file must mean "start again", never a command that refuses to run.
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "not json".write(toFile: directory + "/dev.json", atomically: true, encoding: .utf8)

        XCTAssertNil(try LiaisonStore(directory: directory).state(for: "dev"))
    }

    func testStatesAreScopedPerSandbox() throws {
        let store = LiaisonStore(directory: directory)
        let at = Date(timeIntervalSince1970: 1_789_000_000)
        try store.setState(LiaisonState(confirmed: [.healthy], candidate: nil, observedAt: at), for: "dev")
        try store.setState(LiaisonState(confirmed: [.unreachable], candidate: nil, observedAt: at), for: "prod")

        XCTAssertEqual(try store.state(for: "dev")?.confirmed, [.healthy])
        XCTAssertEqual(try store.state(for: "prod")?.confirmed, [.unreachable])
    }

    func testANameThatWouldEscapeTheDirectoryIsRefused() throws {
        let store = LiaisonStore(directory: directory)
        let at = Date(timeIntervalSince1970: 1_789_000_000)
        let state = LiaisonState(confirmed: [.healthy], candidate: nil, observedAt: at)

        XCTAssertThrowsError(try store.setState(state, for: "../escape"))
        XCTAssertThrowsError(try store.state(for: ".."))
        XCTAssertThrowsError(try store.state(for: ""))
    }
}
