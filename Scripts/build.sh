#!/bin/bash
# Builds MenuBarKeeper.app into build/.
#
#   ./Scripts/build.sh                 build a universal binary (arm64 + x86_64)
#   ./Scripts/build.sh --native        build for this machine only (faster)
#   ./Scripts/build.sh --install       build, then install into /Applications
#   ./Scripts/build.sh --no-sign       build without signing (no keychain access)
#
# Signing strategy (important)
# ----------------------------
# Prefers a local self-signed certificate, "MenuBarKeeper Local Signer". It makes the
# TCC designated requirement
#
#     identifier "io.github.felixastra.MenuBarKeeper" and certificate leaf = H"..."
#
# so rebuilding does not invalidate an existing Accessibility grant. Falling back to
# ad-hoc signing degrades the requirement to a bare cdhash, which changes on every
# rebuild and forces the user to re-authorise each time. Create the certificate once
# with Scripts/make-signing-cert.sh.
set -euo pipefail

NAME="MenuBarKeeper"
SIGN_ID="MenuBarKeeper Local Signer"
BUNDLE_ID="io.github.felixastra.MenuBarKeeper"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/$NAME.app"
DEPLOYMENT_TARGET="14.0"

ARCHS=("arm64" "x86_64")
INSTALL=false
SIGN=true

for arg in "$@"; do
    case "$arg" in
        --native)  ARCHS=("$(uname -m)") ;;
        --install) INSTALL=true ;;
        --no-sign) SIGN=false ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Single source of truth for the version.
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

echo "==> MenuBarKeeper $VERSION (build $BUILD_NUMBER)"

SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find "$ROOT/Sources" -name '*.swift' | sort)
if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "No Swift sources found under $ROOT/Sources" >&2
    exit 1
fi

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling (${ARCHS[*]})"
BINARIES=()
for arch in "${ARCHS[@]}"; do
    out="$ROOT/build/.$NAME-$arch"
    echo "    $arch"
    xcrun swiftc \
        -swift-version 5 \
        -O \
        -target "${arch}-apple-macosx${DEPLOYMENT_TARGET}" \
        -framework AppKit \
        -framework ApplicationServices \
        -o "$out" \
        "${SOURCES[@]}"
    BINARIES+=("$out")
done

if [ ${#BINARIES[@]} -gt 1 ]; then
    echo "==> Merging into a universal binary"
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$NAME"
    rm -f "${BINARIES[@]}"
else
    mv "${BINARIES[0]}" "$APP/Contents/MacOS/$NAME"
fi

echo "==> Assembling the bundle"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$ROOT/Supporting/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Assets and .lproj string tables. The tree is copied recursively so localized folders
# keep their structure. Anything starting with "_" is local-only and skipped.
if [ -d "$ROOT/Resources" ]; then
    for entry in "$ROOT/Resources"/*; do
        [ -e "$entry" ] || continue
        case "$(basename "$entry")" in _*) continue ;; esac
        cp -R "$entry" "$APP/Contents/Resources/"
    done
    echo "    resources: $(ls "$APP/Contents/Resources" | tr '\n' ' ')"
fi

if [ "$SIGN" = true ]; then
    echo "==> Signing"
    if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
        codesign --force --sign "$SIGN_ID" "$APP"
        echo "    identity: $SIGN_ID (Accessibility grants survive rebuilds)"
    else
        codesign --force --sign - "$APP" 2>/dev/null || true
        echo "    WARNING: identity '$SIGN_ID' not found — fell back to ad-hoc signing."
        echo "             Every rebuild will invalidate the Accessibility permission."
        echo "             Create the certificate once: ./Scripts/make-signing-cert.sh"
    fi
    codesign --verify --strict "$APP"
fi

if [ "$INSTALL" = true ]; then
    echo "==> Installing to /Applications"
    # Not cosmetic: the system only protects the menu bar icon of an app installed in a
    # standard location. Run from anywhere else and MenuBarKeeper's own icon gets hidden
    # together with the rest, leaving no controls.
    pkill -f "$NAME.app/Contents/MacOS/$NAME" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/$NAME.app"
    echo "    /Applications/$NAME.app"
    echo "==> Launching"
    open "/Applications/$NAME.app"
else
    echo
    echo "Note: the app must run from /Applications, otherwise its own menu bar icon is"
    echo "hidden along with everything else. Install it with: ./Scripts/build.sh --install"
fi

echo
echo "Bundle:  $APP"
echo "ID:      $BUNDLE_ID"
