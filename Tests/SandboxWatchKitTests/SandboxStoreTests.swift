import XCTest
@testable import SandboxWatchKit

final class SandboxStoreTests: XCTestCase {
    private var path: String!
    private var store: SandboxStore!

    override func setUp() {
        super.setUp()
        let dir = NSTemporaryDirectory() + "sbw-tests-\(UUID().uuidString)"
        path = dir + "/sandboxes.yaml"
        store = SandboxStore(path: path)
    }

    override func tearDown() {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
        super.tearDown()
    }

    private func dev() -> Sandbox {
        Sandbox(name: "dev", url: URL(string: "https://sandbox-dev.azurewebsites.net")!, notes: "budget 50 EUR")
    }

    func testLoadMissingFileReturnsEmptyInventory() throws {
        XCTAssertEqual(try store.load().sandboxes, [])
    }

    func testAddThenLoadRoundTrips() throws {
        try store.add(dev())
        XCTAssertEqual(try store.load().sandboxes, [dev()])
    }

    func testAddDuplicateNameThrows() throws {
        try store.add(dev())
        XCTAssertThrowsError(try store.add(dev())) { error in
            XCTAssertTrue("\(error)".contains("already exists"))
        }
    }

    func testRemoveReportsWhetherItRemovedAnything() throws {
        try store.add(dev())
        XCTAssertTrue(try store.remove(named: "dev"))
        XCTAssertFalse(try store.remove(named: "dev"))
        XCTAssertEqual(try store.load().sandboxes, [])
    }

    func testSandboxNamedThrowsWithAHint() throws {
        XCTAssertThrowsError(try store.sandbox(named: "prod")) { error in
            XCTAssertTrue("\(error)".contains("sbw sandbox add prod"))
        }
    }

    func testUnparseableFileNamesThePath() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "this: is: not: valid: yaml:\n  - [".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue("\(error)".contains(self.path))
        }
    }

    // The inventory is the half of the configuration a human edits and reads. A token that
    // leaked into it would be world-readable on disk and would end up in any copy of the file.
    func testInventoryFileNeverCarriesAToken() throws {
        try store.add(dev())
        let text = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertFalse(text.lowercased().contains("token"))
    }
}
