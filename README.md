# SandboxWatch

**The Mac half of [Azure Sandbox Manager](../AzureSandboxManager).**

Azure Sandbox Manager runs inside the Azure resource group it watches and exposes a snapshot plus an
append-only change log over `/api/v1`. SandboxWatch reads that API from your Mac — a CLI (`sbw`), a
menu bar app that notifies you when something changes while nobody is looking, and a control center
window — and can start, stop or restart the web apps under your own Azure credentials.

The pair mirrors [Homeport](../../RaspberryTools/Homeport) /
[HomePortManager](../../RaspberryTools/HomePortManager): an agent on the machine, a manager on the
Mac.

> **Status: batches 1, A1, A2a and A2b shipped** — `SandboxWatchKit`, the read-only `sbw` CLI,
> `sbw watch`, and a menu bar agent.
> Install the CLI: `swift build -c release && ln -sf "$PWD/.build/release/sbw" ~/.local/bin/sbw`.
> Build and sign the app: `./Scripts/build-app.sh`, then
> `ditto App/stage/SandboxWatch.app ~/Applications/SandboxWatch.app`.
> See [`docs/getting-started.md`](docs/getting-started.md), and
> [`docs/superpowers/specs/2026-09-16-sandboxwatch-design.md`](docs/superpowers/specs/2026-09-16-sandboxwatch-design.md)
> for the design the remaining batches follow.
>
> **Diagrams** (self-contained HTML, open in a browser):
> [architecture](docs/diagrams/architecture.html) ·
> [the `sbw changes` cursor](docs/diagrams/change-cursor.html).

## Planned shape

| Batch | Contents |
|---|---|
| ✅ 1 | `SandboxWatchKit` + read-only CLI: inventory, Keychain, `status`, `doctor`, `changes` |
| ✅ A1 | Transition detection with its debounce, `sbw watch` |
| ✅ A2a | `SandboxWatcher.poll` in the Kit, one change cursor and one liaison state per surface |
| ✅ A2b | Menu bar agent: status icon, notifications on transitions and critical events, FR + EN |
| ✅ B | `start` / `stop` / `restart` via the local `az` CLI, behind three guards, with an append-only journal |
| 4 | Control center window |

## Two things that are not like HomePortManager

- **The transport is a secret.** `hpm`'s `fleet.yaml` holds no secrets because SSH config is the
  transport. Here the `SANDBOX_TOKEN` *is* the transport, so it lives in the Keychain and never in
  the YAML inventory.
- **The server is read-only.** Write actions run under your own `az` login, never under the sandbox
  token — which keeps the server's property intact: holding the token lets you read an inventory and
  change nothing.

## Licence

MIT — see [LICENSE](LICENSE).
