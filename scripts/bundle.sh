#!/bin/bash
# Build the Meetily executable with SwiftPM and assemble a signed .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Meetily"
APP="dist/Meetily.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Meetily"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --options runtime --entitlements Support/Meetily.entitlements -s - "$APP"

echo "Built $APP"
