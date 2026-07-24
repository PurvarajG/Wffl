#!/bin/bash
# Create a compressed distributable DMG containing only the signed Wffl app.
set -euo pipefail

APP="${1:?usage: scripts/make-dmg.sh <Wffl.app> <Wffl.dmg>}"
DMG="${2:?usage: scripts/make-dmg.sh <Wffl.app> <Wffl.dmg>}"
[[ -d "$APP" ]] || { echo "error: app bundle not found: $APP" >&2; exit 1; }

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wffl-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP" "$STAGING_DIR/Wffl.app"
hdiutil create -volname Wffl -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG"
