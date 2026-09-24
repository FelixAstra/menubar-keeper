#!/bin/bash
# Creates a local self-signed code-signing certificate for MenuBarKeeper (run once).
#
# Why this is needed
# ------------------
# For an ad-hoc signed app, the TCC designated requirement is the binary's `cdhash`.
# Recompiling changes the binary, which changes the cdhash, which orphans the
# Accessibility grant the user already gave — the app then reports "not authorised"
# even though System Settings shows it ticked.
#
# Signing with a fixed certificate changes the requirement to
#
#     identifier "io.github.felixastra.MenuBarKeeper" and certificate leaf = H"..."
#
# which survives rebuilds as long as the certificate and bundle identifier stay the same.
#
# Produces
# --------
#   certificate + private key -> login keychain, identity "MenuBarKeeper Local Signer"
#   cert.pem                  -> Scripts/signing/  (public half only, safe to keep)
#
# The private key never leaves the keychain and is never written into the project.
set -euo pipefail

NAME="MenuBarKeeper Local Signer"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/signing"
KC="$HOME/Library/Keychains/login.keychain-db"
# Only used to shuttle the key through a .p12; the file is deleted right after import.
PASS="mbklocal"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Signing identity already present: $NAME — nothing to do"
    exit 0
fi

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Generating a self-signed certificate (valid for 10 years)"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME/OU=LocalDev" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

echo "==> Exporting and importing into the keychain"
# macOS `security` cannot read OpenSSL 3's default AES-256/PBKDF2, so the legacy PBE
# algorithms have to be requested explicitly.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/cert.p12" \
    -name "$NAME" -passout "pass:$PASS" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1

security import "$WORK/cert.p12" -k "$KC" -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security -A

cp "$WORK/cert.pem" "$OUT/cert.pem"

echo
echo "Done. Signing identity: $NAME"
echo "Public certificate backed up to $OUT/cert.pem (the private key stays in the keychain)."
echo
echo "Note: changing the certificate fingerprint makes macOS treat the app as new, so the"
echo "Accessibility permission has to be granted once more."
