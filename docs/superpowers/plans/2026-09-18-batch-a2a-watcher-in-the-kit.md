# Batch A2a — The watcher moves into the Kit, and learns about events

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one poll a value the menu bar app can consume, and give it the change events batch A1 left out.

**Architecture:** A1 put `pollOnce` in `Sources/sbw`, which is an executable target — an Xcode app target can link the `SandboxWatchKit` library product but cannot import an executable. So the call A1 described as "exactly what the menu bar needs" is at an address the menu bar cannot reach. This moves it, then turns its `String?` into a report value carrying the findings, the transition and the new change events, leaving rendering to each surface.

**Tech Stack:** Swift, SwiftPM, XCTest. No new dependency.

**Spec:** `docs/superpowers/specs/2026-09-17-supervision-dispositif-design.md` (sections 3.4, 6.1, 6.4, and the 2026-09-18 amendment in 6.3)

**Why this is its own plan:** everything here is provable with `swift test` and `sbw` against the live sandbox. Batch A2b — the Xcode project, the menu bar, notifications, i18n and signing — can only be gated by Vincent launching the app, and mixing the two would mean writing test steps nobody can execute.

## Global Constraints

- **Every decision lives in `SandboxWatchKit`.** `Sources/sbw` parses arguments and renders text. This is spec section 3.4, and the defect this plan opens with is what happens when it slips.
- **No new package dependency**; `Package.swift` keeps ArgumentParser and Yams.
- **`swift test` touches no network, no Keychain, no `az`.**
- **Each surface keeps its own memory** (spec 6.3, amended 2026-09-18). `CursorStore` and `LiaisonStore` both take a `directory`; the Kit never picks one. `sbw watch` uses `cursors-watch` and `liaison`; the app will use `cursors-app` and `liaison-app`.
- **A denied section never renders as empty data.**
- **Verify against the live sandbox before declaring done.**

---

### Task 1: Move the poll into the Kit, unchanged

**Files:**
- Create: `Sources/SandboxWatchKit/SandboxWatcher.swift`
- Modify: `Sources/sbw/WatchCommand.swift` — delete `enum WatchCommands`, keep `WatchCommand`
- Modify: `Tests/SandboxWatchKitTests/WatchCommandTests.swift` — the import and the call site only

**Interfaces:**
- Consumes: `Doctor`, `LiaisonMonitor`, `LiaisonStore`, `SandboxAPIClient`.
- Produces: `SandboxWatcher.pollOnce(sandbox:client:liaison:at:) async throws -> String?` — the same signature, now on the library.

A pure move. **If any assertion in `WatchCommandTests` has to change, the move was not pure and something else is wrong** — stop and find out what.

- [ ] **Step 1: Move the type**

Create `Sources/SandboxWatchKit/SandboxWatcher.swift` with the body of `WatchCommands` verbatim, renamed:

```swift
import Foundation

/// One poll of one sandbox.
///
/// This lives in the Kit rather than beside the command because an Xcode app target can link the
/// `SandboxWatchKit` library product but cannot import the `sbw` executable target. Batch A1 put
/// it in the executable and described it as the call the menu bar needs; the shape was right and
/// the address was not.
public enum SandboxWatcher {
    /// Returns the line to show, or `nil` when nothing changed.
    public static func pollOnce(
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
```

In `Sources/sbw/WatchCommand.swift`, delete `enum WatchCommands` entirely and point the command at the Kit:

```swift
            if let line = try await SandboxWatcher.pollOnce(
                sandbox: name, client: client, liaison: liaison) {
```

- [ ] **Step 2: Re-point the tests, assertions untouched**

In `Tests/SandboxWatchKitTests/WatchCommandTests.swift`, replace every `WatchCommands.pollOnce` with `SandboxWatcher.pollOnce`. Change nothing else — not the fixtures, not the expectations.

- [ ] **Step 3: Run the suite**

Run: `swift test`
Expected: PASS, same count as before the move. `@testable import sbw` can stay: the file still exercises the command's wiring.

- [ ] **Step 4: Prove the move was the point**

Run: `grep -rn "pollOnce" Sources/`
Expected: one definition, in `Sources/SandboxWatchKit/SandboxWatcher.swift`, and one call site in `Sources/sbw/WatchCommand.swift`. A second definition means the old one was copied rather than moved.

- [ ] **Step 5: Commit**

```bash
git add Sources/SandboxWatchKit/SandboxWatcher.swift Sources/sbw/WatchCommand.swift Tests/SandboxWatchKitTests/WatchCommandTests.swift
git commit -m "refactor: move the poll into the Kit, where the app can reach it"
```

---

### Task 2: A report instead of a line, carrying the new events

**Files:**
- Modify: `Sources/SandboxWatchKit/SandboxWatcher.swift`
- Modify: `Sources/sbw/WatchCommand.swift` — render the report, add `--cursor-directory` default
- Modify: `Tests/SandboxWatchKitTests/WatchCommandTests.swift`
- Test: `Tests/SandboxWatchKitTests/SandboxWatcherTests.swift` (new)

**Interfaces:**
- Consumes: `ChangeCursor.scan`, `CursorStore`, `ChangeEvent.severity` (published by the server since batch 0).
- Produces:
  - `SandboxWatchReport` — `findings: [Doctor.Finding]`, `transition: LiaisonTransition?`, `newEvents: [ChangeEvent]`, `overflowed: Bool`; `var isSilent: Bool` true when there is nothing to announce.
  - `SandboxWatcher.poll(sandbox:client:liaison:cursors:at:limit:) async throws -> SandboxWatchReport`
  - `SandboxWatcher.render(_ report: SandboxWatchReport, sandbox:at:) -> String?` — the CLI line, `nil` when silent.

The report carries **every** new event, not only the critical ones. Filtering is the caller's policy: the CLI prints them with the markers `sbw changes` uses, and the app will notify on `critical` and badge on `notable` (spec 6.4). A Kit that pre-filters would force that policy on both.

`cursors` is supplied by the caller and never defaulted inside the Kit — `sbw watch` passes `cursors-watch`, the app will pass `cursors-app`, and `sbw changes` keeps `cursors` untouched.

- [ ] **Step 1: Write the failing test**

Create `Tests/SandboxWatchKitTests/SandboxWatcherTests.swift`:

```swift
import XCTest
@testable import SandboxWatchKit

final class SandboxWatcherTests: XCTestCase {
    private let base = URL(string: "https://dev.azurewebsites.net")!
    private let t0 = Date(timeIntervalSince1970: 1_789_000_000)
    private var directory: String!

    override func setUp() {
        super.setUp()
        directory = NSTemporaryDirectory() + "sbw-watcher-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    private func client(_ mock: MockHTTPClient) -> SandboxAPIClient {
        SandboxAPIClient(baseURL: base, token: "t", http: mock)
    }

    private var liaison: LiaisonStore { LiaisonStore(directory: directory + "/liaison") }
    private var cursors: CursorStore { CursorStore(directory: directory + "/cursors") }

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

    private func changesJSON(_ events: String) -> String {
        #"{"limit": 50, "events": [\#(events)]}"#
    }

    private let criticalEvent = """
    { "at": "2026-09-16T09:18:01.000Z", "type": "collector_access_lost", "subject": "governance",
      "detail": { "message": "AuthorizationFailed" }, "collector": "governance",
      "severity": "critical" }
    """

    func testAHealthySandboxWithNoNewEventsIsSilent() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(""))

        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        XCTAssertTrue(report.isSilent)
        XCTAssertNil(SandboxWatcher.render(report, sandbox: "dev", at: t0))
    }

    func testTheFirstPollEstablishesTheCursorAndAnnouncesNothing() async throws {
        // The change cursor's first-run rule, unchanged: declaring a sandbox must not replay its
        // history as an alarm.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(criticalEvent))

        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        XCTAssertTrue(report.newEvents.isEmpty)
        XCTAssertTrue(report.isSilent)
    }

    func testAnEventArrivingAfterTheCursorIsReported() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(""))

        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(criticalEvent))
        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(300))

        XCTAssertEqual(report.newEvents.map(\.type), ["collector_access_lost"])
        XCTAssertEqual(report.newEvents.first?.severity, .critical)
        XCTAssertFalse(report.isSilent)

        let line = SandboxWatcher.render(report, sandbox: "dev", at: t0.addingTimeInterval(300))
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("!!"), "a critical event is marked: \(line!)")
        XCTAssertTrue(line!.contains("AuthorizationFailed"), "the detail is shown: \(line!)")
    }

    func testTheReportCarriesEveryNewEventAndLetsTheCallerFilter() async throws {
        // The Kit must not pre-filter: the CLI prints everything with markers, and the app will
        // notify on critical while only badging notable.
        let notable = """
        { "at": "2026-09-16T10:00:00.000Z", "type": "role_added", "subject": "p",
          "detail": {}, "collector": "governance", "severity": "notable" }
        """
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(""))
        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON("\(criticalEvent), \(notable)"))
        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(300))

        XCTAssertEqual(report.newEvents.count, 2)
        XCTAssertEqual(report.newEvents.filter { $0.severity == .critical }.count, 1)
        XCTAssertEqual(report.newEvents.filter { $0.severity == .notable }.count, 1)
    }

    func testAnUnreachableSandboxStillReportsItsTransitionWithoutEvents() async throws {
        // `/changes` cannot answer when the app is down. That must not swallow the transition,
        // which is the whole point of polling.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(""))
        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors, at: t0)

        mock.fail(path: "/api/v1", error: SandboxWatchError("could not connect"))
        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(300))
        let report = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: cursors,
            at: t0.addingTimeInterval(600))

        XCTAssertNotNil(report.transition)
        XCTAssertTrue(report.newEvents.isEmpty)
        XCTAssertFalse(report.isSilent)
    }

    func testTheCursorIsTheCallersAndNeverTheOneSbwChangesUses() async throws {
        // Spec 6.3, amended: three readers, three notions of "since I last looked". A watch that
        // moved the `sbw changes` cursor would make a manual run show nothing.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/v1/snapshot", status: 200, json: healthyJSON)
        mock.stub(path: "/api/v1/changes", status: 200, json: changesJSON(criticalEvent))

        let watch = CursorStore(directory: directory + "/cursors-watch")
        let manual = CursorStore(directory: directory + "/cursors")

        _ = try await SandboxWatcher.poll(
            sandbox: "dev", client: client(mock), liaison: liaison, cursors: watch, at: t0)

        XCTAssertNotNil(try watch.mark(for: "dev"))
        XCTAssertNil(try manual.mark(for: "dev"), "the manual cursor must not have moved")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SandboxWatcherTests`
Expected: FAIL — `type 'SandboxWatcher' has no member 'poll'`

- [ ] **Step 3: Write minimal implementation**

Replace the body of `Sources/SandboxWatchKit/SandboxWatcher.swift`:

```swift
import Foundation

/// What one poll of one sandbox found.
///
/// A value, not a rendered line: the CLI prints it, and the menu bar app turns it into an icon
/// and a notification. Every new event is carried, including the quiet ones — filtering is the
/// caller's policy, and a Kit that pre-filtered would impose one policy on both surfaces.
public struct SandboxWatchReport {
    public let findings: [Doctor.Finding]
    public let transition: LiaisonTransition?
    public let newEvents: [ChangeEvent]
    /// The change log moved by more than one page: some events are missing from `newEvents`.
    public let overflowed: Bool

    /// Nothing to announce. A steady state with no new events.
    public var isSilent: Bool { transition == nil && newEvents.isEmpty && !overflowed }
}

/// One poll of one sandbox.
///
/// This lives in the Kit rather than beside the command because an Xcode app target can link the
/// `SandboxWatchKit` library product but cannot import the `sbw` executable target. Batch A1 put
/// it in the executable and described it as the call the menu bar needs; the shape was right and
/// the address was not.
public enum SandboxWatcher {
    public static func poll(
        sandbox: String,
        client: SandboxAPIClient,
        liaison: LiaisonStore,
        cursors: CursorStore,
        at now: Date = Date(),
        limit: Int = SandboxAPI.defaultChangeLimit
    ) async throws -> SandboxWatchReport {
        let findings = await Doctor(client: client).diagnose()

        let decision = LiaisonMonitor.decide(
            observed: Set(findings.map(\.kind)),
            previous: try liaison.state(for: sandbox), at: now)
        try liaison.setState(decision.state, for: sandbox)

        // A sandbox that cannot be reached cannot serve its change log either. That must not
        // swallow the transition, which is the reason for polling in the first place.
        var newEvents: [ChangeEvent] = []
        var overflowed = false
        if let page = try? await client.changes(limit: limit) {
            let scan = ChangeCursor.scan(page: page, since: try cursors.mark(for: sandbox))
            newEvents = scan.newEvents
            overflowed = scan.overflowed
            if let newest = scan.newest { try cursors.setMark(newest, for: sandbox) }
        }

        return SandboxWatchReport(
            findings: findings, transition: decision.transition,
            newEvents: newEvents, overflowed: overflowed)
    }

    /// The CLI line, or `nil` when there is nothing to say. Markers match `sbw changes`, so both
    /// commands teach one vocabulary.
    public static func render(_ report: SandboxWatchReport, sandbox: String, at now: Date) -> String? {
        guard !report.isSilent else { return nil }
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []

        if report.overflowed {
            lines.append("!  \(sandbox)  older events were not returned — some are missing here")
        }
        if report.transition != nil {
            let headlines = report.findings.map(\.headline).joined(separator: "; ")
            lines.append("!! \(formatter.string(from: now))  \(sandbox)  \(headlines)")
        }
        for event in report.newEvents {
            let marker: String
            switch event.severity {
            case .critical: marker = "!!"
            case .notable: marker = "! "
            case .informational: marker = "  "
            }
            let detail = (event.detail?["message"]?.text).map { " (\($0))" } ?? ""
            lines.append("\(marker) \(formatter.string(from: event.at))  \(sandbox)  \(event.type)  \(event.subject)\(detail)")
        }
        return lines.joined(separator: "\n")
    }
}
```

In `Sources/sbw/WatchCommand.swift`, render the report and use the watch's own cursor directory:

```swift
    func run() async throws {
        let client = try liveClient(for: name)
        let liaison = LiaisonStore()
        // Its own cursor: moving the one `sbw changes` uses would make a manual run show
        // nothing. Spec 6.3, amended 2026-09-18.
        let cursors = CursorStore(directory: "~/.config/sbw/cursors-watch")

        repeat {
            let now = Date()
            let report = try await SandboxWatcher.poll(
                sandbox: name, client: client, liaison: liaison, cursors: cursors, at: now)
            if let line = SandboxWatcher.render(report, sandbox: name, at: now) {
                print(line)
            }
            if once { return }
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        } while true
    }
```

- [ ] **Step 4: Re-point `WatchCommandTests` and run everything**

`WatchCommandTests` calls `pollOnce`, which no longer exists. Rewrite its two cases against `poll` plus `render`, keeping their intent word for word: the first poll says nothing, and two failed polls announce once. Both need a `/api/v1/changes` stub added, since `poll` now asks for one.

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Prove the tests discriminate**

Two deliberate breakages, each reverted immediately:

```bash
# 1. Make `poll` pre-filter to critical only.
#    Expected: testTheReportCarriesEveryNewEventAndLetsTheCallerFilter fails.
# 2. Make `poll` return early when `/changes` fails, before the liaison decision.
#    Expected: testAnUnreachableSandboxStillReportsItsTransitionWithoutEvents fails.
```

A test that passes against the bug it names is not a test.

- [ ] **Step 6: Commit**

```bash
git add Sources/SandboxWatchKit/SandboxWatcher.swift Sources/sbw/WatchCommand.swift Tests/SandboxWatchKitTests/
git commit -m "feat: a poll reports its events, and each surface keeps its own cursor"
```

---

## Exit gate for batch A2a

- [x] `swift test` green (131, was 125), `swift build -c release` clean.
- [x] `grep -rn "pollOnce" Sources/ Tests/` returns nothing: the old entry point is gone, not shadowed.
- [x] Against the live sandbox, `sbw watch dev --once` twice in a row: the first established the
      watch cursor at `2026-09-18T02:35:32.957Z`, both were silent — the liaison state was already
      `healthy` from 2026-09-17, and a steady state says nothing.
- [x] `ls ~/.config/sbw/` shows `cursors`, `cursors-watch` and `liaison` as separate directories.
      After the two watches, `sbw changes dev --keep-cursor` still reported **20** events from its
      own cursor at `2026-09-16T09:08:02Z`, the four probe events the watch had just consumed
      included, and `cursors/dev.json` was byte-identical before and after.
- [x] Replaying the real 2026-09-16 incident through the watch cursor, the rendered line carries
      the full Azure message:
      `!! 2026-09-16T09:18:01Z  dev  collector_access_lost  governance (The client '…' does not
      have authorization to perform action 'Microsoft.Authorization/roleAssignments/read' …)`

The fourth item is the one that matters: it is the only check that proves the three readers are
really independent, and it is the exact bug the 2026-09-18 amendment exists to prevent.
