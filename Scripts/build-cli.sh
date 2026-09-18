#!/usr/bin/env bash
# Build `sbw` in release and sign it with the stable Developer ID identity.
#
# Why signing a local CLI matters here: the Keychain ACL on the sandbox token is keyed on the
# binary's designated requirement. A SwiftPM binary is unsigned, so every `swift build -c release`
# produces a new identity, the ACL no longer matches, and the next `sbw` call blocks on a
# SecurityAgent dialog — which, in a non-interactive shell, means it blocks forever.
#
# Measured 2026-09-18 on the app: same identity and identifier -> one prompt ever, then 0.02 s.
# Change either and macOS asks again.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
# Fixed, and never changed for the same reason PRODUCT_BUNDLE_IDENTIFIER is fixed for the app.
IDENTIFIER="fr.lauriat.sbw"

cd "$ROOT"
swift build -c release

codesign --force --sign "$IDENTITY" --identifier "$IDENTIFIER" .build/release/sbw
codesign --verify --strict .build/release/sbw
codesign -dv --verbose=2 .build/release/sbw 2>&1 | grep -E "Identifier|Authority=Developer|TeamIdentifier"
echo
echo "Signed: $ROOT/.build/release/sbw"
