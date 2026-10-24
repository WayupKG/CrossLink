#!/bin/bash
# Creates "CrossLink Local Signing", a self-signed code signing certificate in the login keychain.
# install.sh signs with it when it is there. An ad hoc signature changes with every build, and
# macOS then asks again for the pairing key in the Keychain; with this one "Always Allow" stays.
# Run once per Mac. Only this Mac trusts the signature: it is not for giving the app to others.
set -euo pipefail
name="CrossLink Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
    echo "\"$name\" is already in the login keychain"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
# LibreSSL from macOS: its PKCS#12 uses the ciphers that "security import" reads
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
    -passout pass:crosslink -out "$tmp/identity.p12"
# -T: codesign may use the key; macOS can still ask once, answer "Always Allow"
security import "$tmp/identity.p12" -k "$keychain" -P crosslink -T /usr/bin/codesign
echo "Created \"$name\""
