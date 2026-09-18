# Batch B — `az` actions behind three guards

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this
> plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `sbw start|stop|restart <sandbox> <app>`, run through the local `az` CLI under Vincent's
own credentials, refused by any of three guards before a single `az` process is spawned.

**Architecture:** A new `ProcessRunner` seam, mocked in tests, so the whole batch is provable
without spawning `az`. The guards are values (`ActionRefusal`), not thrown errors, because a
refusal is a state the CLI and the app must both display. Every attempt — refused or performed —
is appended to `~/.config/sbw/actions.jsonl`.

**Tech Stack:** Foundation `Process`, XCTest, ArgumentParser.

**Spec:** `docs/superpowers/specs/2026-09-16-sandboxwatch-design.md` §6, and
`docs/superpowers/specs/2026-09-17-supervision-dispositif-design.md` §7 "Batch B".

## Global Constraints

- **This is the only batch that can break something real.** Each guard is written with its test,
  never after. A guard without a test that proves it fails closed is not a guard.
- The sandbox token is never used for a write. Reads use the token; writes use `az`.
- Errors that are states go in values; `SandboxWatchError` stays for what the operator caused.
- Never let the suite spawn a real process, reach the real Keychain, or touch `~/.config/sbw/`.
- `.macOS(.v13)`, Swift 5.9, French to Vincent, English in code and docs.

## What was measured before writing this (2026-09-18)

Read from the tools themselves, not assumed.

**`az` on this Mac:** version 2.88.0 at `/opt/homebrew/bin/az`, logged in, current subscription
`3e0041cf-c56e-447a-917f-15d5ac615f6f` — which is the subscription in the sandbox's own
`AuthorizationFailed` message, so guard 1 passes today and the test must force the mismatch.

**Argument shape**, from `az webapp restart --help`: `--name/-n`, `--resource-group/-g`,
`--subscription`, `--slot/-s`. `--only-show-errors`, `--output/-o` and `--query` are global
arguments and accepted on every subcommand.

**Logged out, `az` fails fast and does not hang.** With an empty `AZURE_CONFIG_DIR`:

```
$ az account show --only-show-errors --output json
exit=1
stdout: (empty)
stderr: ERROR: Please run 'az login' to setup account.
```

That is guard 3's contract, measured rather than assumed: a non-zero exit with empty stdout, no
device-code flow, no prompt. The fear the guard exists for — an `az` login prompt hanging forever
in a menu bar app with no TTY — is real for `az login`, not for this preflight, which is exactly
why the preflight must be the thing that runs first.

**The server already offers the refresh primitive.** `POST /api/v1/refresh`, rate-limited to once
per 30 s, returning the current snapshot with `X-Refresh-Skipped: true` instead of an error.
`SandboxAPI.Route.refresh` and `SandboxAPI.refreshSkippedHeader` are already declared; the client
has no `refresh()` method yet.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/SandboxWatchKit/ProcessRunner.swift` | The seam: protocol, `ProcessResult`, `SystemProcessRunner` |
| `Sources/SandboxWatchKit/ActionGuards.swift` | The three guards, as values |
| `Sources/SandboxWatchKit/ActionJournal.swift` | Append-only journal of every attempt |
| `Sources/SandboxWatchKit/AzRunner.swift` | Exact argv, and the run |
| `Sources/sbw/ActionCommands.swift` | `start` / `stop` / `restart`, confirmation, `--yes` |
| `Tests/SandboxWatchKitTests/MockProcessRunner.swift` | Scripted exit codes and output |

---

## Task 1: The `ProcessRunner` seam

**Files:**
- Create: `Sources/SandboxWatchKit/ProcessRunner.swift`,
  `Tests/SandboxWatchKitTests/MockProcessRunner.swift`
- Test: `Tests/SandboxWatchKitTests/ProcessRunnerTests.swift`

**Interfaces:**
- Produces: `ProcessResult { exitCode: Int32, stdout: String, stderr: String }`,
  `protocol ProcessRunner { func run(_ executable: String, _ arguments: [String]) async throws -> ProcessResult }`,
  `SystemProcessRunner`, and `MockProcessRunner` with
  `script(arguments:exitCode:stdout:stderr:)` plus a recorded `invocations: [[String]]`.

- [ ] **Step 1: Write the failing tests.** `MockProcessRunner` records exactly the argv it was
      given, and an unscripted invocation is a test failure rather than a silent empty result —
      a mock that answers anything proves nothing.
- [ ] **Step 2: Run them, watch them fail.**
- [ ] **Step 3: Implement.** `SystemProcessRunner` uses `Process` with `Pipe`s, never a shell:
      an argv array cannot be word-split, and a sandbox or app name is operator input.
- [ ] **Step 4: Run the suite.**
- [ ] **Step 5: Commit** — `feat: a process seam, so az is provable without running it`.

## Task 2: The three guards, each failing closed

**Files:**
- Create: `Sources/SandboxWatchKit/ActionGuards.swift`
- Test: `Tests/SandboxWatchKitTests/ActionGuardsTests.swift`
- Modify: `Sources/SandboxWatchKit/SandboxAPIClient.swift` (add `refresh()`)

**Interfaces:**
- Consumes: `ProcessRunner`, `SandboxAPIClient`, `Snapshot`.
- Produces: `ActionRefusal` (`.wrongSubscription(expected:actual:)`, `.notLoggedIn(String)`,
  `.couldNotConfirmFreshness(String)`), `ActionContext { ageSeconds, refreshSkipped, appState }`,
  `ActionGuards.check(sandbox:app:client:runner:) async -> Result<ActionContext, ActionRefusal>`.

- [ ] **Step 1: Write the failing tests.** One per guard, each proving it fails **closed** —
      the refusal is returned and `runner.invocations` contains no `webapp` call:

```swift
func testAMismatchedSubscriptionRefusesAndNamesBothValues()
func testNotBeingLoggedInRefusesBeforeAnythingElseRuns()
func testAFailedRefreshRefusesRatherThanActingOnAStaleSnapshot()
func testTheSkippedRefreshHeaderReachesTheContext()
func testAllThreeSatisfiedYieldsAContextCarryingAgeAndState()
```

`testNotBeingLoggedInRefusesBeforeAnythingElseRuns` scripts the measured shape exactly: exit 1,
empty stdout, `ERROR: Please run 'az login' to setup account.` on stderr.

`testTheSkippedRefreshHeaderReachesTheContext` is the one that is easy to skip and must not be.
Two actions in quick succession mean the second refresh silently no-ops; a confirmation that said
nothing about it would imply freshly verified state, which is the single thing this guard exists
to guarantee.

- [ ] **Step 2: Run them, watch them fail.**
- [ ] **Step 3: Implement.** Order matters and is part of the contract: login, then subscription,
      then freshness. The cheapest and most certain refusal comes first, and nothing touches the
      network until `az` has proved it can answer.
- [ ] **Step 4: Run the suite.**
- [ ] **Step 5: Prove the tests discriminate.** Three deliberate breakages, each expected to fail
      exactly one named test: return the context when subscriptions differ; run the preflight
      after the subscription check; drop `X-Refresh-Skipped` from the context.
- [ ] **Step 6: Commit** — `feat: three guards that fail closed before any az runs`.

## Task 3: The journal

**Files:**
- Create: `Sources/SandboxWatchKit/ActionJournal.swift`
- Test: `Tests/SandboxWatchKitTests/ActionJournalTests.swift`

**Interfaces:**
- Produces: `ActionRecord { at, sandbox, app, action, outcome, detail }` where `outcome` is
  `.performed(exitCode:)` or `.refused(String)`; `ActionJournal.append(_:)`, `.records()`.

- [ ] **Step 1: Write the failing tests.**

```swift
func testAPerformedActionIsRecordedWithItsExitCode()
func testARefusedActionIsRecordedToo()          // the spec names this explicitly
func testTheJournalIsAppendOnlyAndSurvivesAReopen()
func testAnUnreadableJournalIsNoJournalNeverACrash()
```

- [ ] **Step 2: Run them, watch them fail.**
- [ ] **Step 3: Implement.** One JSON object per line, appended with a file handle, never
      rewritten. A journal you can lose by crashing mid-write is worse than none.
- [ ] **Step 4: Run the suite.**
- [ ] **Step 5: Commit** — `feat: an append-only journal that records refusals too`.

## Task 4: `AzRunner` and the commands

**Files:**
- Create: `Sources/SandboxWatchKit/AzRunner.swift`, `Sources/sbw/ActionCommands.swift`
- Modify: `Sources/sbw/SBW.swift`
- Test: `Tests/SandboxWatchKitTests/AzRunnerTests.swift`,
  `Tests/SandboxWatchKitTests/ActionCommandsTests.swift`

**Interfaces:**
- Produces: `AzAction { start, stop, restart }`,
  `AzRunner.perform(_:app:resourceGroup:subscriptionId:runner:) async throws -> ProcessResult`,
  `ActionCommands.perform(sandbox:app:action:client:runner:journal:confirmed:)`.

- [ ] **Step 1: Write the failing tests.** The argv assertion is the whole point — a test that
      only checks the exit code would pass while restarting the wrong app:

```swift
func testTheArgvIsExactlyWhatWasMeasured() async throws {
    _ = try await AzRunner.perform(.restart, app: "api", resourceGroup: "rg",
                                   subscriptionId: "sub-1", runner: mock)
    XCTAssertEqual(mock.invocations, [[
        "webapp", "restart", "--name", "api", "--resource-group", "rg",
        "--subscription", "sub-1", "--only-show-errors", "--output", "json",
    ]])
}
func testAnUnconfirmedActionDoesNotRun()
func testARefusedGuardIsJournalledAndNoAzRuns()
```

- [ ] **Step 2: Run them, watch them fail.**
- [ ] **Step 3: Implement**, then wire `start`/`stop`/`restart` into `SBW.subcommands` as thin
      `ParsableCommand` wrappers, with `--yes` bypassing the confirmation, following the
      `ReadCommands` shape so the decision stays testable without spawning a process.
- [ ] **Step 4: Run the suite.**
- [ ] **Step 5: Prove the tests discriminate.** Drop `--subscription` from the argv; expect
      `testTheArgvIsExactlyWhatWasMeasured` and nothing else to fail.
- [ ] **Step 6: Commit** — `feat: sbw start, stop and restart under your own az login`.

## Task 5: Documentation, in the same turn

- [ ] `ARCHITECTURE_EN.md` + `ARCHITECTURE.md`: `actions.jsonl` in the state table, the three
      guards and their **order**, and the `ProcessRunner` seam next to `HTTPClient` and
      `TokenStore`.
- [ ] `CLAUDE.md`: the seam is no longer "batch 3"; the guard order as an invariant.
- [ ] `README.md`: batch 3 ticked, the three guards in one line each.
- [ ] `CHANGES.md`, `TODOS.md`, `MEMORY.md`, `COMMANDS.md`, `PLAN.md`.

---

## Exit gate for batch B

- [ ] `swift test` green; `swift build -c release` clean; the app still builds and signs.
- [ ] Each guard has a test proving it returns a refusal **and** that `runner.invocations` holds
      no `webapp` call. A guard that refuses after spawning `az` has already done the damage.
- [ ] `~/.config/sbw/actions.jsonl` holds a line for a refused attempt as well as a performed one.
- [ ] **Vincent's to run, and his alone.** A real `sbw restart dev <app> --yes` against the
      sandbox, and a real refusal by pointing `az account set` at another subscription first.
      Nothing in this plan authorises restarting one of his web apps; the suite proves the guards
      without touching Azure, and the live run is a decision, not a verification step.
