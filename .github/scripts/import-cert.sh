#!/bin/bash
set -euo pipefail

if [ -z "${DEVELOPER_ID_CERT_BASE64:-}" ]; then
  echo "DEVELOPER_ID_CERT_BASE64 is required" >&2
  exit 1
fi

if [ -z "${DEVELOPER_ID_CERT_PASSWORD:-}" ]; then
  echo "DEVELOPER_ID_CERT_PASSWORD is required" >&2
  exit 1
fi

KEYCHAIN_PATH="$RUNNER_TEMP/build.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
CERT_PATH="$RUNNER_TEMP/developer-id-certificate.p12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > "$CERT_PATH"
security import "$CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$DEVELOPER_ID_CERT_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"

security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')
rm -f "$CERT_PATH"

echo "KEYCHAIN_PATH=$KEYCHAIN_PATH" >> "$GITHUB_ENV"
