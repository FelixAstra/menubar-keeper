#!/bin/bash
# Packages build/MenuBarKeeper.app into a distributable disk image.
#
#   ./Scripts/package-dmg.sh            -> build/MenuBarKeeper-<version>.dmg
#   ./Scripts/package-dmg.sh --build    also run Scripts/build.sh first
#
# The image contains the app plus an "Applications" symlink, so the user drags the app
# across to install it — the layout macOS users expect.
#
# On Gatekeeper: the app is signed ad-hoc or with a local self-signed certificate, and is
# NOT notarized. macOS therefore blocks the first launch when the image was downloaded.
# Users open it once with right-click → Open, or clear the quarantine flag:
#
#     xattr -dr com.apple.quarantine /Applications/MenuBarKeeper.app
#
# Notarization requires a paid Apple Developer account and is deliberately out of scope;
# see docs/TECHNICAL-FINDINGS.md.
set -euo pipefail

NAME="MenuBarKeeper"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/$NAME.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DMG="$ROOT/build/$NAME-$VERSION.dmg"
STAGING="$ROOT/build/dmg"

if [ "${1:-}" = "--build" ]; then
    "$ROOT/Scripts/build.sh" "${@:2}"
fi

if [ ! -d "$APP" ]; then
    echo "Not built yet: $APP" >&2
    echo "Run ./Scripts/build.sh first, or pass --build." >&2
    exit 1
fi

echo "==> Staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
# ditto preserves resource forks, extended attributes and the code signature, which a
# plain cp does not.
ditto "$APP" "$STAGING/$NAME.app"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating the disk image"
hdiutil create \
    -volname "$NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

rm -rf "$STAGING"

echo "==> Verifying"
hdiutil verify "$DMG" >/dev/null
SIZE="$(du -h "$DMG" | cut -f1)"
echo
echo "Disk image: $DMG  ($SIZE)"
echo
echo "Reminder: the app is not notarized. Tell users to right-click → Open the first"
echo "time, or to run: xattr -dr com.apple.quarantine /Applications/$NAME.app"
