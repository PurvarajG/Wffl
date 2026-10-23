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
# Asset catalog: the layered icon (light/dark/tinted) for macOS 26+ and the graphite AccentColor
# (sidebar selection and focus use it instead of the system blue). AppIcon.icns above stays the
# icon fallback, so a missing or old actool never fails the build.
ASSET_INPUTS=()
[ -d Support/AppIcon.icon ] && ASSET_INPUTS+=(Support/AppIcon.icon)
[ -d Support/Assets.xcassets ] && ASSET_INPUTS+=(Support/Assets.xcassets)
if [ ${#ASSET_INPUTS[@]} -gt 0 ]; then
  ICON_OUT="$STAGING_DIR/assets"
  mkdir -p "$ICON_OUT"
  ICON_ARGS=()
  [ -d Support/AppIcon.icon ] && ICON_ARGS=(--app-icon AppIcon --include-all-app-icons)
  if xcrun actool "${ASSET_INPUTS[@]}" --compile "$ICON_OUT" --output-partial-info-plist "$ICON_OUT/partial.plist" \
       ${ICON_ARGS[@]+"${ICON_ARGS[@]}"} --target-device mac --minimum-deployment-target 15.0 \
       --platform macosx >/dev/null 2>&1 && [ -f "$ICON_OUT/Assets.car" ]; then
    cp "$ICON_OUT/Assets.car" "$STAGING_APP/Contents/Resources/Assets.car"
  else
    echo "warning: could not compile the asset catalog; shipping the .icns icon and the system accent" >&2
  fi
fi

# SwiftPM stamps the deployment target as the SDK version (LC_BUILD_VERSION sdk 15.0). macOS 26+
# then runs the app in compatibility mode: no Liquid Glass sidebar or toolbar. Stamp the SDK the
# binary was really built with, before signing.
EXE="$STAGING_APP/Contents/MacOS/Wffl"
vtool -set-build-version macos 15.0 "$(xcrun --show-sdk-version)" -replace -output "$EXE.stamped" "$EXE"
mv "$EXE.stamped" "$EXE"

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
