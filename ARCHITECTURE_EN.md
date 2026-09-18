# Architecture — SandboxWatch

Source of truth. `ARCHITECTURE.md` is its French mirror and must be edited in the same turn.

**What exists today: batches 1, A1, A2a, A2b and B** — the Kit, the `sbw` CLI (read commands,
`watch`, and `start`/`stop`/`restart`), and the menu bar app. Rows below marked *(batch 4)* are
designed, not built; they are here because the shape of the Kit assumes them, not because you
will find them in `Sources/`.

## Diagrams

Two interactive diagrams stand beside this document. Both are self-contained HTML — open them in
a browser; the specification each one is generated from sits next to it.

| Diagram | What it shows |
|---|---|
| [`docs/diagrams/architecture.html`](docs/diagrams/architecture.html) | The two transports and the two identities: what reads under the Reader-bounded sandbox token, what writes under your own `az` login, and which boxes are designed rather than built. |
| [`docs/diagrams/change-cursor.html`](docs/diagrams/change-cursor.html) | How `sbw changes` decides what is new — the `(at, type, subject)` mark, the widening ladder after an overflow, and the report that replaces a silent truncation. |

To regenerate one, edit its `.json` and run it back through the `archify` skill. The HTML is the
delivered artifact, not a file to hand-edit.

## Position in the family

```
Azure resource group
├── web apps, plans, budget, role assignments
└── AzureSandboxManager        Node 20, no dependencies, managed identity, Reader role
    │                          collects every 10 min, diffs against the previous snapshot
    └── GET /api/v1/snapshot | /apps | /changes, POST /api/v1/refresh, GET /healthz
                                  ▲
                                  │ HTTPS, header X-Sandbox-Token (Keychain)
                                  │
                       ┌──────────┴──────────┐
                       │    SandboxWatch     │  this repository, on the Mac
                       │  SandboxWatchKit    │
                       │   ├── sbw (CLI)     │
                       │   └── App (SwiftUI) │
                       └──────────┬──────────┘
                                  │ az CLI, Vincent's own credentials, exact argument arrays
                                  ▼
                       start / stop / restart a web app
```

Two transports, two identities, on purpose. Reading uses the sandbox token, which the server has
bounded to a Reader role. Writing uses Vincent's own `az` login. The token can never mutate anything.

## Components

| Component | Responsibility | Depends on |
|---|---|---|
| `SandboxStore` | The YAML inventory (`~/.config/sbw/sandboxes.yaml`). No secrets. | Yams |
| `TokenStore` | The `SANDBOX_TOKEN` per sandbox, in the Keychain. Protocol; mocked in tests. | Security.framework |
| `SandboxAPIClient` | Typed calls on `/api/v1`. Maps every documented status code to a modelled state. | `HTTPClient` |
| `SandboxAPIContract` | The executable half of the API contract. | — |
| `Snapshot` model | Sections whose payload is unreachable without switching on their status. | — |
| `ChangeCursor` | Per-sandbox `(at, type, subject)` cursor, with overflow detection. | — |
| `Doctor` | The five-verdict diagnosis. | `SandboxAPIClient` |
| `AzRunner` | The exact `az` argv, in one place. | `ProcessRunner` |
| `ActionGuards` | The three guards, as values. | `ProcessRunner`, `SandboxAPIClient` |
| `ActionJournal` | Append-only local log of write actions, refusals included. | — |
| `SandboxAction` | One write action end to end: guards, confirmation text, journal. | `ActionGuards`, `AzRunner`, `ActionJournal` |
| `OverviewRow` | One control-center line per sandbox. Counts are optional on purpose. | `WatchPresentation` |
| `SandboxDetail` | A tab's worth of rows, or the reason there are none (`Panel`). | `Snapshot`, `ChangeEvent` |
| `sbw` | Thin CLI over the Kit. | ArgumentParser |
| `App` *(batches 2 and 4)* | Menu bar + control center, links the Kit locally. | SwiftUI |

## Seams

Every side effect goes through a protocol, mocked in tests:

- `HTTPClient` → `URLSessionHTTPClient` (prod) / `MockHTTPClient` (test)
- `TokenStore` → `KeychainTokenStore` (prod) / `InMemoryTokenStore` (test)
- `ProcessRunner` → `SystemProcessRunner` (prod) / `MockProcessRunner` (test)

`swift test` therefore touches no network, no Keychain and no `az`. The two consequences worth
stating plainly: `KeychainTokenStore` and `URLSessionHTTPClient` are the only types no test
executes, so they are proved by use rather than by the suite. This is HomePortManager's pattern
(`ProcessRunner` mocked throughout `HomePortKitTests`), applied to the two kinds of outside world
this project has.

## Two structural decisions

**A section's payload is unreachable without its status.** The server compares two snapshots only
when both collected a section successfully, because a naive diff would announce that every role
assignment vanished at the moment a Reader role is revoked. A client that renders a `denied` section
as "0 role assignments" reintroduces that false alarm from the outside. So the model has no stored
`data` property: the payload lives inside the `.ok` case.

**Write actions are guarded three ways.** Subscription mismatch (`az` points wherever
`az account set` left it), snapshot staleness (up to 10 minutes), and non-interactivity (`az` will
open a device-code flow that hangs forever with no TTY). Each guard is a test, not a convention.

## State on disk

| Path | Contents | Secret |
|---|---|---|
| `~/.config/sbw/sandboxes.yaml` | Inventory: name, URL, notes | no |
| Keychain `fr.lauriat.sandboxwatch` | One token per sandbox | **yes** |
| `~/.config/sbw/cursors/<name>.json` | Last change `sbw changes` reported | no |
| `~/.config/sbw/cursors-watch/<name>.json` | Last change `sbw watch` reported | no |
| `~/.config/sbw/cursors-app/<name>.json` | Last change the app reported | no |
| `~/.config/sbw/liaison/<name>.json` | Confirmed link state for `sbw watch`, for debounce | no |
| `~/.config/sbw/liaison-app/<name>.json` | Confirmed link state for the app | no |
| `~/.config/sbw/actions.jsonl` | Write-action journal, refusals included — **one, shared** | no |

The journal is deliberately *not* split per surface, unlike the cursors and the liaison state. A
cursor is consumed: one reader advancing it robs another. Nobody consumes a journal entry, and the
point is a single record of everything done to the sandbox, whichever surface did it.

### The three guards, in this order

`ActionGuards.check` runs all three before a single `az webapp` process exists, and returns an
`ActionContext` or an `ActionRefusal` — a value, because a refusal is a state the CLI prints and
the app shows in a sheet.

1. **Non-interactivity**, first. `az account show --query id --output tsv --only-show-errors`.
   It is the cheapest and most certain refusal, and nothing should touch the network until `az`
   has proved it can answer at all. Measured 2026-09-18: logged out, this exits 1 with an empty
   stdout and opens no device-code flow.
2. **Freshness.** `POST /api/v1/refresh`, then read *that* response — not the snapshot from before
   it. When the server rate-limits and returns `X-Refresh-Skipped: true`, the flag reaches the
   confirmation prompt. A prompt that hid it would imply freshly verified state, which is the one
   thing this guard exists to guarantee.
3. **Subscription.** The snapshot's `identity.subscriptionId` against what `az` reported. `az`
   points wherever `az account set` last left it, which has nothing to do with the sandbox on
   screen. `--subscription` is then passed explicitly on the action, so the guard checks a value
   it also uses.

The guards run **once** per action. The context the operator confirms against is the context the
action departs against; checking twice would break the promise the second guard makes.


Three readers, three notions of "since I last looked". One shared cursor would let a background
watch consume what a manual `sbw changes` was owed — the surface that reads most often would
silence the others. `SandboxWatcher.poll` therefore takes its `CursorStore` as a parameter and
never picks one itself.

**The liaison store is the same rule, one level up, and it matters more.** `poll` persists its
decision unconditionally, so a shared `liaison/` would let whichever surface polled first confirm
the new state; the second would compare the same set against itself, decide nothing changed, and
stay silent. A missed change event is a nuisance. A missed transition is the founding incident of
this project.
