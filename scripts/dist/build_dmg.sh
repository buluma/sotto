#!/usr/bin/env bash
set -euo pipefail

# Package a personal-use app without Developer ID credentials. Set
# SIGNING_IDENTITY to the SHA-1 of the owner's self-signed code-signing
# certificate (optionally with SIGNING_KEYCHAIN) to keep the designated
# requirement stable across builds; otherwise the app is ad-hoc signed.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/Sotto.app}"
DMG_PATH="${2:-$ROOT_DIR/dist/Sotto.dmg}"
[[ -d "$APP_PATH" ]] || { echo "Missing app bundle: $APP_PATH" >&2; exit 1; }
"$ROOT_DIR/scripts/dist/verify_release_version.sh" "$APP_PATH"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
sign_args=(--sign -)
if [[ -n "$SIGNING_IDENTITY" ]]; then
  sign_args=(--sign "$SIGNING_IDENTITY")
  [[ -z "${SIGNING_KEYCHAIN:-}" ]] || sign_args+=(--keychain "$SIGNING_KEYCHAIN")
fi
# No hardened runtime is requested for this personal build.
codesign --force --deep "${sign_args[@]}" --entitlements "$ROOT_DIR/scripts/dist/Sotto.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  EXPECTED_SIGNING_CERT_SHA1="$SIGNING_IDENTITY" "$ROOT_DIR/scripts/dist/verify_app_privacy_surface.sh" "$APP_PATH"
else
  ALLOW_ADHOC_SIGNING=1 "$ROOT_DIR/scripts/dist/verify_app_privacy_surface.sh" "$APP_PATH"
fi
VERIFY_CODE_SIGNATURES=1 "$ROOT_DIR/scripts/dist/verify_meeting_echo_assets.sh" "$APP_PATH"

mkdir -p "$(dirname "$DMG_PATH")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sotto-dmg.XXXXXX")"
TEMP_OUTPUT_DIR="$(mktemp -d "$(dirname "$DMG_PATH")/.sotto-dmg.XXXXXX")"
DMG_BASENAME="$(basename "$DMG_PATH")"
DMG_STEM="${DMG_BASENAME%.dmg}"
trap 'rm -rf "$STAGING_DIR" "$TEMP_OUTPUT_DIR"' EXIT
# Preserve bundle metadata, symlinks, and signatures.
ditto "$APP_PATH" "$STAGING_DIR/$(basename "$APP_PATH")"
ln -s /Applications "$STAGING_DIR/Applications"

# hdiutil can transiently report "Resource busy" on hosted macOS runners.
# Build to a same-volume temporary path so retries never expose a partial DMG
# or replace an existing artifact before verification succeeds.
MAX_CREATE_ATTEMPTS=3
attempt=1
CREATE_LOG="$TEMP_OUTPUT_DIR/hdiutil-create.log"
while (( attempt <= MAX_CREATE_ATTEMPTS )); do
  # Keep .dmg as the final suffix; hdiutil appends it when the suffix is missing.
  TEMP_DMG_PATH="$TEMP_OUTPUT_DIR/$DMG_STEM.attempt-$attempt.dmg"
  if hdiutil create -volname "${DMG_VOLUME_NAME:-Sotto}" -srcfolder "$STAGING_DIR" -format UDZO "$TEMP_DMG_PATH" >"$CREATE_LOG" 2>&1; then
    cat "$CREATE_LOG"
    break
  else
    status=$?
    cat "$CREATE_LOG" >&2
  fi

  if (( attempt == MAX_CREATE_ATTEMPTS )) || ! grep -Fq "Resource busy" "$CREATE_LOG"; then
    exit "$status"
  fi

  echo "hdiutil create reported Resource busy; retrying in ${attempt}s (attempt $((attempt + 1))/$MAX_CREATE_ATTEMPTS)" >&2
  sleep "$attempt"
  ((attempt += 1))
done

hdiutil verify "$TEMP_DMG_PATH"
mv -f "$TEMP_DMG_PATH" "$DMG_PATH"
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
echo "Created $DMG_PATH and SHA-256 checksum"
