# Batch A1 — Transition detection and `sbw watch`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notice that a sandbox's link changed state — became unreachable, refused the token, went stale, lost a section — and report it once, without crying wolf.

**Architecture:** `Doctor` already produces the verdicts. This adds the memory `Doctor` deliberately lacks: a `kind` for each finding so two readings can be compared, a pure decision function that turns two observations into a transition or silence, a per-sandbox store beside the change cursors, and `sbw watch` to run the loop. The macOS app of batch A2 reuses every one of these; nothing here is CLI-specific.

**Tech Stack:** Swift 5.9 tools version, SwiftPM, XCTest, ArgumentParser. No new dependency.

**Spec:** `docs/superpowers/specs/2026-09-17-supervision-dispositif-design.md` (section 6)

## Global Constraints

- **No new package dependency.** `Package.swift` keeps ArgumentParser and Yams, nothing else.
- **`swift test` touches no network, no Keychain, no `az`.** Every side effect goes through an existing protocol; the decision logic is a pure function taking values.
- **A denied section never renders as empty data.** `Section.fold` still forces both branches.
- **The CLI and the app say the same thing about the same state.** Every decision lives in `SandboxWatchKit`; `Sources/sbw` only parses arguments and prints.
- **Verify against the live sandbox before declaring done.** `swift test` green is necessary and not sufficient — batch 1 shipped 99 green tests over a client that had never decoded a real snapshot.

---

### Task 1: A finding's kind

**Files:**
- Modify: `Sources/SandboxWatchKit/Doctor.swift` — add `Kind` and `kind` inside `Doctor.Finding`
- Test: `Tests/SandboxWatchKitTests/DoctorTests.swift` (append)

**Interfaces:**
- Consumes: the existing `Doctor.Finding`.
- Produces: `Doctor.Finding.Kind` — `unreachable`, `unauthorised`, `notCollectedYet`, `serverProblem`, `stale`, `sectionsUnavailable`, `healthy`; `Equatable`, `Hashable`, `CaseIterable`, `Codable`, `String`-backed. And `Doctor.Finding.kind: Kind`.

Without this, transitions cannot be compared: `.stale(ageSeconds:)` and `.healthy(ageSeconds:)` carry a number that changes at every reading, so comparing `[Finding]` with `Equatable` would report a transition every five minutes forever.

- [ ] **Step 1: Write the failing test**

Append to `Tests/SandboxWatchKitTests/DoctorTests.swift`:

```swift
    func testTwoHealthyReadingsShareOneKindDespiteDifferentAges() async {
        // The trap this type exists for. `.healthy(ageSeconds:)` carries a number that changes
        // at every reading, so comparing findings by Equatable would report a transition every
        // five minutes, forever.
        let first = Doctor.Finding.healthy(ageSeconds: 60)
        let second = Doctor.Finding.healthy(ageSeconds: 305)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.kind, second.kind)
        XCTAssertEqual(Set([first].map(\.kind)), Set([second].map(\.kind)))
    }

    func testEveryFindingHasADistinctKind() {
        let findings: [Doctor.Finding] = [
            .unreachable("x"), .unauthorised, .notCollectedYet, .serverProblem("x"),
            .stale(ageSeconds: 1), .sectionsUnavailable(["governance"]), .healthy(ageSeconds: 1),
        ]
        XCTAssertEqual(Set(findings.map(\.kind)).count, findings.count)
        XCTAssertEqual(Set(findings.map(\.kind)), Set(Doctor.Finding.Kind.allCases))
    }

    func testStaleWithDeniedSectionsIsATwoKindObservation() async {
        // A transition is a change of the SET, not of "the worst": going from {stale} to
        // {stale, sectionsUnavailable} is a transition even though the worst did not change.
        let findings: [Doctor.Finding] = [.stale(ageSeconds: 4000), .sectionsUnavailable(["governance"])]
        XCTAssertEqual(Set(findings.map(\.kind)), [.stale, .sectionsUnavailable])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DoctorTests`
Expected: FAIL — `value of type 'Doctor.Finding' has no member 'kind'`

- [ ] **Step 3: Write minimal implementation**

In `Sources/SandboxWatchKit/Doctor.swift`, inside `public enum Finding`, after the cases:

```swift
        /// A finding stripped of its payload, so two observations can be compared.
        ///
        /// `.stale` and `.healthy` carry an age that changes at every reading. Comparing
        /// findings themselves would therefore report a transition on every poll, forever.
        public enum Kind: String, Equatable, Hashable, CaseIterable, Codable {
            case unreachable, unauthorised, notCollectedYet, serverProblem
            case stale, sectionsUnavailable, healthy
        }

        public var kind: Kind {
            switch self {
            case .unreachable:         return .unreachable
            case .unauthorised:        return .unauthorised
            case .notCollectedYet:     return .notCollectedYet
            case .serverProblem:       return .serverProblem
            case .stale:               return .stale
            case .sectionsUnavailable: return .sectionsUnavailable
            case .healthy:             return .healthy
            }
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DoctorTests`
Expected: PASS, and every pre-existing `DoctorTests` case still green.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/Doctor.swift Tests/SandboxWatchKitTests/DoctorTests.swift
git commit -m "feat: give a doctor finding a kind, so two readings can be compared"
```

---

### Task 2: The transition decision

**Files:**
- Create: `Sources/SandboxWatchKit/LiaisonTransition.swift`
- Test: `Tests/SandboxWatchKitTests/LiaisonTransitionTests.swift`

**Interfaces:**
- Consumes: `Doctor.Finding.Kind` from Task 1.
- Produces:
  - `LiaisonState` — `Codable`, `Equatable`; `confirmed: Set<Doctor.Finding.Kind>`, `candidate: Set<Doctor.Finding.Kind>?`, `observedAt: Date`
  - `LiaisonTransition` — `Equatable`; `from: Set<Doctor.Finding.Kind>`, `to: Set<Doctor.Finding.Kind>`
  - `LiaisonDecision` — `Equatable`; `state: LiaisonState`, `transition: LiaisonTransition?`
  - `LiaisonMonitor.decide(observed:previous:at:reestablishAfter:) -> LiaisonDecision`, `reestablishAfter` defaulting to `900`

A pure function over values, the same shape as `ChangeCursor.scan`: no clock, no I/O, no client. It is where every safeguard of spec section 6.5 lives.

- [ ] **Step 1: Write the failing test**

Create `Tests/SandboxWatchKitTests/LiaisonTransitionTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class LiaisonTransitionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_789_000_000)
    private func later(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private let healthy: Set<Doctor.Finding.Kind> = [.healthy]
    private let down: Set<Doctor.Finding.Kind> = [.unreachable]

    func testFirstObservationEstablishesAndAnnouncesNothing() {
        // Same rule as the change cursor's first run: declaring a sandbox must not replay its
        // history as an alarm.
        let decision = LiaisonMonitor.decide(observed: down, previous: nil, at: t0)

        XCTAssertNil(decision.transition)
        XCTAssertEqual(decision.state.confirmed, down)
        XCTAssertNil(decision.state.candidate)
    }

    func testAnUnchangedObservationIsSilent() {
        let first = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let second = LiaisonMonitor.decide(observed: healthy, previous: first, at: later(300))

        XCTAssertNil(second.transition)
        XCTAssertEqual(second.state.confirmed, healthy)
    }

    func testOneFailedReadingChangesNothing() {
        // A Mac that sleeps, changes Wi-Fi or switches to tethering manufactures spurious
        // "unreachable". One reading is not evidence.
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let second = LiaisonMonitor.decide(observed: down, previous: established, at: later(300))

        XCTAssertNil(second.transition)
        XCTAssertEqual(second.state.confirmed, healthy)
        XCTAssertEqual(second.state.candidate, down)
    }

    func testTwoConsecutiveReadingsChangeTheState() {
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let pending = LiaisonMonitor.decide(observed: down, previous: established, at: later(300)).state
        let third = LiaisonMonitor.decide(observed: down, previous: pending, at: later(600))

        XCTAssertEqual(third.transition, LiaisonTransition(from: healthy, to: down))
        XCTAssertEqual(third.state.confirmed, down)
        XCTAssertNil(third.state.candidate)
    }

    func testRecoveryAlsoNeedsTwoReadings() {
        // Both directions. Knowing it is over is worth as much as knowing it began — and a
        // single lucky reading is no more evidence than a single failed one.
        var state = LiaisonMonitor.decide(observed: down, previous: nil, at: t0).state
        state = LiaisonMonitor.decide(observed: healthy, previous: state, at: later(300)).state
        XCTAssertEqual(state.confirmed, down)

        let recovered = LiaisonMonitor.decide(observed: healthy, previous: state, at: later(600))
        XCTAssertEqual(recovered.transition, LiaisonTransition(from: down, to: healthy))
    }

    func testAThirdDifferentObservationReplacesTheCandidate() {
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let pending = LiaisonMonitor.decide(observed: down, previous: established, at: later(300)).state
        let other = LiaisonMonitor.decide(
            observed: [.unauthorised], previous: pending, at: later(600))

        XCTAssertNil(other.transition)
        XCTAssertEqual(other.state.confirmed, healthy)
        XCTAssertEqual(other.state.candidate, [.unauthorised])
    }

    func testALongGapReestablishesSilently() {
        // The lid was shut all weekend. The first reading on waking describes a state nobody
        // was watching, so it establishes rather than announces.
        let established = LiaisonMonitor.decide(observed: healthy, previous: nil, at: t0).state
        let afterSleep = LiaisonMonitor.decide(observed: down, previous: established, at: later(3600))

        XCTAssertNil(afterSleep.transition)
        XCTAssertEqual(afterSleep.state.confirmed, down)
        XCTAssertNil(afterSleep.state.candidate)
    }

    func testAChangeOfSetIsATransitionEvenWhenTheWorstIsUnchanged() {
        // Doctor refuses to reduce its diagnosis to one verdict, so a transition is defined on
        // the set: {stale} -> {stale, sectionsUnavailable} is a real change.
        let one: Set<Doctor.Finding.Kind> = [.stale]
        let two: Set<Doctor.Finding.Kind> = [.stale, .sectionsUnavailable]

        var state = LiaisonMonitor.decide(observed: one, previous: nil, at: t0).state
        state = LiaisonMonitor.decide(observed: two, previous: state, at: later(300)).state
        let decision = LiaisonMonitor.decide(observed: two, previous: state, at: later(600))

        XCTAssertEqual(decision.transition, LiaisonTransition(from: one, to: two))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LiaisonTransitionTests`
Expected: FAIL — `cannot find 'LiaisonMonitor' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SandboxWatchKit/LiaisonTransition.swift`:

```swift
import Foundation

/// What the last observations of one sandbox's link looked like.
///
/// `confirmed` is what has been announced. `candidate` is an observation seen once and not yet
/// believed — a Mac that sleeps, changes network or switches to tethering manufactures spurious
/// failures, and a repeated false alarm is exactly what makes an operator ignore the icon.
public struct LiaisonState: Codable, Equatable {
    public let confirmed: Set<Doctor.Finding.Kind>
    public let candidate: Set<Doctor.Finding.Kind>?
    public let observedAt: Date

    public init(confirmed: Set<Doctor.Finding.Kind>, candidate: Set<Doctor.Finding.Kind>?, observedAt: Date) {
        self.confirmed = confirmed
        self.candidate = candidate
        self.observedAt = observedAt
    }
}

public struct LiaisonTransition: Equatable {
    public let from: Set<Doctor.Finding.Kind>
    public let to: Set<Doctor.Finding.Kind>

    public init(from: Set<Doctor.Finding.Kind>, to: Set<Doctor.Finding.Kind>) {
        self.from = from
        self.to = to
    }
}

public struct LiaisonDecision: Equatable {
    public let state: LiaisonState
    public let transition: LiaisonTransition?
}

public enum LiaisonMonitor {
    /// Turns one observation into a transition, or into silence.
    ///
    /// Three safeguards, all of them here rather than in a caller:
    ///
    /// - the first observation establishes, it does not announce;
    /// - a change needs two consecutive readings, in both directions;
    /// - an observation older than `reestablishAfter` is treated as a fresh start, because
    ///   nobody was watching in between.
    public static func decide(
        observed: Set<Doctor.Finding.Kind>,
        previous: LiaisonState?,
        at now: Date,
        reestablishAfter: TimeInterval = 900
    ) -> LiaisonDecision {
        guard let previous, now.timeIntervalSince(previous.observedAt) <= reestablishAfter else {
            return LiaisonDecision(
                state: LiaisonState(confirmed: observed, candidate: nil, observedAt: now),
                transition: nil)
        }

        if observed == previous.confirmed {
            return LiaisonDecision(
                state: LiaisonState(confirmed: observed, candidate: nil, observedAt: now),
                transition: nil)
        }

        if observed == previous.candidate {
            return LiaisonDecision(
                state: LiaisonState(confirmed: observed, candidate: nil, observedAt: now),
                transition: LiaisonTransition(from: previous.confirmed, to: observed))
        }

        return LiaisonDecision(
            state: LiaisonState(confirmed: previous.confirmed, candidate: observed, observedAt: now),
            transition: nil)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LiaisonTransitionTests`
Expected: PASS — the 8 cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/LiaisonTransition.swift Tests/SandboxWatchKitTests/LiaisonTransitionTests.swift
git commit -m "feat: decide when a link has really changed state"
```

---

### Task 3: Remembering it between runs

**Files:**
- Create: `Sources/SandboxWatchKit/LiaisonStore.swift`
- Test: `Tests/SandboxWatchKitTests/LiaisonStoreTests.swift`

**Interfaces:**
- Consumes: `LiaisonState` from Task 2.
- Produces: `LiaisonStore(directory:)` with `defaultDirectory = "~/.config/sbw/liaison"`, `state(for: String) throws -> LiaisonState?`, `setState(_:for:) throws`

Deliberately the same shape as `CursorStore`, including its path guard: a sandbox name comes from the command line, and letting it act as a path would write outside the directory. `sbw watch` and the app share one memory of what has already been announced, exactly as they share one cursor.

- [ ] **Step 1: Write the failing test**

Create `Tests/SandboxWatchKitTests/LiaisonStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LiaisonStoreTests`
Expected: FAIL — `cannot find 'LiaisonStore' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SandboxWatchKit/LiaisonStore.swift`:

```swift
import Foundation

/// Where each sandbox's last-observed link state lives, so `sbw watch` and the app agree on
/// what has already been announced — the same arrangement as `CursorStore`.
public final class LiaisonStore {
    public static let defaultDirectory = "~/.config/sbw/liaison"
    private let directory: String

    public init(directory: String = LiaisonStore.defaultDirectory) {
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

    /// A missing or unreadable file is "no state": a fresh start, never a crash that blocks
    /// every command.
    public func state(for sandbox: String) throws -> LiaisonState? {
        let path = try path(for: sandbox)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? SandboxJSON.decoder.decode(LiaisonState.self, from: data)
    }

    public func setState(_ state: LiaisonState, for sandbox: String) throws {
        let path = try path(for: sandbox)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        try encoder.encode(state).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LiaisonStoreTests`
Expected: PASS — the 5 cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/LiaisonStore.swift Tests/SandboxWatchKitTests/LiaisonStoreTests.swift
git commit -m "feat: remember a sandbox's link state between runs"
```

---

### Task 4: `sbw watch`

**Files:**
- Create: `Sources/sbw/WatchCommand.swift`
- Modify: `Sources/sbw/SBW.swift` — add `WatchCommand.self` to `subcommands`
- Test: `Tests/SandboxWatchKitTests/WatchCommandTests.swift`

**Interfaces:**
- Consumes: `LiaisonMonitor.decide`, `LiaisonStore`, `Doctor`, `SandboxAPIClient`.
- Produces: `WatchCommands.pollOnce(sandbox:client:liaison:at:) async throws -> String?` — the rendered line for a transition, or `nil` when there is nothing to say.

One poll is a function; the loop is the command's five lines. That keeps the whole decision testable with no timing, and gives batch A2 exactly the call its menu bar needs.

- [ ] **Step 1: Write the failing test**

Create `Tests/SandboxWatchKitTests/WatchCommandTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit
@testable import sbw

final class WatchCommandTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!
    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "sbw-watch-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "t", http: mock)
    }

    private let healthyJSON = """
    {
      "collectedAt": "2026-09-16T08:00:00.000Z",
      "ageSeconds": 60,
      "snapshot": {
        "identity": { "available": true, "subscriptionId": "sub-1", "resourceGroup": "rg" },
        "resources": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "plans": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "apps": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "budget": { "status": "ok", "data": [], "message": null, "durationMs": 1 },
        "governance": { "status": "ok", "data": {}, "message": null, "durationMs": 1 },
        "probes": { "status": "ok", "data": [], "message": null, "durationMs": 1 }
      }
    }
    """

    func testFirstPollSaysNothing() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)

        let line = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: LiaisonStore(directory: directory),
            at: Date(timeIntervalSince1970: 1_789_000_000))

        XCTAssertNil(line)
    }

    func testTwoFailedPollsAnnounceTheTransitionOnce() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        let store = LiaisonStore(directory: directory)
        let t0 = Date(timeIntervalSince1970: 1_789_000_000)

        _ = try await WatchCommands.pollOnce(sandbox: "dev", client: client(mock), liaison: store, at: t0)

        mock.stub(path: "/api/v1/snapshot", status: 401, json: "{}")
        let first = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: store, at: t0.addingTimeInterval(300))
        let second = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: store, at: t0.addingTimeInterval(600))
        let third = try await WatchCommands.pollOnce(
            sandbox: "dev", client: client(mock), liaison: store, at: t0.addingTimeInterval(900))

        XCTAssertNil(first, "one reading is not evidence")
        XCTAssertNotNil(second)
        XCTAssertTrue(second!.contains("token"), "the line names what changed: \(second!)")
        XCTAssertNil(third, "a steady state is not announced again")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WatchCommandTests`
Expected: FAIL — `cannot find 'WatchCommands' in scope`

- [ ] **Step 3: Write minimal implementation**

Create `Sources/sbw/WatchCommand.swift`:

```swift
import ArgumentParser
import Foundation
import SandboxWatchKit

enum WatchCommands {
    /// One poll. Returns the line to show, or `nil` when nothing changed.
    ///
    /// The loop lives in the command; this is the whole decision, so it is testable with no
    /// timing — and it is exactly the call the menu bar app needs.
    static func pollOnce(
        sandbox: String,
        client: SandboxAPIClient,
        liaison: LiaisonStore,
        at now: Date = Date()
    ) async throws -> String? {
        let findings = await Doctor(client: client).diagnose()
        let observed = Set(findings.map(\.kind))

        let decision = LiaisonMonitor.decide(
            observed: observed, previous: try liaison.state(for: sandbox), at: now)
        try liaison.setState(decision.state, for: sandbox)

        guard decision.transition != nil else { return nil }

        let formatter = ISO8601DateFormatter()
        let headlines = findings.map(\.headline).joined(separator: "; ")
        return "!! \(formatter.string(from: now))  \(sandbox)  \(headlines)"
    }
}

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Poll a sandbox and report only when its state changes.")

    @Argument var name: String
    @Option(help: "Seconds between polls.") var interval: Int = 300
    @Flag(name: .long, help: "Poll once and exit.") var once = false

    func run() async throws {
        let client = try liveClient(for: name)
        let liaison = LiaisonStore()

        repeat {
            if let line = try await WatchCommands.pollOnce(
                sandbox: name, client: client, liaison: liaison) {
                print(line)
            }
            if once { return }
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        } while true
    }
}
```

In `Sources/sbw/SBW.swift`, extend the subcommand list:

```swift
        subcommands: [SandboxCommand.self, StatusCommand.self, DoctorCommand.self,
                      ChangesCommand.self, WatchCommand.self]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS — the whole suite, 102 plus the cases added in Tasks 1–4.

- [ ] **Step 5: Commit**

```bash
git add Sources/sbw/WatchCommand.swift Sources/sbw/SBW.swift Tests/SandboxWatchKitTests/WatchCommandTests.swift
git commit -m "feat: add sbw watch, which speaks only on a transition"
```

---

## Deliberately not in this plan

**`sbw watch` reports link transitions, not change events.** Spec section 6.1 names two sources,
and this plan implements one. That is not an omission by accident:

- Every `critical` event is `collector_access_lost` or `collector_access_restored`, which means a
  section became unavailable or came back — and that already moves the observed set of kinds through
  `sectionsUnavailable`. The founding incident is therefore caught by the liaison half alone.
- `notable` and `informational` events do not notify, by the policy in spec 6.4. Surfacing them in a
  watch loop would add noise and no alarm.
- `sbw changes` already reports the event stream, with its own cursor. Having `watch` move that same
  cursor would make a manual `sbw changes` show nothing, which is a worse bug than the gap.

What the event stream adds is **detail** — which collector, and the message Azure returned. That
belongs to batch A2, where a notification body has room for it and the cursor question has to be
answered anyway.

**Also not here:** per-sandbox notification rules, quiet hours, grouping, and `--all` for `watch`.
One sandbox per invocation until the app needs more.

## Exit gate for batch A1

Batch A2 — the menu bar app — must not start before all of these hold:

- [ ] `swift test` green, and `swift build -c release` clean.
- [ ] **Run against the live sandbox**, which the suite structurally cannot cover:
  ```bash
  sbw watch dev --once        # first run: prints nothing, writes the state file
  cat ~/.config/sbw/liaison/dev.json
  sbw watch dev --once        # steady state: still prints nothing
  ```
- [ ] Force a real transition and see it announced exactly once. **A sandbox that is broken from
      its first poll produces no transition** — `unreachable` simply becomes its baseline, and
      three silences are the correct answer. The state has to start healthy and then break:
  ```bash
  <token> | sbw sandbox add probe --url https://sandboxmgr.azurewebsites.net
  sbw watch probe --once          # silent: establishes a healthy baseline
  sbw sandbox remove probe
  echo x | sbw sandbox add probe --url https://does-not-exist.azurewebsites.net
  sbw watch probe --once          # silent: one reading is not evidence
  sbw watch probe --once          # SPEAKS
  sbw watch probe --once          # silent: a steady state is not re-announced
  sbw sandbox remove probe && rm ~/.config/sbw/liaison/probe.json
  ```
  Removing a sandbox leaves its liaison state on disk, which is what makes this work.
- [ ] Read the announced line. It goes into a notification body in batch A2, so an NSError dump
      is a defect, not cosmetics.
- [ ] `sbw watch dev --once` and `sbw doctor dev` describe the same state in the same words —
      the rule that the CLI and the app never diverge starts here.

The third item is the one worth insisting on: it is the only check that exercises the debounce,
and a debounce that never fires is indistinguishable from one that is broken.
