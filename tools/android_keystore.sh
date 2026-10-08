#!/usr/bin/env bash
# Generate the Alfaeq Yemen Android release keystore and print the values that
# must be stored as GitHub Actions secrets.
#
# The keystore and its passwords must NEVER be committed. This script writes the
# keystore to android/app/ (git-ignored) and prints a base64 copy for the
# ANDROID_KEYSTORE_BASE64 secret.
#
# Required secrets on the repository:
#   ANDROID_KEYSTORE_BASE64    base64 of the .jks file
#   ANDROID_KEYSTORE_PASSWORD  store password
#   ANDROID_KEY_ALIAS          key alias (default: alfaeq)
#   ANDROID_KEY_PASSWORD       key password (usually same as store password)
#
# Usage:
#   tools/android_keystore.sh [alias]
set -euo pipefail

ALIAS="${1:-alfaeq}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYSTORE="$REPO_ROOT/android/app/alfaeq-release.jks"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install a JDK (e.g. 'apt-get install -y default-jdk') and retry." >&2
  exit 1
fi

if [[ -f "$KEYSTORE" ]]; then
  echo "Keystore already exists at $KEYSTORE" >&2
  echo "Refusing to overwrite: losing it would make existing releases unupdatable." >&2
  exit 1
fi

mkdir -p "$(dirname "$KEYSTORE")"

if [[ -n "${ANDROID_KEYSTORE_PASSWORD:-}" ]]; then
  STORE_PASS="$ANDROID_KEYSTORE_PASSWORD"
  KEY_PASS="${ANDROID_KEY_PASSWORD:-$ANDROID_KEYSTORE_PASSWORD}"
else
  read -r -s -p "Keystore password: " STORE_PASS; echo
  read -r -s -p "Key password (Enter = same): " KEY_PASS; echo
  KEY_PASS="${KEY_PASS:-$STORE_PASS}"
fi

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$STORE_PASS" -keypass "$KEY_PASS" \
  -dname "CN=Alfaeq Yemen, OU=Mobile, O=Alfaeq Yemen, L=Sanaa, C=YE"

echo
echo "Keystore created: $KEYSTORE"
echo "Store the following as GitHub Actions secrets (Settings > Secrets and variables > Actions):"
echo
echo "ANDROID_KEY_ALIAS=$ALIAS"
echo "ANDROID_KEYSTORE_PASSWORD=<the store password you entered>"
echo "ANDROID_KEY_PASSWORD=<the key password you entered>"
echo
echo "ANDROID_KEYSTORE_BASE64="
base64 -w0 "$KEYSTORE"
echo
echo
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "Tip: push the secrets with"
  echo "  base64 -w0 \"$KEYSTORE\" | gh secret set ANDROID_KEYSTORE_BASE64"
  echo "  gh secret set ANDROID_KEYSTORE_PASSWORD --body \"\$STORE_PASS\""
  echo "  gh secret set ANDROID_KEY_ALIAS --body \"$ALIAS\""
  echo "  gh secret set ANDROID_KEY_PASSWORD --body \"\$KEY_PASS\""
fi
