# Batch C — The control center

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this
> plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A window on the existing menu bar agent: an overview across sandboxes, then per-sandbox
tabs — Summary, Changes, Apps & probes, Governance, Budget, Actions — with the Actions tab
carrying the same three guards as the CLI.

**Architecture:** The spec's gate for this batch is *"nothing new in logic; if a notion is missing,
it belonged to batch A."* It has already caught one: `ActionCommands` lived in the `sbw`
executable, which an app target cannot link. That move is Task 0, and it is done. What remains in
the Kit is shaping, with tests; the SwiftUI views own layout and nothing else.

**Tech Stack:** AppKit `NSWindow` + `NSHostingView`, SwiftUI, `Localizable.xcstrings`, xcodegen.

**Spec:** `docs/superpowers/specs/2026-09-16-sandboxwatch-design.md` §7, and
`docs/superpowers/specs/2026-09-17-supervision-dispositif-design.md` §7 "Batch C".

## Global Constraints

- `.macOS(.v13)`, Swift 5.9. French to Vincent; English in code and docs.
- No new logic. A notion missing from the Kit belonged to an earlier batch — move it, do not
  reinvent it in a view.
- The suite touches no network, no Keychain, no `az`, and no real `~/.config/sbw/`.
- **One journal, shared.** `~/.config/sbw/actions.jsonl` is *not* split per surface. A cursor is
  consumed — one reader advancing it robs another — but nobody consumes a journal entry, and the
  point is a single record of everything done to the sandbox, whichever surface did it. The
  per-surface rule applies to cursors and liaison state, and stops there.

## What the spikes measured (2026-09-18, run and removed)

**An `LSUIElement` agent can present a window.** `setActivationPolicy(.regular)` on open and back
to `.accessory` on close works, and **the status item survives both flips** — measured, because
losing it would be the obvious way this goes wrong.

**There is no main menu, so Cmd-W and Cmd-Q do not exist** until one is built by hand. Installing a
minimal `NSMenu` with `performClose:`/`terminate:` gives `Close=w`, `Quit=q` — and macOS adds its
own "Close All" alternate. Build the menu *before* `setActivationPolicy(.regular)`, or the first
activation shows an empty menu bar.

**Key-window behaviour could not be settled from this session, and there is nothing to fix.** The
window came back `isVisible: true`, `canBecomeKey: true`, but never key — and the diagnostic said
why: `frontmost app: loginwindow`. The screen was locked, so macOS refused activation. Three
passes were spent before that showed up; the lesson is to log `NSWorkspace.shared.frontmostApplication`
in the *first* pass of any activation spike. Vincent confirms this one interactively.

**The notarization profile does exist — an earlier claim here that it did not was wrong.**
On 2026-09-18, with the screen locked, `xcrun notarytool history --keychain-profile
"AppliMacVincentGithub"` returned *"No Keychain password item found"* and a keychain dump showed
no notarytool credential. Both were artefacts of the locked session. `security show-keychain-info`
answering `no-timeout` was read as "unlocked", and it does not mean that: it reports the lock
*timeout policy*, not the lock state. The contradicting signal — an unrelated item also being
unreadable — was explained away instead of followed. Re-run with the screen unlocked, the profile
lists accepted submissions, and `Scripts/release.sh` notarized successfully on the first try.

The lesson, which is the same one this project keeps teaching: **a negative result from a tool
needs its own verification before it becomes a fact.** The cheap check was to read a known-present
item; that check was run, came back negative too, and was dismissed.

---

## Task 0: The action decisions move into the Kit — **done**

`SandboxAction.prepare / describe / render / journal / perform` now live in
`Sources/SandboxWatchKit/SandboxAction.swift`; `Sources/sbw/ActionCommands.swift` holds only the
`ParsableCommand` wrappers. Verified as a move: 174 tests before and after.

Also done, and the reason it came up now: `Scripts/build-cli.sh` signs `sbw` with the same stable
Developer ID identity and a fixed `--identifier fr.lauriat.sbw`. A SwiftPM binary is unsigned, so
every `swift build -c release` gave it a new code identity, the Keychain ACL stopped matching, and
the next `sbw` call blocked on a SecurityAgent dialog — forever, in a non-interactive shell. This
happened for real during this batch.

## Task 1: The window, and what it shows at the top

**Files:**
- Create: `Sources/SandboxWatchKit/OverviewRow.swift`,
  `Tests/SandboxWatchKitTests/OverviewRowTests.swift`,
  `App/SandboxWatch/ControlCenterWindow.swift`, `App/SandboxWatch/OverviewView.swift`
- Modify: `App/SandboxWatch/AppDelegate.swift` (a menu item that opens the window)

**Interfaces:**
- Produces: `OverviewRow { sandbox, icon, apps: (up: Int, of: Int), budgetPercent: Double?,
  ageSeconds: Double?, unreadChanges: Int }` and `OverviewRow.make(from:sandbox:)`.

- [ ] **Step 1: Write the failing tests.** The rule the whole project rests on has to hold here
      too — a `denied` section must never render as `0/0 up` or `0%`:

```swift
func testADeniedAppsSectionYieldsNoCountAtAllNotZeroOfZero()
func testADeniedBudgetYieldsNoPercentageNotZero()
func testAnUnreachableSandboxStillProducesARowSoItCannotVanishFromTheList()
func testTheRowsIconMatchesWhatTheMenuBarWouldShow()
```

The last one keeps the window and the menu bar on one vocabulary: both go through
`WatchPresentation.icon(for:)`, never two thresholds.

- [ ] **Step 2: Run them, watch them fail.**
- [ ] **Step 3: Implement `OverviewRow`**, reading sections only through `fold(ok:unavailable:)`.
- [ ] **Step 4: Run the suite.**
- [ ] **Step 5: Prove they discriminate.** Make the denied branch return `0`; expect the first two
      tests and nothing else to fail.
- [ ] **Step 6: The window.** `NSWindow` + `NSHostingView`, menu built before the policy flip,
      `.accessory` restored in `windowWillClose`. One window, reused — a second menu click raises
      the existing one rather than opening another.
- [ ] **Step 7: Commit** — `feat: a control center window, and an overview that never invents a zero`.

## Task 2: The per-sandbox tabs

**Files:**
- Create: `Sources/SandboxWatchKit/SandboxDetail.swift`,
  `Tests/SandboxWatchKitTests/SandboxDetailTests.swift`,
  `App/SandboxWatch/SandboxTabsView.swift`, `App/SandboxWatch/ActionsTabView.swift`
- Modify: `App/SandboxWatch/Localizable.xcstrings`

- [ ] **Step 1: Write the failing tests** — one per tab, each asserting that an unavailable
      section is rendered as its reason and never as an empty list:

```swift
func testTheGovernanceTabShowsWhyItIsUnavailableNotAnEmptyRoleList()
func testTheProbesTabPairsEachProbeWithItsApp()
func testTheBudgetTabShowsSpentAgainstAmountAndNothingWhenDenied()
func testTheChangesTabCarriesSeverityMarkersMatchingSbwChanges()
```

- [ ] **Step 2: Run them, watch them fail.**
- [ ] **Step 3: Implement `SandboxDetail`** — shaping only, no formatting decisions in the views.
- [ ] **Step 4: Run the suite.**
- [ ] **Step 5: Build the SwiftUI tabs.** The Actions tab calls `SandboxAction.prepare`, shows
      `SandboxAction.describe` in a confirmation sheet, and enables the button only on
      `.success` — the same three guards, through the same code, because Task 0 put it where the
      window can reach it.
- [ ] **Step 6: FR + EN for every new string.**
- [ ] **Step 7: Commit** — `feat: per-sandbox tabs, with the Actions tab behind the same guards`.

## Task 3: Release — **done**

- [x] `Scripts/release.sh`, modelled on `MacTools/MarkdownViewer/Scripts/release.sh` minus what
      does not apply (no Sparkle, no appex, so no EdDSA signing and no appcast). It **calls**
      `Scripts/build-app.sh` rather than duplicating the signing block.
- [x] DMG in `release/`, with the drag-to-install Finder layout: the app on the left, an
      `/Applications` alias on the right.
- [x] Notarized and stapled. `The validate action worked!`
- [x] `Scripts/make-icon.swift` and an `AppIcon` asset catalog. The agent is `LSUIElement`, so it
      has no Dock icon at rest — but opening the control center flips it to `.regular`, and that
      is when the icon is needed. SF Symbols are deliberately not used: Apple's licence does not
      allow them in an app icon.
- [ ] Publishing (`gh release create`, a tag) stays a separate, deliberate step. The script prints
      the command rather than running it: *always confirm before creating releases or tags.*

## Task 4: Documentation, in the same turn

- [ ] `ARCHITECTURE_EN.md` + `ARCHITECTURE.md`: `SandboxAction` in the Kit table, the window, and
      one line on why the journal is shared while cursors are not.
- [ ] `CLAUDE.md`: `Scripts/build-cli.sh` and why signing the CLI is not optional.
- [ ] `README.md`, `CHANGES.md`, `TODOS.md`, `MEMORY.md`, `COMMANDS.md`, `PLAN.md`.

---

## Exit gate for batch C

- [ ] `swift test` green; `./Scripts/build-cli.sh` and `./Scripts/build-app.sh` both clean.
- [ ] No new notion. `grep` shows the views calling Kit functions, not reimplementing them — in
      particular the Actions tab goes through `SandboxAction`, so the refusal is journalled by the
      same code the CLI uses.
- [ ] A denied section renders as its reason in every tab. Never `0%`, never `0/0 up`.
- [ ] **Vincent's to run.** The window opens from the menu bar with keyboard focus and a working
      Cmd-W, the status item survives closing it, and the Actions tab refuses when `az` points at
      the wrong subscription. Key-window behaviour could not be settled from a locked screen.
