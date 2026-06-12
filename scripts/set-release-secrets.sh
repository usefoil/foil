#!/bin/bash
set -euo pipefail

REPO="${REPO:-usefoil/foil}"
CERT_DIR="${CERT_DIR:-$HOME/Desktop/apple-developer-certificates}"
P12_PATH="${P12_PATH:-$CERT_DIR/DeveloperIDApplication-B3A6AN2HA4.p12}"
ISSUER_ID_PATH="${ISSUER_ID_PATH:-$CERT_DIR/issuer_id}"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-$CERT_DIR/AuthKey_99GHUYUVPF.p8}"
SPARKLE_PRIVATE_ED_KEY_PATH="${SPARKLE_PRIVATE_ED_KEY_PATH:-$CERT_DIR/SparkleEdDSAPrivateKey}"
SPARKLE_PUBLIC_ED_KEY_PATH="${SPARKLE_PUBLIC_ED_KEY_PATH:-$CERT_DIR/SparkleEdDSAPublicKey}"
TEAM_ID="${APPLE_TEAM_ID:-B3A6AN2HA4}"
KEY_ID="${APP_STORE_CONNECT_KEY_ID:-99GHUYUVPF}"

require_file() {
  if [ ! -f "$1" ]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_file "$P12_PATH"
require_file "$ISSUER_ID_PATH"
require_file "$PRIVATE_KEY_PATH"
require_file "$SPARKLE_PRIVATE_ED_KEY_PATH"
require_file "$SPARKLE_PUBLIC_ED_KEY_PATH"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: brew install gh" >&2
  exit 1
fi

gh auth status >/dev/null

read -r -s -p "Developer ID .p12 password: " CERT_PASSWORD
printf '\n'

if [ -z "$CERT_PASSWORD" ]; then
  echo "Certificate password cannot be empty" >&2
  exit 1
fi

if ! openssl pkcs12 -legacy -in "$P12_PATH" -nokeys -passin "pass:$CERT_PASSWORD" >/dev/null 2>&1; then
  echo "Could not open Developer ID .p12 with the provided password" >&2
  exit 1
fi

SPARKLE_PUBLIC_ED_KEY="$(tr -d '\r\n' < "$SPARKLE_PUBLIC_ED_KEY_PATH")"
if ! printf '%s' "$SPARKLE_PUBLIC_ED_KEY" | base64 --decode | wc -c | grep -Eq '^[[:space:]]*32$'; then
  echo "Sparkle public EdDSA key must be a base64-encoded 32-byte key: $SPARKLE_PUBLIC_ED_KEY_PATH" >&2
  exit 1
fi

base64 -i "$P12_PATH" | gh secret set DEVELOPER_ID_CERT_BASE64 --repo "$REPO"
printf '%s' "$CERT_PASSWORD" | gh secret set DEVELOPER_ID_CERT_PASSWORD --repo "$REPO"
printf '%s' "$TEAM_ID" | gh secret set APPLE_TEAM_ID --repo "$REPO"
printf '%s' "$KEY_ID" | gh secret set APP_STORE_CONNECT_KEY_ID --repo "$REPO"
tr -d '\r\n' < "$ISSUER_ID_PATH" | gh secret set APP_STORE_CONNECT_ISSUER_ID --repo "$REPO"
gh secret set APP_STORE_CONNECT_PRIVATE_KEY --repo "$REPO" < "$PRIVATE_KEY_PATH"
printf '%s' "$SPARKLE_PUBLIC_ED_KEY" | gh secret set SPARKLE_PUBLIC_ED_KEY --repo "$REPO"
tr -d '\r\n' < "$SPARKLE_PRIVATE_ED_KEY_PATH" | gh secret set SPARKLE_PRIVATE_ED_KEY --repo "$REPO"

echo "Release secrets set for $REPO"
