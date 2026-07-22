#!/bin/bash
# Build the Wffl executable with SwiftPM and assemble a signed .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Wffl"
APP="dist/Wffl.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wffl"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Sign with a stable identity so TCC permissions (mic, etc.) survive reinstalls.
# Ad-hoc (-s -) changes identity every build, forcing permission re-grants.
IDENTITY="${WFFL_SIGN_IDENTITY:-Wffl Dev}"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --options runtime --entitlements Support/Wffl.entitlements -s "$IDENTITY" "$APP"
else
  echo "warning: signing identity '$IDENTITY' not found; falling back to ad-hoc (permissions will reset on reinstall)" >&2
  codesign --force --options runtime --entitlements Support/Wffl.entitlements -s - "$APP"
fi

echo "Built $APP"
