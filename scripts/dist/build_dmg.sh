#!/usr/bin/env bash
set -euo pipefail

# Package a personal-use, ad-hoc-signed app without Developer ID credentials.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/Sotto.app}"
DMG_PATH="${2:-$ROOT_DIR/dist/Sotto.dmg}"
[[ -d "$APP_PATH" ]] || { echo "Missing app bundle: $APP_PATH" >&2; exit 1; }
"$ROOT_DIR/scripts/dist/verify_release_version.sh" "$APP_PATH"

# No hardened runtime is requested for this personal ad-hoc build.
codesign --force --deep --sign - --entitlements "$ROOT_DIR/scripts/dist/Sotto.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
ALLOW_ADHOC_SIGNING=1 "$ROOT_DIR/scripts/dist/verify_app_privacy_surface.sh" "$APP_PATH"
VERIFY_CODE_SIGNATURES=1 "$ROOT_DIR/scripts/dist/verify_meeting_echo_assets.sh" "$APP_PATH"

mkdir -p "$(dirname "$DMG_PATH")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sotto-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
# Preserve bundle metadata, symlinks, and signatures.
ditto "$APP_PATH" "$STAGING_DIR/$(basename "$APP_PATH")"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "${DMG_VOLUME_NAME:-Sotto}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
echo "Created $DMG_PATH and SHA-256 checksum"
