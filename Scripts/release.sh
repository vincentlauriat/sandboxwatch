#!/usr/bin/env bash
# Build, sign, package and notarize SandboxWatch.app as a distributable .dmg.
#
# Usage: ./Scripts/release.sh <version>      e.g. ./Scripts/release.sh 0.1.0
#
# Modelled on MacTools/MarkdownViewer/Scripts/release.sh, minus what does not apply here:
# SandboxWatch has no Sparkle framework, no app extension and no auto-update, so there is no
# EdDSA signing and no appcast. The parts kept are the ones that were learned the hard way there.
#
# Prerequisites, both already in place (verified 2026-09-18):
#   - "Developer ID Application: Vincent LAURIAT (KFLACS69T9)" in the login keychain
#   - notarytool credentials under the keychain profile "AppliMacVincentGithub"
#     (`xcrun notarytool history --keychain-profile "AppliMacVincentGithub"` lists submissions)
#
# Outputs release/SandboxWatch-<version>.dmg, notarized and stapled.
# Does NOT create a git tag or a GitHub release — it prints the command instead.
set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>  (e.g. ./Scripts/release.sh 0.1.0)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/App"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"
SIGNING_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"

cd "$ROOT"

# 1. The version on the tin must be the version in the project.
if ! grep -q "MARKETING_VERSION: \"$VERSION\"" App/project.yml; then
  echo "✗ MARKETING_VERSION in App/project.yml does not match $VERSION" >&2
  grep "MARKETING_VERSION" App/project.yml | sed 's/^/    /' >&2
  exit 1
fi

# 2. Build and sign, through the one script that knows how. Duplicating the signing block is how
# two scripts end up signing with two different identities.
echo "→ Scripts/build-app.sh"
"$ROOT/Scripts/build-app.sh" >/dev/null
APP="$APP_DIR/stage/SandboxWatch.app"
[ -d "$APP" ] || { echo "✗ build-app.sh did not produce $APP" >&2; exit 1; }

# The app is only worth shipping if the suite that describes it passes.
echo "→ swift test"
swift test 2>&1 | grep -aE "Executed [0-9]+ tests, with [0-9]+ failures" | tail -1

RELEASE_DIR="$ROOT/release"
mkdir -p "$RELEASE_DIR"
DMG="$RELEASE_DIR/SandboxWatch-$VERSION.dmg"
rm -f "$DMG"

# 3. The drag-to-install layout: the app on the left, an /Applications alias on the right.
STAGING_DIR="$(mktemp -d)"
LAYOUT="$STAGING_DIR/dmg-layout"
VOLNAME="SandboxWatch $VERSION"
mkdir -p "$LAYOUT"
# `ditto --noextattr` again: lsregister leaves com.apple.provenance xattrs on the build product,
# and they travel into the DMG if copied with cp.
ditto --norsrc --noextattr --noacl "$APP" "$LAYOUT/SandboxWatch.app"
ln -s /Applications "$LAYOUT/Applications"

echo "→ Creating a writable DMG to place the icons"
RW_DMG="$STAGING_DIR/temp.dmg"
hdiutil create -volname "$VOLNAME" -srcfolder "$LAYOUT" \
  -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null

MOUNT=$(hdiutil attach -nobrowse -noverify -noautoopen "$RW_DMG" | awk -F '\t' 'END {print $NF}')
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 100, 740, 460}
        set view_options to the icon view options of container window
        set arrangement of view_options to not arranged
        set icon size of view_options to 128
        set position of item "SandboxWatch.app" of container window to {140, 180}
        set position of item "Applications" of container window to {400, 180}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Flush the .DS_Store the layout was just written into, or the positions are lost.
sync
hdiutil detach "$MOUNT" -quiet

echo "→ Compressing to $DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -rf "$STAGING_DIR"

# 4. Notarize, then staple so the app opens on a machine with no internet.
echo "→ Submitting to Apple (2–5 min)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "→ Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 5. Independent verification. Never trust this script's own success message.
echo
echo "→ Verifying the result rather than trusting the steps above"
# `spctl` goes on the .app, never on the DMG: the DMG carries a stapled ticket but is not itself
# code-signed, so asking it for a signature answers "rejected — no usable signature" on a release
# that is perfectly good. Mount the image and check what a user actually double-clicks.
VERIFY_MOUNT=$(hdiutil attach -nobrowse -noverify -noautoopen "$DMG" | awk -F '\t' 'END {print $NF}')
spctl -a -t exec -vv "$VERIFY_MOUNT/SandboxWatch.app" 2>&1 | sed 's/^/    /'
codesign --verify --deep --strict "$VERIFY_MOUNT/SandboxWatch.app" && echo "    app signature: ok"
hdiutil detach "$VERIFY_MOUNT" -quiet

echo
echo "Built: $DMG"
echo "Release notes go in $RELEASE_DIR/release-notes-$VERSION.md"
echo "Publishing is a separate, deliberate step:"
echo "    gh release create v$VERSION \"$DMG\" --title \"SandboxWatch $VERSION\" --notes-file \"$RELEASE_DIR/release-notes-$VERSION.md\""
