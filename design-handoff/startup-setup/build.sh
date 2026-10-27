#!/bin/zsh
# Builds Wffl Setup Study.app from every .swift file in this folder.
#   build.sh                      build, print the app path
#   build.sh --render [args...]   build, then render keyframes into renders/ and renders/compact/
set -eu
ROOT="${0:A:h}"
APP="$ROOT/Wffl Setup Study.app"
FONTS="$ROOT/../../Sources/WfflPrototype/Fonts"

rm -rf "$APP/Contents"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$FONTS/HankenGrotesk-Variable.ttf" "$FONTS/FragmentMono-Regular.ttf" "$APP/Contents/Resources/"
cp "$ROOT/assets/ask-final.png" "$APP/Contents/Resources/"

swiftc -parse-as-library -O -target "$(uname -m)-apple-macos14.0" \
  "$ROOT"/*.swift -o "$APP/Contents/MacOS/SetupStudy"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SetupStudy</string>
  <key>CFBundleIdentifier</key><string>com.wffl.setup-study</string>
  <key>CFBundleName</key><string>Wffl Setup Study</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

printf '%s\n' "$APP"

if [[ "${1:-}" == "--render" ]]; then
  shift
  "$APP/Contents/MacOS/SetupStudy" --render "$ROOT/renders" "$@"
  "$APP/Contents/MacOS/SetupStudy" --render "$ROOT/renders/compact" --compact "$@"
fi
