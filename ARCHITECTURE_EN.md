# Architecture — SandboxWatch

Source of truth. `ARCHITECTURE.md` is its French mirror and must be edited in the same turn.

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
| `AzRunner` | `az` invocation with the three guards. | `ProcessRunner`, `SandboxAPIClient` |
| `ActionJournal` | Append-only local log of write actions. | — |
| `sbw` | Thin CLI over the Kit. | ArgumentParser |
| `App` | Menu bar + control center, links the Kit locally. | SwiftUI |

## Seams

Every side effect goes through a protocol, mocked in tests:

- `HTTPClient` → `URLSessionHTTPClient` (prod) / `MockHTTPClient` (test)
- `ProcessRunner` → `SystemProcessRunner` (prod) / `MockProcessRunner` (test)
- `TokenStore` → `KeychainTokenStore` (prod) / `InMemoryTokenStore` (test)

`swift test` therefore touches no network, no Keychain and no `az`. This is HomePortManager's pattern
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
| `~/.config/sbw/cursors/<name>.json` | Last change seen | no |
| `~/.config/sbw/actions.jsonl` | Write-action journal | no |
