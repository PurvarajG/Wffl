#!/bin/bash
# Build the app v2 design prototype (two directions, sample data only) as build/WfflPrototype.app.
#   scripts/prototype.sh                       build, then open it
#   scripts/prototype.sh --build               build only
#   scripts/prototype.sh --direction b ...     build, then open with launch args
#     (--direction a|b  --screen home|summary|transcript|recording  --appearance light|dark  --size 1180x760)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product WfflPrototype
BIN="$(swift build --show-bin-path)"
APP=build/WfflPrototype.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Support/Prototype/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/WfflPrototype" "$APP/Contents/MacOS/WfflPrototype"
cp -R "$BIN/Wffl_WfflPrototype.bundle" "$APP/Contents/Resources/" 2>/dev/null || cp -R "$BIN"/*WfflPrototype*.bundle "$APP/Contents/Resources/"
[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Graphite accent: the sidebar selection takes the app's AccentColor, not the system blue.
xcrun actool Support/Prototype/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 15.0 --target-device mac --output-partial-info-plist /dev/null >/dev/null
# SwiftPM stamps the deployment target as the SDK version (sdk 15.0), which makes macOS 26+
# run the app in compatibility mode: no Liquid Glass. Stamp the SDK it was really built with.
EXE="$APP/Contents/MacOS/WfflPrototype"
vtool -set-build-version macos 15.0 "$(xcrun --show-sdk-version)" -replace -output "$EXE.tmp" "$EXE" 2>/dev/null
mv "$EXE.tmp" "$EXE"
xattr -cr "$APP"
codesign -s - -f --deep "$APP" 2>/dev/null

if [ "${1:-}" != "--build" ]; then open -n "$APP" --args "$@"; fi
