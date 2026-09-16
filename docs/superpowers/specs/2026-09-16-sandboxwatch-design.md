# SandboxWatch — design

*Written 2026-09-16. Approved in chat the same day: name, surfaces, `az` write actions, and the
four-batch sequence 1 → 2 → 3 → 4.*

## What this is

The Mac half of [Azure Sandbox Manager](../../../../AzureSandboxManager). The server runs *inside*
the Azure resource group it watches, collects a snapshot every ten minutes, and exposes it — plus an
append-only change log — over `/api/v1`. SandboxWatch reads that API from a Mac, tells you when
something changed while nobody was looking, and can act on the web apps under your own Azure
credentials.

The model is the pair `Homeport` / `HomePortManager`: an agent on the machine, a manager on the Mac.
`AzureSandboxManager` already plays Homeport's part, and its `docs/api.md` ships a Swift client
sketch — the server was written anticipating this client. Its README names the gap in its own
limitations: *"No notifications. Changes are visible, not pushed. The append-only change log is the
right base to build alerting on."* That is what SandboxWatch is for.

## What does not transpose from HomePortManager

Worth stating, because copying the model too faithfully is the main way this goes wrong.

`hpm` talks **agentless SSH**, and most of its command table is mutation: install, update, backup,
restore, config push, remove, maintenance. None of that has a counterpart here. There is nothing to
install on an App Service web app and nothing to back up. A command table copied from `hpm` would be
mostly dead commands.

And `hpm`'s `fleet.yaml` is explicitly *"no secrets"*, because with SSH the transport is not a
secret. Here the transport **is** a secret. That single difference drives the storage decision in
§2.

## 1. Repository shape

A new repository, `~/DevApps/AzureTools/SandboxWatch`, sibling to `AzureSandboxManager`.

```
Package.swift                 SandboxWatchKit (library) + sbw (executable) + tests
Sources/SandboxWatchKit/      all logic, no I/O without a seam
Sources/sbw/                  thin CLI over the Kit
Tests/SandboxWatchKitTests/   unit tests against mocked seams
App/SandboxWatch.xcodeproj/   SwiftUI menu bar app + control center, links the Kit locally
Scripts/release.sh            signed, notarised DMG
docs/                         api contract, getting started, security model
```

Dependencies: `swift-argument-parser` and `Yams`. Nothing else. This mirrors HomePortManager's split
and its design note — *"A future macOS app can link HomePortKit directly"* — except that here the app
is in scope from the start, so the Kit is built for two consumers from day one.

Platform: macOS 13. Tests run with `swift test`; the app builds with `xcodebuild`.

## 2. Inventory and secrets

Two stores, split along one line: **what is not secret goes in a file you can read and edit; the
token goes in the Keychain.**

`~/.config/sbw/sandboxes.yaml`:

```yaml
sandboxes:
  - name: dev
    url: https://sandbox-dev.azurewebsites.net
    notes: "Groupe de ressources de dev, budget 50 €"
```

The token lives in the Keychain — `kSecClassGenericPassword`, `service = fr.lauriat.sandboxwatch`,
`account = <sandbox name>`. `sbw sandbox add <name> --url <url>` reads it from stdin, never from an
argument: an argument ends up in the shell history and in the process table.

`SandboxStore` (YAML, mirroring `FleetStore`) and `TokenStore` (Keychain) are separate types with
separate tests. `TokenStore` is a protocol so tests never touch the real Keychain.

## 3. The Kit — two mockable seams

Every side effect goes through one of two protocols, both mocked in tests. This is `hpm`'s
`ProcessRunner` pattern, applied twice because there are two kinds of outside world here.

| Seam | Production | Test | Used for |
|---|---|---|---|
| `HTTPClient` | `URLSessionHTTPClient` | `MockHTTPClient` | the sandbox API |
| `ProcessRunner` | `SystemProcessRunner` | `MockProcessRunner` | `az` |

`ProcessRunner` takes an **exact argument array**, never a shell string. There is no code path that
builds a command by interpolation.

`SandboxAPIContract.swift` holds the executable half of the API contract — status codes, error
codes, the envelope shape — so that a server change breaks a test rather than a screen.

### The rule the model must make unbreakable

The server's README states the property that makes its change detection trustworthy:

> Data is compared **only when both snapshots successfully collected that section**. A change of
> collection status is its own event, never a data change. […] there is a test that fails if the
> rule is removed.

A client can undo that from the outside. If the governance section comes back `denied` and the UI
renders it as *0 role assignments*, it reintroduces exactly the false alarm the server was built to
prevent — at the worst possible moment, since `denied` is what a revoked Reader role looks like.

So in the Kit's model, a section is:

```swift
/// A collected section. There is no stored `data` property: the payload lives inside `.ok`,
/// so it cannot be read without first establishing that the collection succeeded.
public enum Section<T> {
    case ok(T, durationMs: Int)
    case denied(message: String?)
    case error(message: String?)
}
```

The payload is unreachable without switching on the case. Rendering a denied section as empty data is not
a discipline the UI has to remember — it does not compile. A test asserts that a `denied` governance
section renders as an explanation, never as a count.

## 4. Reading

`sbw status [name | --all]` — one row per sandbox: snapshot age, per-collector status, apps up/down,
budget percentage, number of changes in the last 24 h. `--all` runs in parallel, output grouped.

`sbw doctor <name>` — the five states the API lets us separate cleanly, each with its own message
and its own next step:

| Observation | Verdict |
|---|---|
| Connection refused / DNS failure | The web app is down or the URL is wrong |
| `401 Unauthorized` | The token is wrong or missing from the Keychain |
| `503 NoSnapshot` | The app is up but has not completed a collection yet — wait, do not redeploy |
| `200`, sections `denied` | The Reader role is missing **or not yet propagated** — the managed-identity token service caches role membership, and Microsoft documents up to 24 h. Not a failure. |
| `200`, `ageSeconds` ≫ interval | The collector has stalled; the data on screen is old |

The fourth row is the one that matters. Reporting a propagation delay as a broken deployment is
exactly the half-hour of wrong readings the server project was written after.

## 5. Changes — the cursor

`sbw changes <name> [--since <iso>] [--limit n]` prints the change log. `sbw watch [--all]` polls and
prints transitions as they appear.

`/api/v1/changes` returns newest first, `?limit=` in 1–500 (clamped, not rejected), default 50. Two
traps follow from that shape, both handled in the Kit rather than discovered later:

**Cursor identity.** The cursor is `(at, type, subject)`, not `at` alone. Timestamps are not
guaranteed unique — several events share a collection instant — and a timestamp-only cursor either
replays the tie or drops it.

**Overflow detection.** If the oldest event in the returned page is still newer than the cursor, the
page did not reach back far enough and events were silently lost. The Kit detects that condition,
widens `limit`, and refetches. Without it, more than 50 events between two polls vanish with no
signal — the failure mode a change-detection tool can least afford.

**Severity.** `collector_access_lost` and `collector_access_restored` get their own level. They are
the founding incident of the whole project — a Contributor role moved over a weekend, every `az`
command failing at once. They do not share a lane with `probe_status_changed`.

The cursor is persisted per sandbox under `~/.config/sbw/cursors/<name>.json`, so the CLI and the app
agree on what has already been seen.

## 6. Writing — `az` under your own credentials

The server is read-only by design, and stays so. Write actions go through the local `az` CLI under
Vincent's own account, never through the sandbox token. That keeps the server's security property
intact: *someone holding the token can read an inventory, and change nothing.*

Scope: `start`, `stop`, `restart` of a web app in the watched resource group. Nothing else.

This is the only part of the design that can cause real damage, so three guards are load-bearing.

**Guard 1 — subscription.** `az` points wherever `az account set` last left it, which has nothing to
do with the sandbox you are looking at. Before any action, `az account show --query id -o tsv` is
compared against the snapshot's `subscriptionId`; on mismatch the action is refused, naming both
values. Without this, `sbw restart api` can restart a same-named web app in a different subscription.

**Guard 2 — freshness.** The snapshot can be ten minutes old. Every action chains
`POST /api/v1/refresh` → re-read → confirmation prompt showing `ageSeconds` and the target's current
state. The server provides both primitives; refresh is rate-limited to once per 30 s and returns the
current snapshot with `X-Refresh-Skipped: true` rather than an error, so this is safe to call.

**Guard 3 — non-interactivity.** Every invocation carries `--only-show-errors --output json`, and a
preflight fails fast on "not logged in" instead of triggering a device-code flow. From a menu bar app
with no TTY, an `az` login prompt hangs forever.

Confirmation is required; `--yes` bypasses it for scripting. Every action is appended to
`~/.config/sbw/actions.jsonl` — what, where, when, exit status — the local equivalent of `hpm`'s task
journal.

## 7. Menu bar app and control center

**Menu bar.** Fleet health at a glance: the icon turns ⚠️ as soon as any sandbox has a problem. One
row per sandbox — snapshot age, apps up/down, budget percentage, unread changes. Refresh every five
minutes. macOS notifications **on transition only**, never on steady state, with
`collector_access_lost` at critical.

**Control center window.** An overview across sandboxes, then per-sandbox tabs: Summary, Changes,
Apps & probes, Governance, Budget, Actions. The Actions tab carries the same three guards as the CLI
— the confirmation sheet shows `ageSeconds` and the resolved subscription before the button is live.

French and English via `Localizable.xcstrings`, light/dark theme. Released as a signed, notarised DMG
through `Scripts/release.sh`, on the shared `AppliMacVincentGithub` notarytool profile.

## 8. Error handling

Errors are values, not thrown exceptions, wherever the answer is a state the UI must display. This is
`HomeportAPIContract`'s rule — *"Compatibility is answered with a value, never a thrown error: a
server too old to serve the API is an ordinary state the UI displays, not a failure"* — and it
applies just as well to `denied`, to `NoSnapshot`, and to a stale snapshot. Thrown errors are
reserved for programmer mistakes and genuine I/O failure.

## 9. Testing

`swift test` against mocked seams, no network, no Keychain, no `az`. The suite must cover, at
minimum:

- the cursor: tie on identical timestamps, overflow detection and widening, empty log, first run
- `doctor`: each of the five verdicts, from a canned HTTP response
- the section model: a `denied` section cannot be read as empty data
- the subscription guard: mismatch refuses, match proceeds, `az` never invoked on refusal
- `az` argument construction: exact arrays, no interpolation
- contract: every documented status and error code maps to a modelled state

## 10. Delivery — four batches

Each is independently useful and shippable.

| Batch | Contents |
|---|---|
| **1** | Kit + read-only CLI: inventory, Keychain, `status`, `doctor`, `changes` |
| **2** | Menu bar app, change notifications on transition |
| **3** | `az` write actions with the three guards, in CLI and app |
| **4** | Control center window |

Sequence approved: 1 → 2 → 3 → 4. HomePortManager's control center corresponds to its epics 1–3 and
is still unfinished after real work; keeping it last means the first three batches ship regardless.

## Out of scope

- Anything the server does not expose. Regional quotas, for instance, are read at subscription scope
  and out of reach of a Reader role on a resource group.
- Deploying or configuring the server itself. `AzureSandboxManager` has `scripts/deploy.sh`.
- Any write action beyond start/stop/restart of a web app. Creating or deleting resources is not a
  thing a menu bar app should be able to do.
- Alerting to anywhere but macOS notifications. No mail, no webhook, no push service.
