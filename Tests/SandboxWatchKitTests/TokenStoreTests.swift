import XCTest
@testable import SandboxWatchKit

final class TokenStoreTests: XCTestCase {
    func testInMemoryStoreRoundTrips() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(try store.token(for: "dev"))
        try store.setToken("abc123", for: "dev")
        XCTAssertEqual(try store.token(for: "dev"), "abc123")
    }

    func testInMemoryStoreReplacesRatherThanDuplicates() throws {
        let store = InMemoryTokenStore(["dev": "old"])
        try store.setToken("new", for: "dev")
        XCTAssertEqual(try store.token(for: "dev"), "new")
    }

    func testRemove() throws {
        let store = InMemoryTokenStore(["dev": "abc123"])
        try store.removeToken(for: "dev")
        XCTAssertNil(try store.token(for: "dev"))
    }

    func testTokensAreScopedPerSandbox() throws {
        let store = InMemoryTokenStore(["dev": "a", "prod": "b"])
        XCTAssertEqual(try store.token(for: "dev"), "a")
        XCTAssertEqual(try store.token(for: "prod"), "b")
    }

    // The missing-token message has to name the command that fixes it: a bare "no token"
    // sends the operator hunting through a Keychain they cannot browse by service name.
    func testRequireTokenExplainsHowToSetIt() {
        let store = InMemoryTokenStore()
        XCTAssertThrowsError(try requireToken(store, for: "dev")) { error in
            XCTAssertTrue("\(error)".contains("sbw sandbox add dev"))
        }
    }

    func testRequireTokenReturnsTheToken() throws {
        let store = InMemoryTokenStore(["dev": "abc123"])
        XCTAssertEqual(try requireToken(store, for: "dev"), "abc123")
    }
}
