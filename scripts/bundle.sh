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

codesign --force --options runtime --entitlements Support/Wffl.entitlements -s - "$APP"

echo "Built $APP"
