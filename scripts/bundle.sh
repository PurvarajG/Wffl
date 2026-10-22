#!/bin/bash
# Build the Wffl executable with SwiftPM and assemble a signed .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"

# A stable identity is required because macOS binds microphone TCC grants to
# the app's signature. Never fall back to ad-hoc signing: it can leave a
# recording session apparently running while CoreAudio delivers zero buffers.
IDENTITY="${WFFL_SIGN_IDENTITY:-Wffl Dev}"
if ! security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  echo "error: required code-signing identity '$IDENTITY' was not found." >&2
  echo "Create a self-signed '$IDENTITY' Code Signing certificate in Keychain Access, then run this script again." >&2
  exit 1
fi

swift build -c "$CONFIG"

BIN=".build/$CONFIG/Wffl"
APP="${WFFL_APP_PATH:-$HOME/Applications/Wffl.app}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wffl-bundle.XXXXXX")"
STAGING_APP="$STAGING_DIR/Wffl.app"
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
cp "$BIN" "$STAGING_APP/Contents/MacOS/Wffl"
cp Support/Info.plist "$STAGING_APP/Contents/Info.plist"
RESOURCE_BUNDLE=".build/$CONFIG/Wffl_Wffl.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  echo "error: missing SwiftPM resource bundle $RESOURCE_BUNDLE" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$STAGING_APP/Contents/Resources/"
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "$STAGING_APP/Contents/Resources/AppIcon.icns"
fi
# Layered icon (light/dark/tinted) for macOS 26+; AppIcon.icns above stays the fallback.
# A missing actool only costs the layered icon, so it never fails the build.
if [ -d Support/AppIcon.icon ]; then
  ICON_OUT="$STAGING_DIR/icon"
  mkdir -p "$ICON_OUT"
  if xcrun actool Support/AppIcon.icon --compile "$ICON_OUT" --output-partial-info-plist "$ICON_OUT/partial.plist" \
       --app-icon AppIcon --include-all-app-icons --target-device mac --minimum-deployment-target 15.0 \
       --platform macosx >/dev/null 2>&1 && [ -f "$ICON_OUT/Assets.car" ]; then
    cp "$ICON_OUT/Assets.car" "$STAGING_APP/Contents/Resources/Assets.car"
  else
    echo "warning: could not compile Support/AppIcon.icon; shipping the .icns icon only" >&2
  fi
fi

# Finder metadata and resource-fork xattrs make strict code-signature
# verification fail after assets are copied into the bundle.
xattr -cr "$STAGING_APP"

SIGN_ARGS=(--force --options runtime --entitlements Support/Wffl.entitlements)
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" -s "$IDENTITY" "$STAGING_APP"
codesign --verify --deep --strict --verbose=2 "$STAGING_APP"

mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
mv "$STAGING_APP" "$APP"
# Moving an app into a Finder-managed folder can attach Finder metadata after
# the staging bundle has been signed. Clear it before the final strict check.
xattr -cr "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built $APP"
