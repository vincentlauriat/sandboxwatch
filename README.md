# SandboxWatch

**The Mac half of [Azure Sandbox Manager](../AzureSandboxManager).**

Azure Sandbox Manager runs inside the Azure resource group it watches and exposes a snapshot plus an
append-only change log over `/api/v1`. SandboxWatch reads that API from your Mac — a CLI (`sbw`), a
menu bar app that notifies you when something changes while nobody is looking, and a control center
window — and can start, stop or restart the web apps under your own Azure credentials.

The pair mirrors [Homeport](../../RaspberryTools/Homeport) /
[HomePortManager](../../RaspberryTools/HomePortManager): an agent on the machine, a manager on the
Mac.

> **Status: batch 1 shipped** — `SandboxWatchKit` and a read-only `sbw` CLI.
> Install: `swift build -c release && ln -sf "$PWD/.build/release/sbw" ~/.local/bin/sbw`.
> See [`docs/getting-started.md`](docs/getting-started.md), and
> [`docs/superpowers/specs/2026-09-16-sandboxwatch-design.md`](docs/superpowers/specs/2026-09-16-sandboxwatch-design.md)
> for the design the remaining batches follow.

## Planned shape

| Batch | Contents |
|---|---|
| ✅ 1 | `SandboxWatchKit` + read-only CLI: inventory, Keychain, `status`, `doctor`, `changes` |
| 2 | Transition detection, `sbw watch`, menu bar app, notifications on transition only |
| 3 | `start` / `stop` / `restart` via the local `az` CLI, with subscription, freshness and non-interactivity guards |
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
