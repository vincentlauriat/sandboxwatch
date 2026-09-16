import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class SandboxCommandsTests: XCTestCase {
    private var path: String!
    private var store: SandboxStore!
    private var tokens: InMemoryTokenStore!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "sbw-cmd-\(UUID().uuidString)/sandboxes.yaml"
        store = SandboxStore(path: path)
        tokens = InMemoryTokenStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
        super.tearDown()
    }

    func testAddStoresTheSandboxAndTheTokenSeparately() throws {
        _ = try SandboxAdmin.add(name: "dev", url: "https://dev.azurewebsites.net", notes: nil,
                                 token: "secret", store: store, tokens: tokens)

        XCTAssertEqual(try store.load().sandboxes.map(\.name), ["dev"])
        XCTAssertEqual(try tokens.token(for: "dev"), "secret")

        // The token must not reach the file. This is the point of having two stores.
        let onDisk = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertFalse(onDisk.contains("secret"))
    }

    func testAddRejectsANonHTTPSURL() {
        XCTAssertThrowsError(try SandboxAdmin.add(
            name: "dev", url: "http://dev.azurewebsites.net", notes: nil,
            token: "secret", store: store, tokens: tokens)) { error in
            XCTAssertTrue("\(error)".contains("https"))
        }
    }

    func testAddRejectsAnUnparseableURL() {
        XCTAssertThrowsError(try SandboxAdmin.add(
            name: "dev", url: "not a url", notes: nil, token: "t", store: store, tokens: tokens))
    }

    func testAddRejectsAnEmptyToken() {
        XCTAssertThrowsError(try SandboxAdmin.add(
            name: "dev", url: "https://dev.azurewebsites.net", notes: nil,
            token: "   ", store: store, tokens: tokens)) { error in
            XCTAssertTrue("\(error)".contains("token"))
        }
    }

    func testListShowsNamesAndURLsAndNeverTokens() throws {
        _ = try SandboxAdmin.add(name: "dev", url: "https://dev.azurewebsites.net", notes: "note",
                                 token: "secret", store: store, tokens: tokens)

        let output = try SandboxAdmin.list(store: store)

        XCTAssertTrue(output.contains("dev"))
        XCTAssertTrue(output.contains("https://dev.azurewebsites.net"))
        XCTAssertFalse(output.contains("secret"))
    }

    func testListOnAnEmptyInventoryExplainsHowToAddOne() throws {
        XCTAssertTrue(try SandboxAdmin.list(store: store).contains("sbw sandbox add"))
    }

    // Removing a sandbox must take its token with it: a Keychain entry left behind outlives
    // the thing it authenticated, and nothing would ever clean it up.
    func testRemoveAlsoRemovesTheToken() throws {
        _ = try SandboxAdmin.add(name: "dev", url: "https://dev.azurewebsites.net", notes: nil,
                                 token: "secret", store: store, tokens: tokens)

        _ = try SandboxAdmin.remove(name: "dev", store: store, tokens: tokens)

        XCTAssertEqual(try store.load().sandboxes, [])
        XCTAssertNil(try tokens.token(for: "dev"))
    }

    // A failed inventory write must not leave an orphan token behind: nothing else would
    // ever clean it up, and the next `add` would silently reuse it.
    func testAddLeavesNoOrphanTokenWhenTheInventoryRejectsTheName() throws {
        _ = try SandboxAdmin.add(name: "dev", url: "https://dev.azurewebsites.net", notes: nil,
                                 token: "first", store: store, tokens: tokens)

        XCTAssertThrowsError(try SandboxAdmin.add(
            name: "dev", url: "https://other.azurewebsites.net", notes: nil,
            token: "second", store: store, tokens: tokens))

        // The pre-existing token survives; the rejected one did not replace it.
        XCTAssertEqual(try tokens.token(for: "dev"), "first")
    }

    func testRemovingAnUnknownSandboxSaysSo() {
        XCTAssertThrowsError(try SandboxAdmin.remove(name: "ghost", store: store, tokens: tokens)) { error in
            XCTAssertTrue("\(error)".contains("ghost"))
        }
    }
}
