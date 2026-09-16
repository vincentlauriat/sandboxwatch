# SandboxWatch Batch 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `SandboxWatchKit` and a read-only `sbw` CLI that inventory Azure sandboxes, read their API, diagnose them, and report what changed.

**Architecture:** One SPM package: a library holding every decision, and a thin CLI over it. Every side effect goes through a protocol (`HTTPClient`, `TokenStore`) so the whole suite runs with no network and no Keychain. The snapshot model makes a failed collection impossible to read as empty data, and the change cursor detects the pages it did not reach back far enough to cover.

**Tech Stack:** Swift 5.9 tools version on the Swift 6.4 toolchain, macOS 13+, XCTest, `swift-argument-parser`, `Yams`.

**Spec:** `docs/superpowers/specs/2026-09-16-sandboxwatch-design.md`

## Global Constraints

- `// swift-tools-version:5.9`, `platforms: [.macOS(.v13)]`. Swift 5 language mode — do not opt into Swift 6 strict concurrency.
- Dependencies are exactly two: `swift-argument-parser` (from 1.3.0) and `Yams` (from 5.0.0). Adding a third is a design change, not an implementation detail.
- Tests are XCTest with `@testable import SandboxWatchKit`, mirroring `HomePortKitTests`.
- **No test may touch the network, the Keychain, or `az`.** Every seam has a test double.
- Code, comments, doc files and commit messages are in English. Conventional commits, present tense.
- **Never add a `Co-Authored-By: Claude` trailer** (`~/DevApps/CLAUDE.md`).
- Work on a feature branch, never directly on `main`.
- Batch 1 is read-only. `POST /api/v1/refresh`, `az`, and `sbw watch` belong to later batches — do not build them here.
- The token header is `X-Sandbox-Token`. `/healthz` is the only route that does not carry it.

---

### Task 1: Package skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/SandboxWatchKit/SandboxWatchError.swift`
- Create: `Sources/SandboxWatchKit/Paths.swift`
- Create: `Sources/sbw/SBW.swift`
- Test: `Tests/SandboxWatchKitTests/ScaffoldTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `SandboxWatchError(_ message: String)` — the Kit's only thrown error type; `expandPath(_ path: String) -> String`.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/ScaffoldTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class ScaffoldTests: XCTestCase {
    // The test target depends on an executable target carrying `@main`. That works, and
    // HomePortManager relies on it, but it is the one structural assumption in Package.swift —
    // exercise it in task 1 rather than discovering it wrong at task 12.
    func testTheCLITargetIsImportable() {
        XCTAssertEqual(SBW.configuration.commandName, "sbw")
    }

    func testErrorCarriesItsMessage() {
        let error = SandboxWatchError("unknown sandbox 'dev'")
        XCTAssertEqual(error.message, "unknown sandbox 'dev'")
        XCTAssertEqual(String(describing: error), "unknown sandbox 'dev'")
    }

    func testExpandPathExpandsLeadingTilde() {
        let expanded = expandPath("~/.config/sbw/sandboxes.yaml")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/.config/sbw/sandboxes.yaml"))
    }

    func testExpandPathLeavesAbsolutePathAlone() {
        XCTAssertEqual(expandPath("/tmp/sbw.yaml"), "/tmp/sbw.yaml")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — the package does not exist yet (`error: no Package.swift`).

- [ ] **Step 3: Write minimal implementation**

`Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SandboxWatch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SandboxWatchKit", targets: ["SandboxWatchKit"]),
        .executable(name: "sbw", targets: ["sbw"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
    ],
    targets: [
        .target(name: "SandboxWatchKit", dependencies: ["Yams"]),
        .executableTarget(name: "sbw", dependencies: [
            "SandboxWatchKit",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        // "sbw" too: the CLI makes its own decisions (argument validation, the shape of the
        // printed table) that deserve the same coverage as the Kit, exactly as HomePortManager
        // tests its `hpm` target.
        .testTarget(name: "SandboxWatchKitTests", dependencies: ["SandboxWatchKit", "sbw"]),
    ]
)
```

`Sources/SandboxWatchKit/SandboxWatchError.swift`:

```swift
import Foundation

/// The Kit's only thrown error: conditions the operator caused and can fix — an unknown
/// sandbox name, an unparseable inventory file.
///
/// States the server or the network can legitimately be in are NOT errors here. A denied
/// collector, a server with no snapshot yet, a stale snapshot: those are values the UI
/// displays (`Section`, `APIFailure`, `Doctor.Finding`). Throwing them would turn an ordinary
/// state into a failure, which is the mistake this project exists to avoid.
public struct SandboxWatchError: Error, CustomStringConvertible, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}
```

`Sources/SandboxWatchKit/Paths.swift`:

```swift
import Foundation

/// Expands a leading `~` against the current user's home directory.
/// `expandingTildeInPath` lives on `NSString`, and everything else here works in `String`.
public func expandPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}
```

`Sources/sbw/SBW.swift`:

```swift
import ArgumentParser
import Foundation
import SandboxWatchKit

/// `AsyncParsableCommand` rather than `ParsableCommand`: every command that reads the API is
/// asynchronous, and only an async root awaits an async subcommand.
@main
struct SBW: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sbw",
        abstract: "Read the state of your Azure sandboxes, and what changed since last time.",
        subcommands: []
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git checkout -b feat/batch-1-kit
git add Package.swift Sources Tests
git commit -m "feat: package skeleton with error type and path expansion"
```

---

### Task 2: The sandbox inventory

**Files:**
- Create: `Sources/SandboxWatchKit/SandboxStore.swift`
- Test: `Tests/SandboxWatchKitTests/SandboxStoreTests.swift`

**Interfaces:**
- Consumes: `SandboxWatchError`, `expandPath`.
- Produces:
  - `struct Sandbox: Codable, Equatable { var name: String; var url: URL; var notes: String? }`
  - `struct Inventory: Codable, Equatable { var sandboxes: [Sandbox] }`
  - `final class SandboxStore` with `init(path: String = SandboxStore.defaultPath)`, `load() throws -> Inventory`, `save(_:) throws`, `add(_ sandbox: Sandbox) throws`, `remove(named: String) throws -> Bool`, `sandbox(named: String) throws -> Sandbox`, `static let defaultPath = "~/.config/sbw/sandboxes.yaml"`.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/SandboxStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SandboxStoreTests`
Expected: FAIL — `cannot find 'SandboxStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/SandboxStore.swift`:

```swift
import Foundation
import Yams

/// One watched sandbox. Deliberately holds no secret: the `SANDBOX_TOKEN` lives in the
/// Keychain (`TokenStore`). This is the one place SandboxWatch diverges from `hpm`'s
/// `fleet.yaml`, and it diverges because there the transport was SSH — not a secret — while
/// here the transport IS the secret.
public struct Sandbox: Codable, Equatable {
    public var name: String
    public var url: URL
    public var notes: String?

    public init(name: String, url: URL, notes: String? = nil) {
        self.name = name
        self.url = url
        self.notes = notes
    }
}

public struct Inventory: Codable, Equatable {
    public var sandboxes: [Sandbox]
    public init(sandboxes: [Sandbox] = []) { self.sandboxes = sandboxes }
}

public final class SandboxStore {
    public static let defaultPath = "~/.config/sbw/sandboxes.yaml"
    private let path: String

    public init(path: String = SandboxStore.defaultPath) {
        self.path = expandPath(path)
    }

    /// A missing file is an empty inventory, not an error: it is what a first run looks like.
    public func load() throws -> Inventory {
        guard FileManager.default.fileExists(atPath: path) else { return Inventory() }
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        do {
            return try YAMLDecoder().decode(Inventory.self, from: contents)
        } catch {
            throw SandboxWatchError("cannot parse \(path): \(error)")
        }
    }

    public func save(_ inventory: Inventory) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let yaml = try YAMLEncoder().encode(inventory)
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public func add(_ sandbox: Sandbox) throws {
        var inventory = try load()
        guard !inventory.sandboxes.contains(where: { $0.name == sandbox.name }) else {
            throw SandboxWatchError("sandbox '\(sandbox.name)' already exists in \(path)")
        }
        inventory.sandboxes.append(sandbox)
        try save(inventory)
    }

    @discardableResult
    public func remove(named name: String) throws -> Bool {
        var inventory = try load()
        let before = inventory.sandboxes.count
        inventory.sandboxes.removeAll { $0.name == name }
        guard inventory.sandboxes.count != before else { return false }
        try save(inventory)
        return true
    }

    public func sandbox(named name: String) throws -> Sandbox {
        guard let found = try load().sandboxes.first(where: { $0.name == name }) else {
            throw SandboxWatchError(
                "unknown sandbox '\(name)' — declare it with: sbw sandbox add \(name) --url <url>")
        }
        return found
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SandboxStoreTests`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/SandboxStore.swift Tests/SandboxWatchKitTests/SandboxStoreTests.swift
git commit -m "feat: YAML sandbox inventory, no secrets on disk"
```

---

### Task 3: The token store

**Files:**
- Create: `Sources/SandboxWatchKit/TokenStore.swift`
- Test: `Tests/SandboxWatchKitTests/TokenStoreTests.swift`

**Interfaces:**
- Consumes: `SandboxWatchError`.
- Produces:
  - `protocol TokenStore { func token(for sandbox: String) throws -> String?; func setToken(_ token: String, for sandbox: String) throws; func removeToken(for sandbox: String) throws }`
  - `final class InMemoryTokenStore: TokenStore` — the test double, with `init(_ seed: [String: String] = [:])`.
  - `final class KeychainTokenStore: TokenStore` — `init(service: String = KeychainTokenStore.defaultService)`, `static let defaultService = "fr.lauriat.sandboxwatch"`.
  - `func requireToken(_ store: TokenStore, for sandbox: String) throws -> String` — throws a message naming the fix.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/TokenStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenStoreTests`
Expected: FAIL — `cannot find 'InMemoryTokenStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/TokenStore.swift`:

```swift
import Foundation
import Security

/// Where a sandbox's `SANDBOX_TOKEN` lives. A protocol so that no test ever touches the
/// real Keychain — running the suite must never prompt for a login password.
public protocol TokenStore {
    func token(for sandbox: String) throws -> String?
    func setToken(_ token: String, for sandbox: String) throws
    func removeToken(for sandbox: String) throws
}

/// Test double.
public final class InMemoryTokenStore: TokenStore {
    private var tokens: [String: String]

    public init(_ seed: [String: String] = [:]) { self.tokens = seed }

    public func token(for sandbox: String) throws -> String? { tokens[sandbox] }
    public func setToken(_ token: String, for sandbox: String) throws { tokens[sandbox] = token }
    public func removeToken(for sandbox: String) throws { tokens[sandbox] = nil }
}

/// The real store: one generic password per sandbox, under a single service name.
public final class KeychainTokenStore: TokenStore {
    public static let defaultService = "fr.lauriat.sandboxwatch"
    private let service: String

    public init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    private func baseQuery(_ sandbox: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sandbox,
        ]
    }

    public func token(for sandbox: String) throws -> String? {
        var query = baseQuery(sandbox)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                throw SandboxWatchError("keychain item for '\(sandbox)' is not readable text")
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw SandboxWatchError("keychain read failed for '\(sandbox)' (OSStatus \(status))")
        }
    }

    /// Replaces rather than duplicates: the Keychain would otherwise accept a second item
    /// with the same service and account, and reads would return an arbitrary one of them.
    public func setToken(_ token: String, for sandbox: String) throws {
        try removeToken(for: sandbox)
        var query = baseQuery(sandbox)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SandboxWatchError("keychain write failed for '\(sandbox)' (OSStatus \(status))")
        }
    }

    public func removeToken(for sandbox: String) throws {
        let status = SecItemDelete(baseQuery(sandbox) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SandboxWatchError("keychain delete failed for '\(sandbox)' (OSStatus \(status))")
        }
    }
}

/// Reads a token, or explains exactly how to set one.
public func requireToken(_ store: TokenStore, for sandbox: String) throws -> String {
    guard let token = try store.token(for: sandbox), !token.isEmpty else {
        throw SandboxWatchError(
            "no token in the keychain for '\(sandbox)' — set one with: sbw sandbox add \(sandbox) --url <url>")
    }
    return token
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TokenStoreTests`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/TokenStore.swift Tests/SandboxWatchKitTests/TokenStoreTests.swift
git commit -m "feat: keychain token store behind a mockable protocol"
```

---

### Task 4: The HTTP seam and the date trap

**Files:**
- Create: `Sources/SandboxWatchKit/HTTPClient.swift`
- Create: `Sources/SandboxWatchKit/SandboxJSON.swift`
- Create: `Tests/SandboxWatchKitTests/MockHTTPClient.swift`
- Test: `Tests/SandboxWatchKitTests/HTTPClientTests.swift`

**Interfaces:**
- Consumes: `SandboxWatchError`.
- Produces:
  - `struct HTTPResponse { let statusCode: Int; let headers: [String: String]; let body: Data; func header(_ name: String) -> String? }` — `header(_:)` is case-insensitive.
  - `protocol HTTPClient { func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse; func post(_ url: URL, headers: [String: String]) async throws -> HTTPResponse }`
  - `final class URLSessionHTTPClient: HTTPClient`
  - `enum SandboxJSON { static let decoder: JSONDecoder }`
  - `final class MockHTTPClient: HTTPClient` (test target) with `stub(path:status:json:headers:)`, `stub(path:status:body:headers:)`, `fail(path:message:)`, `private(set) var requests: [(method: String, url: URL, headers: [String: String])]`.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/HTTPClientTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class HTTPClientTests: XCTestCase {
    // The server sends `X-Refresh-Skipped`; HTTP header names are case-insensitive and
    // URLSession may hand them back in any casing. A case-sensitive lookup would silently
    // miss the one header a guard depends on.
    func testHeaderLookupIsCaseInsensitive() {
        let response = HTTPResponse(statusCode: 200, headers: ["x-refresh-skipped": "true"], body: Data())
        XCTAssertEqual(response.header("X-Refresh-Skipped"), "true")
        XCTAssertEqual(response.header("x-refresh-skipped"), "true")
        XCTAssertNil(response.header("X-Missing"))
    }

    // `docs/api.md` shows "2026-09-16T08:00:00.000Z". JSONDecoder's built-in `.iso8601`
    // strategy REJECTS fractional seconds — decoding every snapshot would fail on a format
    // the server documents. Both spellings must decode.
    func testDecoderAcceptsFractionalAndWholeSeconds() throws {
        struct Stamped: Decodable { let at: Date }

        let withFraction = try SandboxJSON.decoder.decode(
            Stamped.self, from: Data(#"{"at":"2026-09-16T08:00:00.000Z"}"#.utf8))
        let withoutFraction = try SandboxJSON.decoder.decode(
            Stamped.self, from: Data(#"{"at":"2026-09-16T08:00:00Z"}"#.utf8))

        XCTAssertEqual(withFraction.at.timeIntervalSince1970, 1789545600, accuracy: 1)
        XCTAssertEqual(withFraction.at, withoutFraction.at)
    }

    func testDecoderRejectsNonsenseDateWithAClearMessage() {
        struct Stamped: Decodable { let at: Date }
        XCTAssertThrowsError(
            try SandboxJSON.decoder.decode(Stamped.self, from: Data(#"{"at":"not a date"}"#.utf8)))
    }

    func testMockRecordsRequestsAndReturnsStubs() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/healthz", status: 200, json: #"{"status":"ok","uptimeSeconds":12}"#)

        let response = try await mock.get(
            URL(string: "https://example.test/healthz")!, headers: ["X-Sandbox-Token": "abc"])

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(mock.requests.count, 1)
        XCTAssertEqual(mock.requests[0].method, "GET")
        XCTAssertEqual(mock.requests[0].headers["X-Sandbox-Token"], "abc")
    }

    func testMockCanSimulateATransportFailure() async {
        let mock = MockHTTPClient()
        mock.fail(path: "/healthz", message: "connection refused")
        do {
            _ = try await mock.get(URL(string: "https://example.test/healthz")!, headers: [:])
            XCTFail("expected a thrown transport failure")
        } catch {
            XCTAssertTrue("\(error)".contains("connection refused"))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HTTPClientTests`
Expected: FAIL — `cannot find 'HTTPResponse' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/HTTPClient.swift`:

```swift
import Foundation

public struct HTTPResponse {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// HTTP header names are case-insensitive, and URLSession does not promise a casing.
    /// `X-Refresh-Skipped` is read through here, so an exact-match lookup would be a silent bug.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// The network seam. Mocked in every test; `URLSessionHTTPClient` is the only implementation
/// that opens a socket.
public protocol HTTPClient {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
    func post(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send("GET", url, headers)
    }

    public func post(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send("POST", url, headers)
    }

    private func send(_ method: String, _ url: URL, _ headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SandboxWatchError("non-HTTP response from \(url)")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}
```

`Sources/SandboxWatchKit/SandboxJSON.swift`:

```swift
import Foundation

public enum SandboxJSON {
    /// `JSONDecoder.DateDecodingStrategy.iso8601` rejects fractional seconds, and the server
    /// documents `"2026-09-16T08:00:00.000Z"`. Using the built-in strategy would fail on every
    /// snapshot. Both spellings are accepted here, and nothing else is.
    public static let decoder: JSONDecoder = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) { return date }
            if let date = withoutFraction.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "expected an ISO 8601 instant, got '\(raw)'"))
        }
        return decoder
    }()
}
```

`Tests/SandboxWatchKitTests/MockHTTPClient.swift`:

```swift
import Foundation
@testable import SandboxWatchKit

/// Test double: records every request and answers stubs matched on the URL's path.
final class MockHTTPClient: HTTPClient {
    struct Request {
        let method: String
        let url: URL
        let headers: [String: String]
    }

    private(set) var requests: [Request] = []
    private var stubs: [(path: String, response: HTTPResponse)] = []
    private var failures: [(path: String, message: String)] = []

    func stub(path: String, status: Int, json: String, headers: [String: String] = [:]) {
        stub(path: path, status: status, body: Data(json.utf8), headers: headers)
    }

    func stub(path: String, status: Int, body: Data, headers: [String: String] = [:]) {
        stubs.append((path, HTTPResponse(statusCode: status, headers: headers, body: body)))
    }

    func fail(path: String, message: String) {
        failures.append((path, message))
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try answer("GET", url, headers)
    }

    func post(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try answer("POST", url, headers)
    }

    private func answer(_ method: String, _ url: URL, _ headers: [String: String]) throws -> HTTPResponse {
        requests.append(Request(method: method, url: url, headers: headers))
        if let failure = failures.last(where: { url.path.contains($0.path) }) {
            throw SandboxWatchError(failure.message)
        }
        guard let stub = stubs.last(where: { url.path.contains($0.path) }) else {
            throw SandboxWatchError("MockHTTPClient: no stub for \(url.path)")
        }
        return stub.response
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HTTPClientTests`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/HTTPClient.swift Sources/SandboxWatchKit/SandboxJSON.swift Tests/SandboxWatchKitTests/MockHTTPClient.swift Tests/SandboxWatchKitTests/HTTPClientTests.swift
git commit -m "feat: HTTP seam with case-insensitive headers and fractional-second dates"
```

---

### Task 5: The snapshot model — a denied section is not empty data

This is the task that carries the project's central property. Read spec §3 before writing it.

**Files:**
- Create: `Sources/SandboxWatchKit/Section.swift`
- Create: `Sources/SandboxWatchKit/Snapshot.swift`
- Test: `Tests/SandboxWatchKitTests/SectionTests.swift`
- Test: `Tests/SandboxWatchKitTests/SnapshotDecodingTests.swift`

**Interfaces:**
- Consumes: `SandboxJSON`.
- Produces:
  - `struct Section<T>` with `let outcome: Outcome`, `let durationMs: Int`, `enum Outcome { case ok(T), denied(message: String?), error(message: String?) }`, `func fold<R>(ok: (T) -> R, unavailable: (String) -> R) -> R`, `var isOK: Bool`, `var unavailableReason: String?`. `Section: Decodable where T: Decodable`.
  - `struct Snapshot: Decodable` with `identity`, `resources`, `plans`, `apps`, `budget`, `governance`, `probes`.
  - `struct SnapshotResponse: Decodable { let collectedAt: Date; let ageSeconds: Double; let snapshot: Snapshot }`
  - `struct AppsResponse: Decodable { let collectedAt: Date; let ageSeconds: Double; let apps: Section<[AzureApp]>; let probes: Section<[Probe]> }`
  - Payload types: `AzureApp`, `ServicePlan`, `AzureResource`, `Budget`, `Governance`, `Probe`, `Identity`.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/SectionTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class SectionTests: XCTestCase {
    private func decode(_ json: String) throws -> Section<[String]> {
        try SandboxJSON.decoder.decode(Section<[String]>.self, from: Data(json.utf8))
    }

    func testOKCarriesItsPayloadAndDuration() throws {
        let section = try decode(#"{"status":"ok","data":["a","b"],"message":null,"durationMs":312}"#)
        XCTAssertTrue(section.isOK)
        XCTAssertEqual(section.durationMs, 312)
        XCTAssertEqual(section.fold(ok: { $0 }, unavailable: { _ in [] }), ["a", "b"])
    }

    // THE test of this project. If a denied section could be read as an empty collection, the
    // moment a Reader role is revoked the UI would announce that every role assignment
    // vanished — the exact false alarm AzureSandboxManager was built to prevent, and which it
    // guards with a test of its own. Here the payload is unreachable without the outcome, and
    // `fold` forces the caller to say what an unavailable section looks like.
    func testDeniedSectionYieldsAReasonAndNeverAPayload() throws {
        let section = try decode(#"{"status":"denied","data":null,"message":"AuthorizationFailed","durationMs":40}"#)
        XCTAssertFalse(section.isOK)
        XCTAssertEqual(section.unavailableReason, "AuthorizationFailed")
        let rendered = section.fold(ok: { "\($0.count) items" }, unavailable: { "unavailable: \($0)" })
        XCTAssertEqual(rendered, "unavailable: AuthorizationFailed")
    }

    func testErrorSectionKeepsItsMessage() throws {
        let section = try decode(#"{"status":"error","data":null,"message":"ETIMEDOUT","durationMs":15000}"#)
        XCTAssertFalse(section.isOK)
        XCTAssertEqual(section.unavailableReason, "ETIMEDOUT")
        XCTAssertEqual(section.durationMs, 15000)
    }

    func testUnavailableSectionWithoutAMessageStillExplainsItself() throws {
        let section = try decode(#"{"status":"denied","data":null,"message":null,"durationMs":5}"#)
        XCTAssertEqual(section.unavailableReason, "denied")
    }

    // `durationMs` is a sibling of `status` in the documented envelope, present on every
    // status. Keeping it only on `.ok` would make the contract model a partial one.
    func testDurationIsKeptOnEveryStatus() throws {
        XCTAssertEqual(try decode(#"{"status":"denied","data":null,"message":null,"durationMs":40}"#).durationMs, 40)
        XCTAssertEqual(try decode(#"{"status":"error","data":null,"message":null,"durationMs":9}"#).durationMs, 9)
    }

    // A status the client does not know is not a success. Defaulting it to `.ok` with no data
    // would be the empty-data bug arriving through a new server version.
    func testUnknownStatusIsTreatedAsUnavailable() throws {
        let section = try decode(#"{"status":"partial","data":["a"],"message":null,"durationMs":1}"#)
        XCTAssertFalse(section.isOK)
        XCTAssertTrue(section.unavailableReason!.contains("partial"))
    }
}
```

`Tests/SandboxWatchKitTests/SnapshotDecodingTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class SnapshotDecodingTests: XCTestCase {
    /// A snapshot where governance is denied and everything else collected — the shape the
    /// founding incident produces.
    static let json = """
    {
      "collectedAt": "2026-09-16T08:00:00.000Z",
      "ageSeconds": 142.7,
      "snapshot": {
        "identity": { "status": "ok", "data": { "subscriptionId": "sub-1", "resourceGroup": "rg-sandbox" }, "message": null, "durationMs": 10 },
        "resources": { "status": "ok", "data": [ { "name": "api", "type": "Microsoft.Web/sites", "location": "westeurope" } ], "message": null, "durationMs": 120 },
        "plans": { "status": "ok", "data": [ { "name": "plan-1", "tier": "Basic", "size": "B1", "appCount": 2, "status": "Ready" } ], "message": null, "durationMs": 90 },
        "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": "NODE|20-lts", "httpsOnly": true, "url": "https://api.azurewebsites.net" } ], "message": null, "durationMs": 110 },
        "budget": { "status": "ok", "data": { "amount": 50, "spend": 12.5, "percentage": 25, "thresholds": [80, 100] }, "message": null, "durationMs": 300 },
        "governance": { "status": "denied", "data": null, "message": "AuthorizationFailed", "durationMs": 45 },
        "probes": { "status": "ok", "data": [ { "name": "api", "url": "https://api.azurewebsites.net", "statusCode": 200, "latencyMs": 87 } ], "message": null, "durationMs": 400 }
      }
    }
    """

    func testDecodesTheDocumentedEnvelope() throws {
        let response = try SandboxJSON.decoder.decode(
            SnapshotResponse.self, from: Data(Self.json.utf8))

        XCTAssertEqual(response.ageSeconds, 142.7, accuracy: 0.001)
        XCTAssertEqual(response.collectedAt.timeIntervalSince1970, 1789545600, accuracy: 1)
    }

    func testCollectedSectionsCarryTheirPayload() throws {
        let snapshot = try SandboxJSON.decoder
            .decode(SnapshotResponse.self, from: Data(Self.json.utf8)).snapshot

        XCTAssertEqual(snapshot.apps.fold(ok: { $0.map(\.name) }, unavailable: { _ in [] }), ["api"])
        XCTAssertEqual(snapshot.probes.fold(ok: { $0.first?.statusCode }, unavailable: { _ in nil }), 200)
        XCTAssertEqual(snapshot.budget.fold(ok: { $0.percentage }, unavailable: { _ in nil }), 25)
        // `ok` returns a non-optional String here, so the unavailable branch must match it:
        // `fold` deliberately forces both branches to agree on one type.
        XCTAssertEqual(snapshot.identity.fold(ok: { $0.subscriptionId }, unavailable: { $0 }), "sub-1")
    }

    func testDeniedGovernanceDoesNotLookLikeAnEmptyGovernance() throws {
        let snapshot = try SandboxJSON.decoder
            .decode(SnapshotResponse.self, from: Data(Self.json.utf8)).snapshot

        XCTAssertFalse(snapshot.governance.isOK)
        XCTAssertEqual(snapshot.governance.unavailableReason, "AuthorizationFailed")
    }

    func testUnavailableSectionNamesAreListed() throws {
        let snapshot = try SandboxJSON.decoder
            .decode(SnapshotResponse.self, from: Data(Self.json.utf8)).snapshot

        XCTAssertEqual(snapshot.unavailableSections, ["governance"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SectionTests`
Expected: FAIL — `cannot find 'Section' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/Section.swift`:

```swift
import Foundation

/// One collected section of a snapshot.
///
/// There is deliberately **no** `data` property and **no** `T?` accessor. The payload lives
/// inside `.ok`, so it cannot be read without first establishing that the collection
/// succeeded, and there is no optional to write `?? []` against.
///
/// This is not stylistic. AzureSandboxManager compares two snapshots only when both collected
/// a section successfully, because a naive diff would announce that every role assignment
/// disappeared at the very moment a Reader role is revoked. A client that renders a denied
/// section as "0 role assignments" reintroduces that false alarm from the outside — at the
/// worst possible moment, since `denied` is exactly what a revoked role looks like.
public struct Section<T> {
    public enum Outcome {
        case ok(T)
        case denied(message: String?)
        case error(message: String?)
    }

    public let outcome: Outcome
    /// The documented envelope carries `durationMs` on every status, so the model does too.
    public let durationMs: Int

    public init(outcome: Outcome, durationMs: Int) {
        self.outcome = outcome
        self.durationMs = durationMs
    }

    public var isOK: Bool {
        if case .ok = outcome { return true }
        return false
    }

    /// Why this section has no payload, in words fit to show an operator. `nil` when it does.
    public var unavailableReason: String? {
        switch outcome {
        case .ok: return nil
        case .denied(let message): return message ?? "denied"
        case .error(let message): return message ?? "error"
        }
    }

    /// The only way to reach the payload: the caller must also say what an unavailable
    /// section looks like, so "denied" can never fall through to a default empty rendering.
    public func fold<R>(ok: (T) -> R, unavailable: (String) -> R) -> R {
        switch outcome {
        case .ok(let value): return ok(value)
        case .denied, .error: return unavailable(unavailableReason!)
        }
    }
}

extension Section: Decodable where T: Decodable {
    private enum CodingKeys: String, CodingKey {
        case status, data, message, durationMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        let message = try container.decodeIfPresent(String.self, forKey: .message)
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0

        switch status {
        case "ok":
            self.outcome = .ok(try container.decode(T.self, forKey: .data))
        case "denied":
            self.outcome = .denied(message: message)
        case "error":
            self.outcome = .error(message: message)
        default:
            // A status this client does not know is not a success. Treating it as `.ok` with
            // no data would let the empty-data bug arrive through a future server version.
            self.outcome = .error(message: "unknown collector status '\(status)'")
        }
    }
}
```

`Sources/SandboxWatchKit/Snapshot.swift`:

```swift
import Foundation

public struct Identity: Decodable, Equatable {
    public let subscriptionId: String
    public let resourceGroup: String
}

public struct AzureResource: Decodable, Equatable {
    public let name: String
    public let type: String
    public let location: String
}

public struct ServicePlan: Decodable, Equatable {
    public let name: String
    public let tier: String?
    public let size: String?
    public let appCount: Int?
    public let status: String?
}

public struct AzureApp: Decodable, Equatable {
    public let name: String
    public let state: String?
    public let runtime: String?
    public let httpsOnly: Bool?
    public let url: String?

    public var isRunning: Bool { state?.caseInsensitiveCompare("Running") == .orderedSame }
}

public struct Budget: Decodable, Equatable {
    public let amount: Double?
    public let spend: Double?
    public let percentage: Double?
    public let thresholds: [Double]?
}

public struct RoleAssignment: Decodable, Equatable {
    public let principalId: String?
    public let roleDefinitionName: String?
    public let scope: String?
}

public struct ResourceLock: Decodable, Equatable {
    public let name: String?
    public let level: String?
}

public struct Governance: Decodable, Equatable {
    public let roleAssignments: [RoleAssignment]?
    public let locks: [ResourceLock]?
    public let denyAssignments: [String]?
}

public struct Probe: Decodable, Equatable {
    public let name: String
    public let url: String?
    public let statusCode: Int?
    public let latencyMs: Double?

    /// A probe with no status code did not answer at all.
    public var answered: Bool { statusCode != nil }
}

public struct Snapshot: Decodable {
    public let identity: Section<Identity>
    public let resources: Section<[AzureResource]>
    public let plans: Section<[ServicePlan]>
    public let apps: Section<[AzureApp]>
    public let budget: Section<Budget>
    public let governance: Section<Governance>
    public let probes: Section<[Probe]>

    /// The sections that did not collect, by name — what `doctor` reports and what the UI
    /// must explain rather than render as empty.
    public var unavailableSections: [String] {
        var names: [String] = []
        if !identity.isOK { names.append("identity") }
        if !resources.isOK { names.append("resources") }
        if !plans.isOK { names.append("plans") }
        if !apps.isOK { names.append("apps") }
        if !budget.isOK { names.append("budget") }
        if !governance.isOK { names.append("governance") }
        if !probes.isOK { names.append("probes") }
        return names
    }
}

public struct SnapshotResponse: Decodable {
    public let collectedAt: Date
    public let ageSeconds: Double
    public let snapshot: Snapshot
}

public struct AppsResponse: Decodable {
    public let collectedAt: Date
    public let ageSeconds: Double
    public let apps: Section<[AzureApp]>
    public let probes: Section<[Probe]>
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SectionTests && swift test --filter SnapshotDecodingTests`
Expected: PASS — 6 + 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/Section.swift Sources/SandboxWatchKit/Snapshot.swift Tests/SandboxWatchKitTests/SectionTests.swift Tests/SandboxWatchKitTests/SnapshotDecodingTests.swift
git commit -m "feat: snapshot model where a denied section cannot read as empty data"
```

---

### Task 6: The API contract

**Files:**
- Create: `Sources/SandboxWatchKit/SandboxAPIContract.swift`
- Test: `Tests/SandboxWatchKitTests/SandboxAPIContractTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum SandboxAPI` with `static let tokenHeader`, `static let refreshSkippedHeader`, `static let changeLimits: ClosedRange<Int>`, `static let defaultChangeLimit: Int`, `static func url(_ route: Route, base: URL) -> URL`, `enum Route { case snapshot, apps, changes(limit: Int), refresh, healthz }`, `static func requiresToken(_ route: Route) -> Bool`.
  - `enum APIFailure: Error, Equatable { case unauthorised, noSnapshot, notFound, serverError(String?), unexpected(status: Int), transport(String), malformed(String) }` with `var explanation: String`.
  - `static func failure(forStatus: Int, body: Data) -> APIFailure?` — `nil` when the status is a success.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/SandboxAPIContractTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class SandboxAPIContractTests: XCTestCase {
    private let base = URL(string: "https://sandbox-dev.azurewebsites.net")!

    func testRouteURLs() {
        XCTAssertEqual(SandboxAPI.url(.snapshot, base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/snapshot")
        XCTAssertEqual(SandboxAPI.url(.apps, base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/apps")
        XCTAssertEqual(SandboxAPI.url(.healthz, base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/healthz")
        XCTAssertEqual(SandboxAPI.url(.changes(limit: 50), base: base).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/changes?limit=50")
    }

    // A base URL with a trailing slash is what a human pastes from a browser. Producing
    // `//api/v1/snapshot` would 404 against the very server we are diagnosing.
    func testTrailingSlashInBaseURLIsHarmless() {
        let slashed = URL(string: "https://sandbox-dev.azurewebsites.net/")!
        XCTAssertEqual(SandboxAPI.url(.snapshot, base: slashed).absoluteString,
                       "https://sandbox-dev.azurewebsites.net/api/v1/snapshot")
    }

    // The server clamps out-of-range limits rather than rejecting them; the client clamps too,
    // so the URL it prints in an error is the limit the server actually used.
    func testChangeLimitIsClampedNotRejected() {
        XCTAssertEqual(SandboxAPI.url(.changes(limit: 0), base: base).query, "limit=1")
        XCTAssertEqual(SandboxAPI.url(.changes(limit: 9999), base: base).query, "limit=500")
    }

    func testOnlyHealthzGoesWithoutAToken() {
        XCTAssertTrue(SandboxAPI.requiresToken(.snapshot))
        XCTAssertTrue(SandboxAPI.requiresToken(.apps))
        XCTAssertTrue(SandboxAPI.requiresToken(.changes(limit: 50)))
        XCTAssertTrue(SandboxAPI.requiresToken(.refresh))
        XCTAssertFalse(SandboxAPI.requiresToken(.healthz))
    }

    func testDocumentedStatusCodesMapToModelledFailures() {
        XCTAssertNil(SandboxAPI.failure(forStatus: 200, body: Data()))
        XCTAssertEqual(SandboxAPI.failure(forStatus: 401, body: Data()), .unauthorised)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 503, body: Data()), .noSnapshot)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 404, body: Data()), .notFound)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 418, body: Data()), .unexpected(status: 418))
    }

    func testServerErrorKeepsTheDocumentedMessage() {
        let body = Data(#"{"error":"InternalError","message":"collector crashed"}"#.utf8)
        XCTAssertEqual(SandboxAPI.failure(forStatus: 500, body: body), .serverError("collector crashed"))
    }

    // 503 is the "not collected yet" case the server documents as retryable. Saying so in the
    // message is what stops an operator from redeploying a working app.
    func testNoSnapshotExplainsItselfAsTemporary() {
        XCTAssertTrue(APIFailure.noSnapshot.explanation.lowercased().contains("not collected"))
        XCTAssertFalse(APIFailure.noSnapshot.explanation.lowercased().contains("redeploy"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SandboxAPIContractTests`
Expected: FAIL — `cannot find 'SandboxAPI' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/SandboxAPIContract.swift`:

```swift
import Foundation

/// The executable half of `AzureSandboxManager/docs/api.md`. Routes, header names, limits and
/// status codes live here so a server change breaks a test rather than a screen.
public enum SandboxAPI {
    public static let tokenHeader = "X-Sandbox-Token"
    public static let refreshSkippedHeader = "X-Refresh-Skipped"
    public static let changeLimits: ClosedRange<Int> = 1...500
    public static let defaultChangeLimit = 50

    public enum Route: Equatable {
        case snapshot
        case apps
        case changes(limit: Int)
        case refresh
        case healthz
    }

    public static func requiresToken(_ route: Route) -> Bool {
        if case .healthz = route { return false }
        return true
    }

    public static func url(_ route: Route, base: URL) -> URL {
        // A pasted base URL often ends in "/", which would produce "//api/v1/..." and 404.
        let root = URL(string: base.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))) ?? base

        switch route {
        case .snapshot: return root.appendingPathComponent("api/v1/snapshot")
        case .apps:     return root.appendingPathComponent("api/v1/apps")
        case .refresh:  return root.appendingPathComponent("api/v1/refresh")
        case .healthz:  return root.appendingPathComponent("healthz")
        case .changes(let limit):
            let clamped = min(max(limit, changeLimits.lowerBound), changeLimits.upperBound)
            var components = URLComponents(
                url: root.appendingPathComponent("api/v1/changes"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: String(clamped))]
            return components.url!
        }
    }

    /// Returns `nil` for a success, or the modelled failure for a documented status code.
    public static func failure(forStatus status: Int, body: Data) -> APIFailure? {
        switch status {
        case 200..<300: return nil
        case 401:       return .unauthorised
        case 404:       return .notFound
        case 503:       return .noSnapshot
        case 500:       return .serverError(errorMessage(in: body))
        default:        return .unexpected(status: status)
        }
    }

    private static func errorMessage(in body: Data) -> String? {
        struct Envelope: Decodable { let error: String?; let message: String? }
        return (try? SandboxJSON.decoder.decode(Envelope.self, from: body))?.message
    }
}

/// Every way a call can fail to produce data. These are values, not thrown programmer errors:
/// each one is a state the CLI and the app must display and explain.
public enum APIFailure: Error, Equatable {
    case unauthorised
    case noSnapshot
    case notFound
    case serverError(String?)
    case unexpected(status: Int)
    case transport(String)
    case malformed(String)

    public var explanation: String {
        switch self {
        case .unauthorised:
            return "the token was refused — check the one stored for this sandbox"
        case .noSnapshot:
            return "the app is up but has not collected yet — wait for the next collection"
        case .notFound:
            return "no such route — the server may be older than this client"
        case .serverError(let message):
            return "the server failed: \(message ?? "no detail given")"
        case .unexpected(let status):
            return "unexpected HTTP status \(status)"
        case .transport(let message):
            return "could not reach the app: \(message)"
        case .malformed(let message):
            return "the response did not match the API contract: \(message)"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SandboxAPIContractTests`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/SandboxAPIContract.swift Tests/SandboxWatchKitTests/SandboxAPIContractTests.swift
git commit -m "feat: executable API contract with modelled failures"
```

---

### Task 7: The API client

**Files:**
- Create: `Sources/SandboxWatchKit/SandboxAPIClient.swift`
- Test: `Tests/SandboxWatchKitTests/SandboxAPIClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `SandboxAPI`, `APIFailure`, `SnapshotResponse`, `AppsResponse`, `SandboxJSON`.
- Produces: `struct SandboxAPIClient` with `init(baseURL: URL, token: String, http: HTTPClient)`, `func snapshot() async throws -> SnapshotResponse`, `func apps() async throws -> AppsResponse`, `func health() async throws -> Health`. `struct Health: Decodable { let status: String; let uptimeSeconds: Double }`.

> `changes(limit:)` is **not** part of this task: it returns `[ChangeEvent]`, which Task 8 defines. It is added in Task 8, so each task compiles on its own and the order below is linear.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/SandboxAPIClientTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class SandboxAPIClientTests: XCTestCase {
    private let base = URL(string: "https://sandbox-dev.azurewebsites.net")!

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "secret-token", http: mock)
    }

    func testSnapshotSendsTheTokenHeader() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: SnapshotDecodingTests.json)

        _ = try await client(mock).snapshot()

        XCTAssertEqual(mock.requests.first?.headers[SandboxAPI.tokenHeader], "secret-token")
    }

    func testHealthzGoesWithoutTheToken() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/healthz", status: 200, json: #"{"status":"ok","uptimeSeconds":1234}"#)

        let health = try await client(mock).health()

        XCTAssertEqual(health.status, "ok")
        XCTAssertNil(mock.requests.first?.headers[SandboxAPI.tokenHeader])
    }

    func testUnauthorisedBecomesAModelledFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 401,
                  json: #"{"error":"Unauthorized","message":"Missing or invalid X-Sandbox-Token header"}"#)

        await XCTAssertThrowsAPIFailure(.unauthorised) { try await self.client(mock).snapshot() }
    }

    func testNoSnapshotYetBecomesAModelledFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 503, json: #"{"error":"NoSnapshot"}"#)

        await XCTAssertThrowsAPIFailure(.noSnapshot) { try await self.client(mock).snapshot() }
    }

    func testTransportFailureIsWrappedNotLeaked() async {
        let mock = MockHTTPClient()
        mock.fail(path: "/api/v1/snapshot", message: "connection refused")

        await XCTAssertThrowsAPIFailure(.transport("connection refused")) {
            try await self.client(mock).snapshot()
        }
    }

    // A 200 whose body does not match the contract must not read as a valid empty snapshot.
    func testMalformedBodyIsItsOwnFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: #"{"unexpected":true}"#)

        do {
            _ = try await client(mock).snapshot()
            XCTFail("expected a malformed failure")
        } catch let failure as APIFailure {
            guard case .malformed = failure else { return XCTFail("got \(failure)") }
        } catch {
            XCTFail("got \(error)")
        }
    }

    func testAppsUsesTheNarrowRoute() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/apps", status: 200, json: """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": 10,
          "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": null, "httpsOnly": true, "url": null } ], "message": null, "durationMs": 5 },
          "probes": { "status": "ok", "data": [ { "name": "api", "url": null, "statusCode": 200, "latencyMs": 12 } ], "message": null, "durationMs": 7 }
        }
        """)

        let response = try await client(mock).apps()

        XCTAssertEqual(mock.requests.first?.url.path, "/api/v1/apps")
        XCTAssertEqual(response.apps.fold(ok: { $0.count }, unavailable: { _ in -1 }), 1)
    }
}

/// Small helper so each expectation reads as one line.
func XCTAssertThrowsAPIFailure(
    _ expected: APIFailure,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch let failure as APIFailure {
        XCTAssertEqual(failure, expected, file: file, line: line)
    } catch {
        XCTFail("expected \(expected), got \(error)", file: file, line: line)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SandboxAPIClientTests`
Expected: FAIL — `cannot find 'SandboxAPIClient' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/SandboxAPIClient.swift`:

```swift
import Foundation

public struct Health: Decodable, Equatable {
    public let status: String
    public let uptimeSeconds: Double
}

/// Typed calls on `/api/v1`. Every documented status code becomes an `APIFailure`, and a body
/// that does not match the contract becomes `.malformed` rather than a plausible-looking empty
/// result.
public struct SandboxAPIClient {
    private let baseURL: URL
    private let token: String
    private let http: HTTPClient

    public init(baseURL: URL, token: String, http: HTTPClient) {
        self.baseURL = baseURL
        self.token = token
        self.http = http
    }

    public func snapshot() async throws -> SnapshotResponse {
        try await get(.snapshot, as: SnapshotResponse.self)
    }

    public func apps() async throws -> AppsResponse {
        try await get(.apps, as: AppsResponse.self)
    }

    public func health() async throws -> Health {
        try await get(.healthz, as: Health.self)
    }

    private func get<T: Decodable>(_ route: SandboxAPI.Route, as type: T.Type) async throws -> T {
        let url = SandboxAPI.url(route, base: baseURL)
        let headers = SandboxAPI.requiresToken(route) ? [SandboxAPI.tokenHeader: token] : [:]

        let response: HTTPResponse
        do {
            response = try await http.get(url, headers: headers)
        } catch let failure as APIFailure {
            throw failure
        } catch {
            // Anything the transport throws is a reachability problem, not a server verdict.
            throw APIFailure.transport("\(error)")
        }

        if let failure = SandboxAPI.failure(forStatus: response.statusCode, body: response.body) {
            throw failure
        }

        do {
            return try SandboxJSON.decoder.decode(type, from: response.body)
        } catch {
            throw APIFailure.malformed("\(error)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SandboxAPIClientTests`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/SandboxAPIClient.swift Tests/SandboxWatchKitTests/SandboxAPIClientTests.swift
git commit -m "feat: typed API client mapping every documented status to a value"
```

---

### Task 8: Change events and their severity

**Files:**
- Create: `Sources/SandboxWatchKit/ChangeEvent.swift`
- Test: `Tests/SandboxWatchKitTests/ChangeEventTests.swift`

**Interfaces:**
- Consumes: `SandboxJSON`.
- Produces:
  - `struct ChangeEvent: Decodable, Equatable { let at: Date; let type: String; let subject: String; let collector: String?; let detail: [String: String]?; var mark: ChangeMark; var severity: ChangeSeverity }`
  - `struct ChangeMark: Codable, Equatable { let at: Date; let type: String; let subject: String }`
  - `enum ChangeSeverity: Int, Comparable { case informational, notable, critical }`

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/ChangeEventTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChangeEventTests`
Expected: FAIL — `cannot find 'ChangeEvent' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/ChangeEvent.swift`:

```swift
import Foundation

public enum ChangeSeverity: Int, Comparable, Codable {
    case informational
    case notable
    case critical

    public static func < (lhs: ChangeSeverity, rhs: ChangeSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A cursor's identity. Not `at` alone: timestamps are not guaranteed unique — several events
/// share one collection instant — and a time-only cursor either replays a tie or drops it.
public struct ChangeMark: Codable, Equatable {
    public let at: Date
    public let type: String
    public let subject: String

    public init(at: Date, type: String, subject: String) {
        self.at = at
        self.type = type
        self.subject = subject
    }
}

public struct ChangeEvent: Decodable, Equatable {
    public let at: Date
    public let type: String
    public let subject: String
    public let collector: String?
    public let detail: [String: String]?

    public var mark: ChangeMark { ChangeMark(at: at, type: type, subject: subject) }

    /// Losing or regaining collector access is the incident this project was written after:
    /// a Contributor role moved over a weekend with no notification. It gets its own level, so
    /// it is never queued behind a probe that flapped.
    public var severity: ChangeSeverity {
        switch type {
        case "collector_access_lost", "collector_access_restored":
            return .critical
        case "role_added", "role_removed", "lock_added", "lock_removed",
             "deny_assignment_added", "deny_assignment_removed", "budget_threshold_crossed":
            return .notable
        default:
            return .informational
        }
    }
}
```

> `detail` is typed `[String: String]?` because every documented example carries string values.
> If a server version sends a nested object there, `SandboxAPIClient` will surface it as
> `.malformed` — a visible contract break, which is the intended outcome.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ChangeEventTests`
Expected: PASS — 7 tests.

- [ ] **Step 5: Add `changes(limit:)` to the API client, test first**

Append to `Tests/SandboxWatchKitTests/SandboxAPIClientTests.swift`, inside the class:

```swift
    func testChangesUnwrapsTheEnvelopeAndKeepsOrder() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: """
        { "limit": 50, "events": [
          {"at":"2026-09-16T09:00:00.000Z","type":"role_added","subject":"alice"},
          {"at":"2026-09-16T08:00:00.000Z","type":"probe_status_changed","subject":"api"}
        ] }
        """)

        let events = try await client(mock).changes(limit: 50)

        XCTAssertEqual(events.map(\.type), ["role_added", "probe_status_changed"])
        XCTAssertEqual(mock.requests.first?.url.query, "limit=50")
    }
```

Run it (`swift test --filter testChangesUnwrapsTheEnvelope`) and confirm it fails with
`value of type 'SandboxAPIClient' has no member 'changes'`. Then add the method to
`Sources/SandboxWatchKit/SandboxAPIClient.swift`, just above `health()`:

```swift
    public func changes(limit: Int = SandboxAPI.defaultChangeLimit) async throws -> [ChangeEvent] {
        struct Envelope: Decodable { let limit: Int; let events: [ChangeEvent] }
        return try await get(.changes(limit: limit), as: Envelope.self).events
    }
```

Run it again and confirm it passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/SandboxWatchKit/ChangeEvent.swift Sources/SandboxWatchKit/SandboxAPIClient.swift Tests/SandboxWatchKitTests/ChangeEventTests.swift Tests/SandboxWatchKitTests/SandboxAPIClientTests.swift
git commit -m "feat: change events with access loss as its own severity"
```

---

### Task 9: The cursor and its overflow detection

**Files:**
- Create: `Sources/SandboxWatchKit/ChangeCursor.swift`
- Create: `Sources/SandboxWatchKit/CursorStore.swift`
- Test: `Tests/SandboxWatchKitTests/ChangeCursorTests.swift`
- Test: `Tests/SandboxWatchKitTests/CursorStoreTests.swift`

**Interfaces:**
- Consumes: `ChangeEvent`, `ChangeMark`, `SandboxWatchError`, `expandPath`.
- Produces:
  - `struct CursorScan: Equatable { let newEvents: [ChangeEvent]; let overflowed: Bool; var newest: ChangeMark? }`
  - `enum ChangeCursor { static func scan(page: [ChangeEvent], since mark: ChangeMark?) -> CursorScan; static func nextLimit(after limit: Int) -> Int? }`
  - `final class CursorStore` with `init(directory: String = CursorStore.defaultDirectory)`, `mark(for sandbox: String) throws -> ChangeMark?`, `setMark(_ mark: ChangeMark, for sandbox: String) throws`, `static let defaultDirectory = "~/.config/sbw/cursors"`.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/ChangeCursorTests.swift`:

```swift
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
```

`Tests/SandboxWatchKitTests/CursorStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChangeCursorTests`
Expected: FAIL — `cannot find 'ChangeCursor' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/ChangeCursor.swift`:

```swift
import Foundation

public struct CursorScan: Equatable {
    /// Newest first, as the API returns them.
    public let newEvents: [ChangeEvent]
    /// True when the page did not reach back as far as the mark: events fell off the end and
    /// the caller must widen the limit and ask again.
    public let overflowed: Bool
    /// Where to move the cursor once the caller has consumed `newEvents`.
    public let newest: ChangeMark?
}

public enum ChangeCursor {
    /// Decides what is new in a page of change events.
    ///
    /// `/api/v1/changes` returns newest first and caps at 500. Two properties matter here:
    ///
    /// - the mark is `(at, type, subject)`, because timestamps tie;
    /// - a page that never reaches the mark means events were lost, and that must be a signal
    ///   rather than a silent truncation.
    public static func scan(page: [ChangeEvent], since mark: ChangeMark?) -> CursorScan {
        let newest = page.first?.mark

        // First run: establish where we are, announce nothing. Otherwise adding a sandbox
        // would replay its whole history as notifications.
        guard let mark else {
            return CursorScan(newEvents: [], overflowed: false, newest: newest)
        }

        if let index = page.firstIndex(where: { $0.mark == mark }) {
            return CursorScan(newEvents: Array(page[0..<index]), overflowed: false, newest: newest)
        }

        guard let oldest = page.last else {
            return CursorScan(newEvents: [], overflowed: false, newest: nil)
        }

        if oldest.at > mark.at {
            // Everything in the page is newer than the mark and the mark is not in it: the
            // page did not reach far enough back, so something between them was not returned.
            return CursorScan(newEvents: page, overflowed: true, newest: newest)
        }

        // We reached back past the mark's instant, so nothing was lost. The marked event
        // itself is simply gone — pruned, or the mark predates the log.
        //
        // This is the one path that compares time alone, and it therefore drops any sibling
        // that shared the marked event's instant. That is deliberate: once the marked event is
        // gone there is nothing left to order its ties against, and re-announcing a change the
        // operator has already seen is the worse of the two errors here.
        return CursorScan(
            newEvents: page.filter { $0.at > mark.at }, overflowed: false, newest: newest)
    }

    /// The widening ladder used after an overflow. `nil` means the server's ceiling is
    /// reached and the caller must report the gap instead of asking again.
    public static func nextLimit(after limit: Int) -> Int? {
        switch limit {
        case ..<200: return 200
        case ..<500: return 500
        default: return nil
        }
    }
}
```

`Sources/SandboxWatchKit/CursorStore.swift`:

```swift
import Foundation

/// Where each sandbox's last-seen change lives, so the CLI and the app agree on what has
/// already been reported.
public final class CursorStore {
    public static let defaultDirectory = "~/.config/sbw/cursors"
    private let directory: String

    public init(directory: String = CursorStore.defaultDirectory) {
        self.directory = expandPath(directory)
    }

    private func path(for sandbox: String) throws -> String {
        // A sandbox name comes from the command line; letting it act as a path would write
        // outside this directory.
        guard !sandbox.isEmpty, !sandbox.contains("/"), sandbox != ".", sandbox != ".." else {
            throw SandboxWatchError("invalid sandbox name '\(sandbox)'")
        }
        return directory + "/" + sandbox + ".json"
    }

    /// A missing or unreadable cursor is "no cursor": a fresh start, never a crash that
    /// blocks every command.
    public func mark(for sandbox: String) throws -> ChangeMark? {
        let path = try path(for: sandbox)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? SandboxJSON.decoder.decode(ChangeMark.self, from: data)
    }

    public func setMark(_ mark: ChangeMark, for sandbox: String) throws {
        let path = try path(for: sandbox)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        try encoder.encode(mark).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ChangeCursorTests && swift test --filter CursorStoreTests`
Expected: PASS — 8 + 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/ChangeCursor.swift Sources/SandboxWatchKit/CursorStore.swift Tests/SandboxWatchKitTests/ChangeCursorTests.swift Tests/SandboxWatchKitTests/CursorStoreTests.swift
git commit -m "feat: change cursor with tie-safe identity and overflow detection"
```

---

### Task 10: The five-verdict diagnosis

**Files:**
- Create: `Sources/SandboxWatchKit/Doctor.swift`
- Test: `Tests/SandboxWatchKitTests/DoctorTests.swift`

**Interfaces:**
- Consumes: `SandboxAPIClient`, `APIFailure`, `SnapshotResponse`.
- Produces:
  - `enum Finding: Equatable { case unreachable(String), unauthorised, notCollectedYet, sectionsUnavailable([String]), stale(ageSeconds: Double), healthy(ageSeconds: Double), serverProblem(String) }` with `var headline: String`, `var nextStep: String?`, `var isProblem: Bool`.
  - `struct Doctor` with `init(client: SandboxAPIClient, staleAfterSeconds: Double = 1800)` and `func diagnose() async -> [Finding]` — always non-empty, most important first.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/DoctorTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class DoctorTests: XCTestCase {
    private let base = URL(string: "https://sandbox-dev.azurewebsites.net")!

    private func doctor(_ mock: MockHTTPClient, staleAfter: Double = 1800) -> Doctor {
        Doctor(client: SandboxAPIClient(baseURL: base, token: "t", http: mock),
               staleAfterSeconds: staleAfter)
    }

    private func snapshotJSON(ageSeconds: Double, governance: String) -> String {
        """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": \(ageSeconds),
          "snapshot": {
            "identity": { "status": "ok", "data": { "subscriptionId": "sub-1", "resourceGroup": "rg" }, "message": null, "durationMs": 1 },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "budget": { "status": "ok", "data": {}, "message": null, "durationMs": 1 },
            "governance": \(governance),
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """
    }

    private let okGovernance = #"{ "status": "ok", "data": {}, "message": null, "durationMs": 1 }"#
    private let deniedGovernance = #"{ "status": "denied", "data": null, "message": "AuthorizationFailed", "durationMs": 1 }"#

    func testUnreachableAppIsTheOnlyFinding() async {
        let mock = MockHTTPClient()
        mock.fail(path: "/api/v1/snapshot", message: "connection refused")

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings.count, 1)
        guard case .unreachable = findings[0] else { return XCTFail("got \(findings)") }
    }

    func testRefusedTokenIsTheOnlyFinding() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 401, json: #"{"error":"Unauthorized"}"#)

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings, [.unauthorised])
    }

    // 503 means the app is up and has simply not finished a first collection. Reporting it as
    // a broken deployment is what sends someone redeploying a working app.
    func testNoSnapshotYetSaysWaitNotRedeploy() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 503, json: #"{"error":"NoSnapshot"}"#)

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings, [.notCollectedYet])
        // Not "must not contain the word redeploy": the best possible message contains it,
        // as a warning. What matters is that it tells the operator to wait and says plainly
        // that redeploying is the wrong move.
        let step = findings[0].nextStep!.lowercased()
        XCTAssertTrue(step.contains("wait"))
        XCTAssertTrue(step.contains("do not redeploy"))
    }

    func testHealthySnapshotReportsItsAge() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: snapshotJSON(ageSeconds: 120, governance: okGovernance))

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings.count, 1)
        guard case .healthy(let age) = findings[0] else { return XCTFail("got \(findings)") }
        XCTAssertEqual(age, 120, accuracy: 0.001)
    }

    // The verdict that matters most. A denied section right after granting a role is the
    // documented managed-identity propagation delay — up to 24 hours — not a failure. The
    // next step must say so, or the operator repeats the assignment that already worked.
    func testDeniedSectionsPointAtRolePropagationNotFailure() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: snapshotJSON(ageSeconds: 60, governance: deniedGovernance))

        let findings = await doctor(mock).diagnose()

        XCTAssertEqual(findings, [.sectionsUnavailable(["governance"])])
        XCTAssertTrue(findings[0].nextStep!.contains("24"))
    }

    func testStaleSnapshotIsReportedBeforeItsDeniedSections() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: snapshotJSON(ageSeconds: 7200, governance: deniedGovernance))

        let findings = await doctor(mock).diagnose()

        // Both are true, and staleness comes first: a two-hour-old reading of "denied" may
        // describe a state that no longer exists.
        XCTAssertEqual(findings.count, 2)
        guard case .stale = findings[0] else { return XCTFail("got \(findings)") }
        XCTAssertEqual(findings[1], .sectionsUnavailable(["governance"]))
    }

    func testEveryFindingKnowsWhetherItIsAProblem() {
        XCTAssertFalse(Doctor.Finding.healthy(ageSeconds: 10).isProblem)
        XCTAssertTrue(Doctor.Finding.unauthorised.isProblem)
        XCTAssertTrue(Doctor.Finding.sectionsUnavailable(["governance"]).isProblem)
        XCTAssertTrue(Doctor.Finding.stale(ageSeconds: 9999).isProblem)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DoctorTests`
Expected: FAIL — `cannot find 'Doctor' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/Doctor.swift`:

```swift
import Foundation

/// Separates the states an operator confuses at the worst moment. The project the server was
/// written after began with half an hour spent on wrong readings — "the subscription was
/// deleted", "the tenant moved" — when the truth was a role assignment that had moved.
public struct Doctor {
    public enum Finding: Equatable {
        case unreachable(String)
        case unauthorised
        case notCollectedYet
        case serverProblem(String)
        case stale(ageSeconds: Double)
        case sectionsUnavailable([String])
        case healthy(ageSeconds: Double)

        public var isProblem: Bool {
            if case .healthy = self { return false }
            return true
        }

        public var headline: String {
            switch self {
            case .unreachable(let detail):
                return "the app could not be reached (\(detail))"
            case .unauthorised:
                return "the token was refused"
            case .notCollectedYet:
                return "the app is up but has not completed a collection yet"
            case .serverProblem(let detail):
                return "the server reported a failure: \(detail)"
            case .stale(let age):
                return "the snapshot is \(Int(age / 60)) minutes old"
            case .sectionsUnavailable(let names):
                return "these sections did not collect: \(names.joined(separator: ", "))"
            case .healthy(let age):
                return "everything collected, \(Int(age)) seconds ago"
            }
        }

        public var nextStep: String? {
            switch self {
            case .unreachable:
                return "check the URL in the inventory, and that the web app is running"
            case .unauthorised:
                return "set the token again: sbw sandbox add <name> --url <url>"
            case .notCollectedYet:
                return "wait for the next collection — do not redeploy, the app is working"
            case .serverProblem:
                return "check the web app's log stream in Azure"
            case .stale:
                return "the collector has stalled; check the app's log stream"
            case .sectionsUnavailable:
                return "grant Reader on the resource group to the app's managed identity — "
                     + "and if you just granted it, wait: role membership is cached and Microsoft "
                     + "documents up to 24 hours before it takes effect. This is not a failure."
            case .healthy:
                return nil
            }
        }
    }

    private let client: SandboxAPIClient
    private let staleAfterSeconds: Double

    /// Default threshold: three times the server's default ten-minute interval. The API does
    /// not expose the configured interval, so this is a decision, not a reading.
    public init(client: SandboxAPIClient, staleAfterSeconds: Double = 1800) {
        self.client = client
        self.staleAfterSeconds = staleAfterSeconds
    }

    /// Always non-empty, most important first. Several findings can be true at once — a stale
    /// snapshot that also shows denied sections — and reducing that to one verdict would hide
    /// whichever the operator needed.
    public func diagnose() async -> [Finding] {
        let response: SnapshotResponse
        do {
            response = try await client.snapshot()
        } catch let failure as APIFailure {
            switch failure {
            case .transport(let detail):    return [.unreachable(detail)]
            case .unauthorised:             return [.unauthorised]
            case .noSnapshot:               return [.notCollectedYet]
            case .notFound:                 return [.serverProblem(failure.explanation)]
            case .serverError, .unexpected: return [.serverProblem(failure.explanation)]
            case .malformed(let detail):    return [.serverProblem("malformed response: \(detail)")]
            }
        } catch {
            return [.unreachable("\(error)")]
        }

        var findings: [Finding] = []

        // Staleness first: a two-hour-old reading of "denied" may describe a state that no
        // longer exists, so the age has to be known before the sections are believed.
        if response.ageSeconds > staleAfterSeconds {
            findings.append(.stale(ageSeconds: response.ageSeconds))
        }

        let unavailable = response.snapshot.unavailableSections
        if !unavailable.isEmpty {
            findings.append(.sectionsUnavailable(unavailable))
        }

        if findings.isEmpty {
            findings.append(.healthy(ageSeconds: response.ageSeconds))
        }
        return findings
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DoctorTests`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/Doctor.swift Tests/SandboxWatchKitTests/DoctorTests.swift
git commit -m "feat: doctor separating propagation delay from failure"
```

---

### Task 11: The status row

**Files:**
- Create: `Sources/SandboxWatchKit/StatusRow.swift`
- Test: `Tests/SandboxWatchKitTests/StatusRowTests.swift`

**Interfaces:**
- Consumes: `SnapshotResponse`, `Sandbox`, `APIFailure`.
- Produces: `struct StatusRow: Equatable { let sandbox: String; let age: String; let apps: String; let budget: String; let sections: String; let problem: String? }`, `static func make(sandbox: String, response: SnapshotResponse) -> StatusRow`, `static func unreachable(sandbox: String, failure: APIFailure) -> StatusRow`, and `func renderTable(_ rows: [StatusRow]) -> String`.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/StatusRowTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class StatusRowTests: XCTestCase {
    private func response(_ json: String) throws -> SnapshotResponse {
        try SandboxJSON.decoder.decode(SnapshotResponse.self, from: Data(json.utf8))
    }

    private func json(ageSeconds: Double, apps: String, budget: String, governance: String) -> String {
        """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": \(ageSeconds),
          "snapshot": {
            "identity": { "status": "ok", "data": { "subscriptionId": "sub-1", "resourceGroup": "rg" }, "message": null, "durationMs": 1 },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": \(apps),
            "budget": \(budget),
            "governance": \(governance),
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """
    }

    private let twoAppsOneStopped = #"""
    { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": null, "httpsOnly": true, "url": null }, { "name": "web", "state": "Stopped", "runtime": null, "httpsOnly": true, "url": null } ], "message": null, "durationMs": 1 }
    """#
    private let okBudget = #"{ "status": "ok", "data": { "amount": 50, "spend": 12.5, "percentage": 25, "thresholds": [] }, "message": null, "durationMs": 1 }"#
    private let okGovernance = #"{ "status": "ok", "data": {}, "message": null, "durationMs": 1 }"#
    private let deniedSection = #"{ "status": "denied", "data": null, "message": "AuthorizationFailed", "durationMs": 1 }"#

    func testAppsColumnCountsRunningOutOfTotal() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.apps, "1/2 up")
    }

    func testAgeIsHumanReadable() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 3900, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.age, "1h5m")
    }

    func testBudgetShowsThePercentage() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.budget, "25%")
    }

    // A denied section must never print as "0/0 up" or "0%". It prints why it is missing —
    // the client-side half of the rule the server guards with a test.
    func testDeniedSectionsPrintTheirReasonNotAZero() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: deniedSection, budget: deniedSection, governance: okGovernance)))

        XCTAssertEqual(row.apps, "denied")
        XCTAssertEqual(row.budget, "denied")
        XCTAssertNotEqual(row.apps, "0/0 up")
    }

    func testSectionsColumnNamesWhatDidNotCollect() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: deniedSection)))
        XCTAssertEqual(row.sections, "governance")
        XCTAssertNotNil(row.problem)
    }

    func testAllCollectedSectionsColumnSaysSo() throws {
        let row = StatusRow.make(sandbox: "dev", response: try response(
            json(ageSeconds: 60, apps: twoAppsOneStopped, budget: okBudget, governance: okGovernance)))
        XCTAssertEqual(row.sections, "all")
        XCTAssertNil(row.problem)
    }

    func testUnreachableSandboxStillGetsARow() {
        let row = StatusRow.unreachable(sandbox: "dev", failure: .transport("connection refused"))
        XCTAssertEqual(row.sandbox, "dev")
        XCTAssertEqual(row.age, "—")
        XCTAssertTrue(row.problem!.contains("connection refused"))
    }

    func testTableAlignsColumns() {
        let rows = [
            StatusRow(sandbox: "dev", age: "2m", apps: "1/2 up", budget: "25%", sections: "all", problem: nil),
            StatusRow(sandbox: "production", age: "1h5m", apps: "3/3 up", budget: "80%", sections: "governance", problem: "governance denied"),
        ]
        let lines = renderTable(rows).split(separator: "\n").map(String.init)

        XCTAssertTrue(lines[0].hasPrefix("SANDBOX"))
        // Every column starts at the same offset on every line.
        let offsets = lines.map { $0.range(of: "up")?.lowerBound }
        XCTAssertEqual(lines[1].distance(from: lines[1].startIndex, to: offsets[1]!),
                       lines[2].distance(from: lines[2].startIndex, to: offsets[2]!))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatusRowTests`
Expected: FAIL — `cannot find 'StatusRow' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/SandboxWatchKit/StatusRow.swift`:

```swift
import Foundation

/// One line of `sbw status`. A view model, not a formatter: the app reuses it.
public struct StatusRow: Equatable {
    public let sandbox: String
    public let age: String
    public let apps: String
    public let budget: String
    public let sections: String
    public let problem: String?

    public init(sandbox: String, age: String, apps: String, budget: String, sections: String, problem: String?) {
        self.sandbox = sandbox
        self.age = age
        self.apps = apps
        self.budget = budget
        self.sections = sections
        self.problem = problem
    }

    public static func make(sandbox: String, response: SnapshotResponse) -> StatusRow {
        let snapshot = response.snapshot

        // `fold` forces both branches: a denied section prints why, never a zero that reads as
        // a measurement.
        let apps = snapshot.apps.fold(
            ok: { apps in "\(apps.filter(\.isRunning).count)/\(apps.count) up" },
            unavailable: { _ in "denied" })

        let budget = snapshot.budget.fold(
            ok: { budget in budget.percentage.map { "\(Int($0))%" } ?? "—" },
            unavailable: { _ in "denied" })

        let unavailable = snapshot.unavailableSections

        return StatusRow(
            sandbox: sandbox,
            age: humanDuration(response.ageSeconds),
            apps: apps,
            budget: budget,
            sections: unavailable.isEmpty ? "all" : unavailable.joined(separator: ","),
            problem: unavailable.isEmpty ? nil : "\(unavailable.joined(separator: ", ")) did not collect")
    }

    public static func unreachable(sandbox: String, failure: APIFailure) -> StatusRow {
        StatusRow(sandbox: sandbox, age: "—", apps: "—", budget: "—", sections: "—",
                  problem: failure.explanation)
    }
}

/// "45s", "2m", "1h5m". Deliberately short: this sits in a table column.
public func humanDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total)s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h\(minutes % 60)m"
}

public func renderTable(_ rows: [StatusRow]) -> String {
    let header = ["SANDBOX", "AGE", "APPS", "BUDGET", "SECTIONS"]
    let body = rows.map { [$0.sandbox, $0.age, $0.apps, $0.budget, $0.sections] }
    let all = [header] + body

    let widths = (0..<header.count).map { column in
        all.map { $0[column].count }.max() ?? 0
    }

    return all.map { line in
        line.enumerated()
            .map { index, cell in
                index == line.count - 1 ? cell : cell.padding(toLength: widths[index] + 2, withPad: " ", startingAt: 0)
            }
            .joined()
    }.joined(separator: "\n")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StatusRowTests`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/StatusRow.swift Tests/SandboxWatchKitTests/StatusRowTests.swift
git commit -m "feat: status row that prints a reason where a section is denied"
```

---

### Task 12: `sbw sandbox add / list / remove`

**Files:**
- Create: `Sources/sbw/SandboxCommands.swift`
- Modify: `Sources/sbw/SBW.swift` — add `SandboxCommand.self` to `subcommands`
- Test: `Tests/SandboxWatchKitTests/SandboxCommandsTests.swift`

**Interfaces:**
- Consumes: `SandboxStore`, `TokenStore`, `InMemoryTokenStore`, `Sandbox`, `SandboxWatchError`.
- Produces: `enum SandboxAdmin { static func add(name:url:notes:token:store:tokens:) throws -> String; static func list(store:) throws -> String; static func remove(name:store:tokens:) throws -> String }` in the `sbw` target — the testable core, with `ParsableCommand` types as thin wrappers around it.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/SandboxCommandsTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SandboxCommandsTests`
Expected: FAIL — `no such module 'sbw'` or `cannot find 'SandboxAdmin' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/sbw/SandboxCommands.swift`:

```swift
import ArgumentParser
import Foundation
import SandboxWatchKit

/// The decisions behind `sbw sandbox …`, separated from ArgumentParser so they can be tested
/// without spawning a process.
/// Reads one line with terminal echo off, so the token is not left on screen — and falls back
/// to a plain read when stdin is not a terminal (a pipe, a test, CI), where there is no echo
/// to disable. `readLine()` alone would echo: never promise otherwise in the prompt.
func readSecretLine() -> String? {
    guard isatty(STDIN_FILENO) == 1 else { return readLine(strippingNewline: true) }

    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else { return readLine(strippingNewline: true) }
    var quiet = original
    quiet.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &quiet)
    defer {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        FileHandle.standardError.write(Data("\n".utf8))
    }
    return readLine(strippingNewline: true)
}

enum SandboxAdmin {
    static func add(
        name: String, url: String, notes: String?, token: String,
        store: SandboxStore, tokens: TokenStore
    ) throws -> String {
        guard let parsed = URL(string: url), parsed.host != nil else {
            throw SandboxWatchError("'\(url)' is not a URL")
        }
        // The dashboard exposes infrastructure detail and the token travels in the header.
        // Over plain HTTP both are readable by anyone on the path.
        guard parsed.scheme?.lowercased() == "https" else {
            throw SandboxWatchError("the URL must be https — '\(url)' is not")
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SandboxWatchError("the token is empty")
        }

        // Reject a duplicate name before writing anything. Discovering it after the token is
        // written would mean undoing that write — and the token now sitting there belongs to
        // the sandbox that already exists, so "undo" would destroy working configuration.
        guard try !store.load().sandboxes.contains(where: { $0.name == name }) else {
            throw SandboxWatchError("sandbox '\(name)' already exists — remove it first, or pick another name")
        }

        // The token goes in first: the other order leaves the inventory holding a sandbox with
        // no token when the keychain write fails, and the repair the operator is then told to
        // run — `sbw sandbox add <name>` — would fail with "already exists".
        //
        // The rollback restores what was there rather than deleting, so a failure here can
        // never leave the keychain emptier than it found it.
        let previous = try tokens.token(for: name)
        try tokens.setToken(trimmed, for: name)
        do {
            try store.add(Sandbox(name: name, url: parsed, notes: notes))
        } catch {
            if let previous {
                try? tokens.setToken(previous, for: name)
            } else {
                try? tokens.removeToken(for: name)
            }
            throw error
        }
        return "added '\(name)' (\(parsed.absoluteString)); token stored in the keychain"
    }

    static func list(store: SandboxStore) throws -> String {
        let sandboxes = try store.load().sandboxes
        guard !sandboxes.isEmpty else {
            return "no sandbox declared — add one with: sbw sandbox add <name> --url <https url>"
        }
        return sandboxes.map { sandbox in
            let notes = sandbox.notes.map { "  — \($0)" } ?? ""
            return "\(sandbox.name)  \(sandbox.url.absoluteString)\(notes)"
        }.joined(separator: "\n")
    }

    static func remove(name: String, store: SandboxStore, tokens: TokenStore) throws -> String {
        guard try store.remove(named: name) else {
            throw SandboxWatchError("unknown sandbox '\(name)'")
        }
        // The token outlives nothing: a keychain entry for a sandbox that no longer exists
        // would never be cleaned up by anything else.
        try tokens.removeToken(for: name)
        return "removed '\(name)' and its token"
    }
}

struct SandboxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sandbox",
        abstract: "Declare the sandboxes to watch.",
        subcommands: [Add.self, List.self, Remove.self])

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a sandbox. The token is read from stdin, never from an argument.")

        @Argument(help: "A short name for this sandbox.") var name: String
        @Option(help: "The https base URL of the Azure Sandbox Manager app.") var url: String
        @Option(help: "A free-text note.") var notes: String?

        func run() throws {
            // An argument would land in the shell history and in the process table, where
            // anyone on the machine can read it. stdin keeps it out of both.
            FileHandle.standardError.write(Data("Token for '\(name)': ".utf8))
            guard let token = readSecretLine() else {
                throw SandboxWatchError("no token read from stdin")
            }
            print(try SandboxAdmin.add(name: name, url: url, notes: notes, token: token,
                                       store: SandboxStore(), tokens: KeychainTokenStore()))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the declared sandboxes.")

        func run() throws {
            print(try SandboxAdmin.list(store: SandboxStore()))
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a sandbox and its token.")

        @Argument var name: String

        func run() throws {
            print(try SandboxAdmin.remove(name: name, store: SandboxStore(), tokens: KeychainTokenStore()))
        }
    }
}
```

Then in `Sources/sbw/SBW.swift`, change the `subcommands` line to:

```swift
        subcommands: [SandboxCommand.self]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SandboxCommandsTests`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/sbw Tests/SandboxWatchKitTests/SandboxCommandsTests.swift
git commit -m "feat: sbw sandbox add/list/remove with the token off disk"
```

---

### Task 13: `sbw status`, `sbw doctor`, `sbw changes`

**Files:**
- Create: `Sources/sbw/ReadCommands.swift`
- Modify: `Sources/sbw/SBW.swift` — extend `subcommands`
- Test: `Tests/SandboxWatchKitTests/ReadCommandsTests.swift`

**Interfaces:**
- Consumes: `SandboxAPIClient`, `Doctor`, `StatusRow`, `renderTable`, `ChangeCursor`, `CursorStore`, `MockHTTPClient`.
- Produces: `enum ReadCommands { static func status(sandboxes:clientFor:) async -> String; static func doctor(sandbox:client:) async -> String; static func changes(sandbox:client:cursors:limit:advance:) async throws -> String }`.

- [ ] **Step 1: Write the failing test**

`Tests/SandboxWatchKitTests/ReadCommandsTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class ReadCommandsTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "t", http: mock)
    }

    private func healthySnapshot(ageSeconds: Double = 60) -> String {
        """
        {
          "collectedAt": "2026-09-16T08:00:00.000Z",
          "ageSeconds": \(ageSeconds),
          "snapshot": {
            "identity": { "status": "ok", "data": { "subscriptionId": "sub-1", "resourceGroup": "rg" }, "message": null, "durationMs": 1 },
            "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
            "apps": { "status": "ok", "data": [ { "name": "api", "state": "Running", "runtime": null, "httpsOnly": true, "url": null } ], "message": null, "durationMs": 1 },
            "budget": { "status": "ok", "data": { "amount": 50, "spend": 5, "percentage": 10, "thresholds": [] }, "message": null, "durationMs": 1 },
            "governance": { "status": "ok", "data": {}, "message": null, "durationMs": 1 },
            "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
          }
        }
        """
    }

    func testStatusRendersOneRowPerSandbox() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthySnapshot())

        let output = await ReadCommands.status(sandboxes: ["dev", "prod"]) { _ in self.client(mock) }

        XCTAssertTrue(output.contains("SANDBOX"))
        XCTAssertTrue(output.contains("dev"))
        XCTAssertTrue(output.contains("prod"))
    }

    // One unreachable sandbox must not take the others down with it: `--all` is exactly the
    // moment you are looking for the one that is broken.
    func testStatusKeepsGoingWhenOneSandboxIsUnreachable() async {
        let good = MockHTTPClient()
        good.stub(path: "/api/v1/snapshot", status: 200, json: healthySnapshot())
        let bad = MockHTTPClient()
        bad.fail(path: "/api/v1/snapshot", message: "connection refused")

        let output = await ReadCommands.status(sandboxes: ["dev", "broken"]) { name in
            self.client(name == "dev" ? good : bad)
        }

        XCTAssertTrue(output.contains("dev"))
        XCTAssertTrue(output.contains("broken"))
        XCTAssertTrue(output.contains("connection refused"))
    }

    func testDoctorPrintsHeadlineAndNextStep() async {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 503, json: #"{"error":"NoSnapshot"}"#)

        let output = await ReadCommands.doctor(sandbox: "dev", client: client(mock))

        XCTAssertTrue(output.contains("has not completed a collection"))
        XCTAssertTrue(output.contains("do not redeploy"))
    }

    func testChangesPrintsNewEventsNewestFirst() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: """
        { "limit": 50, "events": [
          {"at":"2026-09-16T09:00:00.000Z","type":"role_added","subject":"alice"},
          {"at":"2026-09-16T08:00:00.000Z","type":"probe_status_changed","subject":"api"}
        ] }
        """)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")
        // Seed the cursor at the older event so the newer one is the only thing reported.
        try cursors.setMark(
            ChangeMark(at: ISO8601DateFormatter().date(from: "2026-09-16T08:00:00Z")!,
                       type: "probe_status_changed", subject: "api"),
            for: "dev")

        let output = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: true)

        XCTAssertTrue(output.contains("role_added"))
        XCTAssertFalse(output.contains("probe_status_changed"))
    }

    // The overflow signal must reach the operator. A quiet truncation is the failure mode a
    // change-detection tool can least afford.
    func testChangesSaysSoWhenThePageDidNotReachBackFarEnough() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: """
        { "limit": 500, "events": [
          {"at":"2026-09-16T09:00:00.000Z","type":"role_added","subject":"alice"}
        ] }
        """)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")
        try cursors.setMark(
            ChangeMark(at: ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z")!,
                       type: "gone", subject: "gone"),
            for: "dev")

        let output = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 500, advance: true)

        XCTAssertTrue(output.lowercased().contains("older events were not returned"))
    }

    func testChangesOnAQuietSandboxSaysNothingChanged() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: #"{ "limit": 50, "events": [] }"#)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")

        let output = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: true)

        XCTAssertTrue(output.lowercased().contains("nothing"))
    }

    func testChangesAdvancesTheCursorOnlyWhenAsked() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/changes", status: 200, json: """
        { "limit": 50, "events": [ {"at":"2026-09-16T09:00:00.000Z","type":"role_added","subject":"alice"} ] }
        """)
        let cursors = CursorStore(directory: NSTemporaryDirectory() + "sbw-\(UUID().uuidString)")

        _ = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: false)
        XCTAssertNil(try cursors.mark(for: "dev"))

        _ = try await ReadCommands.changes(
            sandbox: "dev", client: client(mock), cursors: cursors, limit: 50, advance: true)
        XCTAssertNotNil(try cursors.mark(for: "dev"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReadCommandsTests`
Expected: FAIL — `cannot find 'ReadCommands' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/sbw/ReadCommands.swift`:

```swift
import ArgumentParser
import Foundation
import SandboxWatchKit

enum ReadCommands {
    /// `clientFor` is injected so tests never build a real `URLSessionHTTPClient`.
    static func status(
        sandboxes: [String],
        clientFor: (String) -> SandboxAPIClient
    ) async -> String {
        var rows: [StatusRow] = []
        for name in sandboxes {
            do {
                let response = try await clientFor(name).snapshot()
                rows.append(StatusRow.make(sandbox: name, response: response))
            } catch let failure as APIFailure {
                // One unreachable sandbox must not hide the others — `--all` is when you are
                // looking for the broken one.
                rows.append(StatusRow.unreachable(sandbox: name, failure: failure))
            } catch {
                rows.append(StatusRow.unreachable(sandbox: name, failure: .transport("\(error)")))
            }
        }

        var output = renderTable(rows)
        let problems = rows.compactMap { row in row.problem.map { "\(row.sandbox): \($0)" } }
        if !problems.isEmpty {
            output += "\n\n" + problems.joined(separator: "\n")
        }
        return output
    }

    static func doctor(sandbox: String, client: SandboxAPIClient) async -> String {
        let findings = await Doctor(client: client).diagnose()
        return findings.map { finding in
            let mark = finding.isProblem ? "!" : "."
            let step = finding.nextStep.map { "\n    → \($0)" } ?? ""
            return "[\(mark)] \(finding.headline)\(step)"
        }.joined(separator: "\n")
    }

    static func changes(
        sandbox: String,
        client: SandboxAPIClient,
        cursors: CursorStore,
        limit: Int,
        advance: Bool
    ) async throws -> String {
        let mark = try cursors.mark(for: sandbox)
        var currentLimit = limit
        var scan = ChangeCursor.scan(page: try await client.changes(limit: currentLimit), since: mark)

        // Widen and refetch while the page still has not reached back to the cursor.
        while scan.overflowed, let wider = ChangeCursor.nextLimit(after: currentLimit) {
            currentLimit = wider
            scan = ChangeCursor.scan(page: try await client.changes(limit: currentLimit), since: mark)
        }

        if advance, let newest = scan.newest {
            try cursors.setMark(newest, for: sandbox)
        }

        var lines: [String] = []
        if scan.overflowed {
            lines.append("! older events were not returned — the log moved by more than "
                       + "\(currentLimit) events since the last check, so some are missing here.")
            lines.append("")
        }

        if scan.newEvents.isEmpty {
            lines.append("nothing changed since the last check")
        } else {
            let formatter = ISO8601DateFormatter()
            for event in scan.newEvents {
                let flag: String
                switch event.severity {
                case .critical: flag = "!!"
                case .notable: flag = "!"
                case .informational: flag = " "
                }
                let detail = event.detail?["message"].map { " (\($0))" } ?? ""
                lines.append("\(flag) \(formatter.string(from: event.at))  \(event.type)  \(event.subject)\(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ArgumentParser wrappers

/// Builds a real client for a declared sandbox. The only place the CLI touches the network
/// and the keychain.
func liveClient(for name: String) throws -> SandboxAPIClient {
    let sandbox = try SandboxStore().sandbox(named: name)
    let token = try requireToken(KeychainTokenStore(), for: name)
    return SandboxAPIClient(baseURL: sandbox.url, token: token, http: URLSessionHTTPClient())
}

func resolveNames(_ name: String?, all: Bool) throws -> [String] {
    if all { return try SandboxStore().load().sandboxes.map(\.name) }
    guard let name else {
        throw SandboxWatchError("name a sandbox, or pass --all")
    }
    return [name]
}

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Snapshot age, apps, budget and collector state.")

    @Argument var name: String?
    @Flag(name: .long, help: "Every declared sandbox.") var all = false

    func run() async throws {
        let names = try resolveNames(name, all: all)
        // `liveClient` throws for an unknown sandbox or a missing token; resolve them all
        // first so the table is not half-printed before failing.
        var clients: [String: SandboxAPIClient] = [:]
        for name in names { clients[name] = try liveClient(for: name) }
        print(await ReadCommands.status(sandboxes: names) { clients[$0]! })
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Tell apart an outage, a refused token and a role that has not propagated.")

    @Argument var name: String

    func run() async throws {
        print(await ReadCommands.doctor(sandbox: name, client: try liveClient(for: name)))
    }
}

struct ChangesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "changes", abstract: "What changed since the last check.")

    @Argument var name: String
    @Option(help: "How many events to ask for (1–500).") var limit = SandboxAPI.defaultChangeLimit
    @Flag(name: .long, help: "Do not move the cursor — show the same events again next time.")
    var keepCursor = false

    func run() async throws {
        print(try await ReadCommands.changes(
            sandbox: name, client: try liveClient(for: name), cursors: CursorStore(),
            limit: limit, advance: !keepCursor))
    }
}
```

Then in `Sources/sbw/SBW.swift`, change the `subcommands` line to:

```swift
        subcommands: [SandboxCommand.self, StatusCommand.self, DoctorCommand.self, ChangesCommand.self]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS — the whole suite, 7 new tests here.

- [ ] **Step 5: Commit**

```bash
git add Sources/sbw Tests/SandboxWatchKitTests/ReadCommandsTests.swift
git commit -m "feat: sbw status, doctor and changes"
```

---

### Task 14: CI and documentation

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `README.md` — replace the "Status" block and the "Planned shape" table with what batch 1 actually ships
- Create: `docs/getting-started.md`

**Interfaces:**
- Consumes: everything above.
- Produces: no code.

- [ ] **Step 1: Write the failing check**

Run the whole suite and a release build, which is what CI will do:

```bash
swift test && swift build -c release
```

Expected at this point: PASS. If either fails, fix that before writing the workflow — a CI file that encodes a broken command is worse than none.

- [ ] **Step 2: Write the workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      # Printed first on purpose: local development is on Swift 6.4 / macOS 27 while this
      # runner ships an older toolchain. Tools-version 5.9 should carry it — but when CI first
      # goes red, read this line before suspecting the code.
      - name: Show toolchain
        run: swift --version
      - name: Test
        run: swift test
      - name: Build release
        run: swift build -c release
```

- [ ] **Step 3: Write `docs/getting-started.md`**

```markdown
# Getting started

## Build

```bash
swift build -c release
ln -s "$PWD/.build/release/sbw" /usr/local/bin/sbw
```

## Declare a sandbox

```bash
sbw sandbox add dev --url https://<app>.azurewebsites.net
# the token is read from stdin — paste the SANDBOX_TOKEN app setting
```

The URL and an optional note go to `~/.config/sbw/sandboxes.yaml`. The token goes to the
Keychain, under the service `fr.lauriat.sandboxwatch`. Nothing secret is written to disk in
readable form.

## Look

```bash
sbw status --all        # age, apps, budget, which sections collected
sbw doctor dev          # why a sandbox is not answering the way you expect
sbw changes dev         # what changed since the last time you ran this
```

## Reading `doctor`

| What it says | What it means |
|---|---|
| the app could not be reached | the web app is down, or the URL is wrong |
| the token was refused | the Keychain holds the wrong token |
| has not completed a collection yet | the app is up and working — wait, do not redeploy |
| these sections did not collect | the Reader role is missing **or was granted recently**: role membership is cached, and Microsoft documents up to 24 hours before it takes effect |
| the snapshot is N minutes old | the collector has stalled; what you see is old |

## Reading `changes`

Events are newest first. `!!` marks a collector losing or regaining access — the incident this
whole project exists for. `!` marks role, lock and budget changes.

Each run moves a cursor, so the next run shows only what is new. `--keep-cursor` looks without
moving it.

If a line says *older events were not returned*, more happened than the server would return in
one page: some events are missing from the output. It is a signal, not an error — the
alternative would be losing them silently.
```

- [ ] **Step 4: Update the README**

Replace the `> **Status: design approved…**` block with:

```markdown
> **Status: batch 1 shipped** — `SandboxWatchKit` and a read-only `sbw` CLI.
> See [`docs/getting-started.md`](docs/getting-started.md).
```

And mark the batch table's first row as done by prefixing it with `✅ `.

- [ ] **Step 5: Commit**

```bash
git add .github README.md docs/getting-started.md
git commit -m "ci: run swift test and a release build; document batch 1"
```

Then push the branch and open the pull request:

```bash
git push -u origin feat/batch-1-kit
gh pr create --base main --title "Batch 1: kit and read-only CLI" --fill
```

The remote is `https://github.com/vincentlauriat/sandboxwatch` (public, settled 2026-09-16).
Never push to `main` directly. Do not merge the PR without Vincent's review.

---

## Self-review notes

**Spec coverage.** §1 repository shape → Task 1 and Task 14. §2 inventory and secrets → Tasks 2, 3, 12. §3 seams → Tasks 3, 4; the unbreakable section rule → Task 5. §4 reading → Tasks 10, 11, 13. §5 cursor → Tasks 8, 9, 13. §6 `az` → **batch 3, deliberately absent**. §7 surfaces → batches 2 and 4. §8 errors as values → `APIFailure` (Task 6), `Doctor.Finding` (Task 10), `Section` (Task 5). §9 testing → the required cases map to `SectionTests`, `DoctorTests`, `ChangeCursorTests`, `SandboxAPIContractTests`; the two `az` cases belong to batch 3.

**Ordering.** Every task compiles against only the tasks before it. `SandboxAPIClient.changes(limit:)` is the one method that spans two tasks, and it is added in Task 8 — the task that defines its return type — rather than declared early in Task 7.

**Deliberately deferred to batch 2:** `sbw watch`, transition detection, notifications. **To batch 3:** `POST /api/v1/refresh`, `ProcessRunner`, `AzRunner`, `ActionJournal`. **To batch 4:** the control center window and `Scripts/release.sh`.
