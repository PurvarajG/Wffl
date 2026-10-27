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

# Sparkle.framework: linked at @rpath, found through the @executable_path/../Frameworks rpath set in
# Package.swift. SwiftPM puts the binary framework next to the products; fall back to the xcframework
# slice in the package artifacts. ditto keeps the Versions/Current symlinks that code signing needs.
SPARKLE_FRAMEWORK=""
for candidate in ".build/$CONFIG/Sparkle.framework" \
                 .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework; do
  if [ -d "$candidate" ]; then SPARKLE_FRAMEWORK="$candidate"; break; fi
done
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo "error: Sparkle.framework not found under .build/$CONFIG or .build/artifacts" >&2
  exit 1
fi
mkdir -p "$STAGING_APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$STAGING_APP/Contents/Frameworks/Sparkle.framework"

SU_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Support/Info.plist 2>/dev/null || true)"
if [ -z "$SU_PUBLIC_KEY" ] || [ "$SU_PUBLIC_KEY" = "SPARKLE_PUBLIC_ED_KEY_NOT_SET" ]; then
  echo "warning: SUPublicEDKey in Support/Info.plist is not set; this build will not check for updates (see docs/release-signing.md)" >&2
fi
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

# SwiftPM also links absolute rpaths into the build folder (.build/.../PackageFrameworks) ahead of
# the bundle's own. On the Mac that built it, the app would then load Sparkle from .build instead of
# Contents/Frameworks, and a launch test would pass for the wrong reason. Keep exactly one rpath.
# Every other dependency (Swift runtime, system frameworks) is linked by absolute path, not @rpath.
BUNDLE_RPATH="@executable_path/../Frameworks"
list_rpaths() {
  otool -l "$1" | awk '/cmd LC_RPATH/ {f=1; next} f && /^ *path / {sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; f=0}'
}
while IFS= read -r rpath; do
  [ "$rpath" = "$BUNDLE_RPATH" ] || install_name_tool -delete_rpath "$rpath" "$EXE"
done < <(list_rpaths "$EXE")
if [ "$(list_rpaths "$EXE")" != "$BUNDLE_RPATH" ]; then
  echo "error: expected the only rpath in $EXE to be $BUNDLE_RPATH, found:" >&2
  list_rpaths "$EXE" >&2
  exit 1
fi

vtool -set-build-version macos 15.0 "$(xcrun --show-sdk-version)" -replace -output "$EXE.stamped" "$EXE"
mv "$EXE.stamped" "$EXE"

# Finder metadata and resource-fork xattrs make strict code-signature
# verification fail after assets are copied into the bundle.
xattr -cr "$STAGING_APP"

SIGN_ARGS=(--force --options runtime --entitlements Support/Wffl.entitlements)
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  SIGN_ARGS+=(--timestamp)
fi

# Sparkle ships nested code that must be signed inside out with our identity, before the app, and
# without --deep (Sparkle's documented order for a non-sandboxed app). The app's own entitlements
# do not belong on this code, so it gets hardened runtime only.
NESTED_ARGS=(--force --options runtime)
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  NESTED_ARGS+=(--timestamp)
fi
SPARKLE_DEST="$STAGING_APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$(cd "$SPARKLE_DEST/Versions/Current" && pwd -P)"
for xpc in "$SPARKLE_VERSION_DIR"/XPCServices/*.xpc; do
  [ -e "$xpc" ] || continue
  # The Downloader keeps the entitlements Sparkle built it with.
  if [ "$(basename "$xpc")" = "Downloader.xpc" ]; then
    codesign "${NESTED_ARGS[@]}" --preserve-metadata=entitlements -s "$IDENTITY" "$xpc"
  else
    codesign "${NESTED_ARGS[@]}" -s "$IDENTITY" "$xpc"
  fi
done
codesign "${NESTED_ARGS[@]}" -s "$IDENTITY" "$SPARKLE_VERSION_DIR/Autoupdate"
codesign "${NESTED_ARGS[@]}" -s "$IDENTITY" "$SPARKLE_VERSION_DIR/Updater.app"
codesign "${NESTED_ARGS[@]}" -s "$IDENTITY" "$SPARKLE_DEST"

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
