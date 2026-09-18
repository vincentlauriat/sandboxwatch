# SandboxWatch 0.1.0

First release: the Mac half of [Azure Sandbox Manager](https://github.com/vincentlauriat/AzureSandboxManager).

## What it does

- **`sbw` CLI** — `sandbox add/list/remove`, `status`, `doctor`, `changes`, `watch`,
  and `start` / `stop` / `restart`.
- **Menu bar agent** — a status icon, one line per sandbox, a poll every five minutes, and
  notifications on a transition or a critical event.
- **Control center** — an overview across sandboxes, then per-sandbox tabs: Summary,
  Apps & probes, Changes, Governance, Budget, Actions.

## The two rules it is built on

**A section that could not be collected is never shown as a zero.** `denied` is exactly what a
revoked Reader role looks like, and rendering it as `0/0 up` or `0%` would say "everything is
fine" at the moment that is least true. Counts are absent instead, everywhere.

**Write actions run under your own `az` login, never under the sandbox token** — which the server
bounds to Reader. Three guards run before a single `az` process exists: `az` must be able to
answer, the snapshot must have just been refreshed, and the subscription `az` points at must be
the one the sandbox watches. Every attempt is appended to `~/.config/sbw/actions.jsonl`, refusals
included.

## Install

Drag SandboxWatch.app to Applications. The app is signed with a Developer ID certificate and
notarized by Apple.

The CLI is built from source: `swift build -c release`, or `./Scripts/build-cli.sh` to sign it —
signing matters because an unsigned binary gets a new code identity on every rebuild, which costs
you a Keychain prompt each time.

## Requirements

macOS 13 or later. The `az` CLI, logged in, for the write actions only.
