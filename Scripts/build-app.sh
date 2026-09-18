#!/usr/bin/env bash
# Build and sign SandboxWatch.app. No DMG, no notarization — those belong to batch 4.
#
# Signing is a separate step from `xcodebuild` on purpose: `xcodebuild` in Release trips over the
# com.apple.provenance xattrs lsregister leaves on the build product, and `ditto` to a clean
# staging directory is what gets past them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/App"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
STAGE="$APP/stage"

cd "$APP"
xcodegen generate
xcodebuild -project SandboxWatch.xcodeproj -scheme SandboxWatch -configuration Release \
    -derivedDataPath .dd build CODE_SIGNING_ALLOWED=NO

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto --norsrc --noextattr --noacl .dd/Build/Products/Release/SandboxWatch.app "$STAGE/SandboxWatch.app"

# The Apple timestamp server is intermittently flaky ("A timestamp was expected but was not found").
for attempt in 1 2 3 4 5; do
    if codesign --force --options runtime --timestamp --sign "$IDENTITY" "$STAGE/SandboxWatch.app"; then
        break
    fi
    echo "codesign attempt $attempt failed, retrying…" >&2
    sleep 5
done

codesign --verify --deep --strict "$STAGE/SandboxWatch.app"
codesign -dv --verbose=2 "$STAGE/SandboxWatch.app" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|flags"
echo
echo "Signed: $STAGE/SandboxWatch.app"
echo "Install with: ditto \"$STAGE/SandboxWatch.app\" ~/Applications/SandboxWatch.app"
