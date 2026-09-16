# Getting started

## Build

```bash
swift build -c release
ln -sf "$PWD/.build/release/sbw" ~/.local/bin/sbw   # or any writable directory on your PATH
```

`/usr/local/bin` also works but needs `sudo` on a stock macOS. Check what is already writable
on your own PATH before reaching for it:

```bash
echo "$PATH" | tr ':' '\n' | while read -r d; do [ -w "$d" ] && echo "$d"; done
```

The symlink points into `.build/release`, so a later `swift build -c release` updates the
installed command with no second step.

## Declare a sandbox

```bash
sbw sandbox add dev --url https://<app>.azurewebsites.net
# the token is read from stdin, with terminal echo off — paste the SANDBOX_TOKEN app setting
```

The URL and an optional note go to `~/.config/sbw/sandboxes.yaml`. The token goes to the
Keychain, under the service `fr.lauriat.sandboxwatch`. Nothing secret is written to disk in
readable form, and the token never appears as a command-line argument — which would put it in
your shell history and in the process table.

## Look

```bash
sbw status --all        # age, apps, budget, which sections collected
sbw doctor dev          # why a sandbox is not answering the way you expect
sbw changes dev         # what changed since the last time you ran this
```

## Reading `doctor`

| What it says | What it means |
|---|---|
| the app could not be reached | the web app is down, or the URL is wrong |
| the token was refused | the Keychain holds the wrong token |
| has not completed a collection yet | the app is up and working — wait, do not redeploy |
| these sections did not collect | the Reader role is missing **or was granted recently**: role membership is cached, and Microsoft documents up to 24 hours before it takes effect |
| the snapshot is N minutes old | the collector has stalled; what you see is old |

The third and fourth rows are why this command exists. Both look like a broken deployment and
neither is one.

## Reading `changes`

Events are newest first. `!!` marks a collector losing or regaining access — the incident this
whole project exists for. `!` marks role, lock and budget changes.

Each run moves a cursor, so the next run shows only what is new. `--keep-cursor` looks without
moving it.

If a line says *older events were not returned*, more happened than the server would return in
one page: some events are missing from the output. It is a signal, not an error — the
alternative would be losing them silently.

## What a denied section looks like

A section the server could not collect shows as `denied`, never as an empty result. `sbw status`
prints `denied` in that column rather than `0/0 up` or `0%`. This is deliberate: reading a
revoked Reader role as "zero role assignments" is the false alarm Azure Sandbox Manager was
built to prevent, and undoing it in the client would defeat the point.
