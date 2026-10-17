#!/bin/bash
# One-time setup: creates a self-signed code-signing identity in your login keychain.
# With it, build-app.sh signs every build the same way, so macOS keeps the app's
# Local Network and Screen Recording permissions across rebuilds.
#
# macOS will ask for your login password (to trust the certificate for code signing),
# and the first build will ask to let codesign use the key: click "Always Allow".
# To undo: delete "MacToCast Local Signing" in Keychain Access.
set -euo pipefail

NAME="MacToCast Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" already exists and is valid."
    exit 0
fi

# A previous run that stopped before the trust step (for example, a cancelled password prompt)
# leaves an untrusted copy; a second copy with the same name would make codesign fail as ambiguous.
for _ in 1 2 3 4 5; do security delete-identity -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1 || break; done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

# The PKCS#12 password only protects the file in the temp folder, which is deleted on exit.
PASS="$(openssl rand -hex 16)"
# -legacy: macOS cannot read the newer PKCS#12 encryption that OpenSSL 3 uses by default.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -passout "pass:$PASS" -out "$TMP/identity.p12"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\""
echo "Done. Rebuild with scripts/build-app.sh."
