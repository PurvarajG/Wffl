#!/bin/bash
# Create a compressed distributable DMG containing the signed Wffl app plus an
# /Applications symlink, so the mounted volume shows the usual drag-to-install
# layout instead of a lone app icon.
set -euo pipefail

APP="${1:?usage: scripts/make-dmg.sh <Wffl.app> <Wffl.dmg>}"
DMG="${2:?usage: scripts/make-dmg.sh <Wffl.app> <Wffl.dmg>}"
[[ -d "$APP" ]] || { echo "error: app bundle not found: $APP" >&2; exit 1; }

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wffl-dmg.XXXXXX")"
RW_DMG="$(mktemp -u "${TMPDIR:-/tmp}/wffl-dmg-rw.XXXXXX").dmg"
MOUNT_POINT=""
cleanup() {
  [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] && hdiutil detach "$MOUNT_POINT" -quiet -force 2>/dev/null || true
  rm -rf "$STAGING_DIR" "$RW_DMG"
}
trap cleanup EXIT

ditto "$APP" "$STAGING_DIR/Wffl.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Build a writable image first so the Finder window layout (icon positions,
# window size) can be baked into the volume's .DS_Store before compressing.
hdiutil create -volname Wffl -srcfolder "$STAGING_DIR" -ov -format UDRW \
  -fs HFS+ "$RW_DMG" >/dev/null

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/wffl-dmg-mnt.XXXXXX")"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

# Best-effort: a headless CI runner may have no Finder to script. The symlink
# above is what actually makes the install gesture possible; the layout is
# cosmetic, so never fail the build over it.
osascript <<EOF >/dev/null 2>&1 || echo "note: skipped Finder window layout" >&2
tell application "Finder"
  tell disk "Wffl"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 800, 550}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "Wffl.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
