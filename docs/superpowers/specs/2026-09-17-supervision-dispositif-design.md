# Supervising the Azure sandbox: the whole device

**Date**: 2026-09-17
**Status**: approved by Vincent, section by section, on 2026-09-17
**Scope**: two repositories — `AzureSandboxManager` (the server and its web front end) and
`SandboxWatch` (the Kit, the `sbw` CLI and the macOS app)

This document does not describe a feature. It fixes **who is allowed to do what** across the three
surfaces that watch one Azure sandbox, so that the two detailed specs that follow — the macOS app,
then the web front end — can be written without re-arbitrating the same questions.

## 1. What is missing today

Three surfaces already exist, and four things are wanted from them:

| Want | Served today? |
|---|---|
| Be told without looking | No. Both READMEs say it: *"No notifications. Changes are visible, not pushed."* |
| A better place to look | Partly. `src/html.js` renders one flat page; it cannot show that one event matters more than another. |
| See several sandboxes at once | Only in `sbw status --all`. Nothing shows them together visually. |
| Act, not only observe | No. Seeing an app is down still means a trip to a terminal and `az`. |

## 2. The governing question

Every future feature is placed by one question:

> **Does this have to stay true when the sandbox is dead?**
> If yes, it belongs to the Mac. If no, it belongs to the server, and the web page may show it.

This is not a preference. The founding incident is *"every `az` command failed at once"*. A front end
hosted inside the resource group is the first casualty of that scenario: if the web app stops, if the
Reader role is revoked, if the subscription is suspended, the page cannot report it — it **is** the
casualty. Only an observer outside can say "the sandbox stopped answering".

Consequences, stated once so they are not re-litigated:

- The web front end can never carry notifications, aggregation across sandboxes, or write actions.
- Aggregation is refused for a second, independent reason: sandbox A would have to hold sandbox B's
  token. That spreads secrets instead of concentrating them in one Keychain.
- Write actions are refused for a third: they would require Contributor on an internet-facing page,
  destroying the property that makes the token shareable — *holding it lets you read an inventory and
  change nothing*.

## 3. The three surfaces

### 3.1 The server — the inside observer

**Does**: collects every 10 minutes under a managed identity holding Reader; diffs against the
previous snapshot; appends to a persistent, append-only change log; serves `/api/v1`; and — new in
this design — **judges the nature of a change**: its type and its severity.

**May not**: write to Azure (never Contributor) · know any sandbox but its own · push anything
outward (no SMTP, no webhook) · depend on an npm package.

Each prohibition is what keeps the token shareable. The day one of them falls, handing the token to
someone stops being harmless — and a single-header authentication stops being an acceptable trade.

### 3.2 The web front end — the display window

**Does**: show the state and the change log of **the** sandbox hosting it, read-only, from any
device, with nothing to install. Shareable by handing over the URL and the token.

**May not**: aggregate several sandboxes · act · notify · **judge**. It renders the severity the
server publishes; it never computes one.

### 3.3 The macOS app — the cockpit

**Does**: everything that requires being outside. Observe that a sandbox no longer answers. Compare
several sandboxes side by side. Detect a transition between two readings. Notify. Act through `az`
under Vincent's own login.

**May not**: use the sandbox token to write · act without the three guards · render a `denied`
section as empty data.

Its judgment bears on **the link**, never on the content. The content is something the server knows
better than it does.

### 3.4 The CLI is not a fourth surface

`sbw` and the app share the Kit, therefore the same decisions. They must always say the same thing
about the same state. A behaviour present in one and absent from the other is a design defect, not a
feature. The useful corollary: everything the app can do is testable without launching the app.

## 4. The single rule

> **A fact is computed where it is known, once.**
> The server judges what it sees. The Mac judges the link. The web judges nothing.

### Why the rule is needed: the vocabulary has already drifted

Measured on 2026-09-17:

| Place | Holds | Content |
|---|---|---|
| `AzureSandboxManager/src/diff.js` | Emits the types — the truth | **12** types |
| `AzureSandboxManager/src/html.js` (`EVENT_LABELS`) | Human labels | 12, aligned |
| `SandboxWatchKit/ChangeEvent.swift` | Severity classification | **14** — including `deny_assignment_added` and `deny_assignment_removed`, which the server never emits |

Two dead branches on the Swift side, harmless today. The real cost is elsewhere: **severity exists
only in Swift**, so the web dashboard cannot tell a `collector_access_lost` — the founding incident —
from an HTTP probe that flickered. It puts them in the same flat table.

The twelve types the server actually emits:

```
resource_added        resource_removed      app_state_changed     plan_tier_changed
role_added            role_removed          lock_added            lock_removed
budget_threshold_crossed  probe_status_changed
collector_access_lost collector_access_restored
```

## 5. API contract: `severity`

### 5.1 The change

An event goes from

```json
{ "at": "…", "type": "role_removed", "subject": "…", "collector": "governance", "detail": {} }
```

to the same thing plus one field:

```json
{ "…": "…", "severity": "critical" }
```

Additive and backward compatible: a client that ignores it keeps working.

| Severity | Types |
|---|---|
| `critical` | `collector_access_lost`, `collector_access_restored` |
| `notable` | `role_added`, `role_removed`, `lock_added`, `lock_removed`, `budget_threshold_crossed` |
| `informational` | `resource_added`, `resource_removed`, `app_state_changed`, `plan_tier_changed`, `probe_status_changed` |

### 5.2 Computed on read, never stored

**Decision.** `src/api.js` derives the severity on the way out. It is never written to
`events.jsonl`.

The log is append-only and persistent; it still holds the trace of a role transfer noticed weeks
later. Writing a severity into it freezes a judgment: the day `probe_status_changed` is promoted
above "informational", history stays classified under the old rule and becomes inconsistent with the
present. Severity is a function of the type, so it needs no storage — and deriving it reclassifies
the whole history retroactively and uniformly, with no data migration.

One module in the server owns the vocabulary — the twelve types and their severity — consumed by
`diff.js` (which emits them), `api.js` (which decorates) and `html.js` (which displays). One table,
three consumers, one language, one repository.

### 5.3 What the server does not publish: the label

The server publishes a **language-free judgment** (`severity`), not words. `EVENT_LABELS` stays in
`html.js`; the macOS app will build its own in `Localizable.xcstrings`, in French and English — which
an English label served by the API would prevent.

### 5.4 How the Kit tolerates a severity it does not know

| Behaviour on an unknown value | Verdict |
|---|---|
| Fail (`APIFailure.malformed`) | No — a new severity would break `sbw changes` entirely |
| Downgrade to `informational` | **No** — the forbidden direction of error: it silently mutes something not understood |
| Treat as `notable`, display the raw value | **Yes** |

An unknown severity becomes `notable`: visible with its `!`, printed as received so the operator can
see the client is behind, and **never** a notification — a value that is not understood must not be
able to wake anyone. Same logic as `denied ≠ empty`: **never quieter than what is known**.

### 5.5 The Swift table survives as a dated fallback

**Decision.** An *absent* `severity` field — a server older than the client — must not be treated as
"unknown → notable", because that would demote `collector_access_lost` in exactly the case that
matters.

The Swift table therefore stays, but as a fallback used only against a server predating this change,
commented as such and deletable once the server is deployed. It moves out of `ChangeEvent` and into
`SandboxAPIContract`, which is already *"the executable half of `docs/api.md`"* — that is where
shared vocabulary belongs. A test there pins the twelve types, so a divergence breaks a test instead
of breaking a screen.

The two phantom `deny_assignment_*` branches are deleted now, regardless.

## 6. Data flow and transition detection

### 6.1 Two sources, two judges

| Source | Who judges | How it arrives |
|---|---|---|
| Change events | **The server** — it judges the content | `/api/v1/changes` plus the `(at, type, subject)` cursor |
| Link transitions | **The Mac** — it judges the link | `Doctor`, compared against the previous reading |

Neither can do the other's work. The server cannot report that it is unreachable; the Mac cannot know
a role moved unless the server tells it.

### 6.2 One loop, on `/snapshot`

**Decision, reversing what `TODOS.md` recorded for batch 2.** The polling loop calls `/api/v1/snapshot`
and `/api/v1/changes`, not `/api/v1/apps`.

`Doctor` calls `/snapshot` because it needs `unavailableSections`. On `/apps` alone, the app cannot
reproduce `sbw doctor`: a sandbox whose governance section is *already* denied would look perfectly
healthy, because there is a transition only when it has just changed.

A snapshot of a sandbox resource group is a few kilobytes every five minutes. Optimising that now
would buy an unmeasurable gain at the price of app/CLI divergence — which section 3.4 forbids.

### 6.3 `Doctor.Finding` needs a `kind`

`Doctor.Finding` carries `.stale(ageSeconds:)` and `.healthy(ageSeconds:)`, whose number changes at
**every** reading. Comparing two `[Finding]` with `Equatable` would report a transition every five
minutes, forever.

The Kit therefore gains `Finding.kind` — the case stripped of its payload — and transitions are
defined on the **set of kinds**. The seven kinds: `unreachable`, `unauthorised`, `notCollectedYet`,
`serverProblem`, `stale`, `sectionsUnavailable`, `healthy`.

The set of kinds last observed for each sandbox is persisted next to the change cursors, at
`~/.config/sbw/liaison/<name>.json`. An unreadable or missing file means "no previous observation",
which safeguard 1 already defines.

**Each surface keeps its own memory — amended 2026-09-18.** This section first said `sbw watch` and
the app share one. They must not. The argument is the one already made about the change cursor: if
`watch` moved the cursor, a manual `sbw changes` would show nothing, "which is a worse bug than the
gap". The same holds here. With a shared liaison state, one `sbw watch dev --once` run to check
something consumes the transition and the app never notifies — and a line printed in a terminal
nobody is reading has not announced anything to a person, while a notification has. Treating the two
channels as interchangeable is what makes that swallow possible.

`LiaisonStore` and `CursorStore` both take a `directory`, so this is a caller's decision and the Kit
stays neutral:

| Surface | Change cursor | Liaison state |
|---|---|---|
| `sbw changes` | `~/.config/sbw/cursors` | — |
| `sbw watch` | `~/.config/sbw/cursors-watch` | `~/.config/sbw/liaison` |
| the app | `~/.config/sbw/cursors-app` | `~/.config/sbw/liaison-app` |

Three readers, three notions of "since I last looked". Announcing the same thing twice on two
different channels is the acceptable error here; missing it on the channel the operator is actually
watching is not.

`Doctor` deliberately refuses to reduce its diagnosis to a single verdict (*"reducing that to one
verdict would hide whichever the operator needed"*). A transition is therefore a change of the
**set**, not of a maximum: going from `{stale}` to `{stale, sectionsUnavailable}` is a transition,
even though "the worst" did not change.

### 6.4 The notification policy

> **A notification is a transition, never a state.**

| What happens | Menu bar | Notification |
|---|---|---|
| `critical` event (`collector_access_lost` / `_restored`) | ⚠️ | **yes** |
| `notable` event | dot | no |
| `informational` event | — | no |
| Unknown severity | dot | no |
| The link changes nature | ⚠️ | **yes, both ways** |
| The link is unchanged | unchanged | no |

Both directions matter: knowing it is **over** is worth as much as knowing it began. Without the
return, the operator is left facing a ⚠️ with no way to know whether it is still true.

`notable` does not notify: a `role_added` on a sandbox being actively worked on would fire in bursts.
`notable` means "worth seeing next time you look"; `critical` means "worth interrupting you".

### 6.5 Three safeguards

1. **The first observation establishes, it does not announce.** At launch, on wake, after a network
   outage: the first reading fixes the state without notifying. This is the change cursor's first-run
   rule, for the same reason — otherwise opening the lid on Monday would produce an
   "unreachable → healthy" notification that describes nothing.

2. **Two consecutive readings to change link state, in both directions.** A Mac that sleeps, changes
   Wi-Fi or switches to tethering manufactures spurious "unreachable". One failed reading changes
   nothing; two do — and a single successful reading does not declare recovery either, for the same
   reason. The price is at worst five minutes of delay on a real outage, against a stream of false
   alarms, and a repeated false alarm is exactly what makes an operator start ignoring the icon.
   The rule does not apply to change events: those come from a durable server-side log and are never
   spurious.

3. **Compare kinds, not values.** See 6.3.

## 7. Build order, and what each batch must prove

### Batch 0 — Severity, server side (`AzureSandboxManager`)

One module owning the vocabulary; `api.js` decorating on read; `html.js` consuming the same table;
`docs/api.md` updated.

**Must prove**: a thirteenth type added to `diff.js` without a severity **breaks a test** ·
`events.jsonl` gains no field (a test reads a line back and asserts its keys) · still zero npm
dependency.

**Gate**: deployed to the real sandbox; `curl /api/v1/changes` shows `severity`.

Immediate benefit before any redesign: the existing dashboard can finally distinguish a
`collector_access_lost` from a flickering probe.

### Batch A — Kit and menu bar (the current batch 2)

`Finding.kind`, persisted link state, transition detection, `sbw watch`, then the app and its
notifications.

**Must prove**: two readings of a healthy sandbox produce **zero** transitions · the first
observation after an interruption announces nothing · one failed reading does not change the state,
two do · `sbw watch` and the app say the same thing about the same state.

**Gate**: the task pending in `TODOS.md` — exercising `KeychainTokenStore` and
`URLSessionHTTPClient` against a real sandbox. The moment is right: the app will exercise both every
five minutes, which no test ever will.

### Batch B — `az` actions (the current batch 3)

**Must prove**: each of the three guards **fails closed**, as a test, before a single `az` runs · the
action journal records a refused action as well as a performed one.

The only batch that can break something real. The guards are written with their tests, not after.

### Batch C — Control center (the current batch 4)

**Must prove**: nothing new in logic. If a notion is missing, it belonged to batch A.

### Batch D — Web front end redesign

**Must prove**: no judgment written in JavaScript beyond batch 0's shared table · still zero
dependency · readable on a phone · and on screen, a `denied` section renders **as refused**, never as
an empty table.

### Batch E — Web actions behind Easy Auth

**Not planned.** Ranked last by Vincent, and it breaks the property that makes the token shareable.
Reopened only on an explicit request.

## 8. Out of scope

- Per-sandbox notification rules, quiet hours, notification grouping. If they are missed, use will
  say so, and they can be added without breaking anything.
- Any pusher living outside both the sandbox and the Mac (scheduled GitHub Action, mail). Decided on
  2026-09-17: being notified while the Mac is running is enough; the cursor guarantees that what
  happened during an absence arrives grouped on resumption, without loss.
- Alerting beyond macOS notifications (mail, webhook) — already out of scope in the 2026-09-16 spec.
- Actions beyond start / stop / restart — refused by design.

## 9. Cross-repository consequence

Batch 0 lives in `../AzureSandboxManager`. The implementation plan derived from this spec therefore
has its first task **in another repository**, with its own tests, its own CI and its own deployment:
a pull request there before a line of Swift here.

This document lives in `SandboxWatch` because the Mac side carries most of it; a pointer belongs in
`AzureSandboxManager/docs/`, matching the cross-link that already exists between the two READMEs.
