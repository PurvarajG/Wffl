#!/bin/bash
# Sign a release DMG with Sparkle's EdDSA key and write a one-item appcast.xml next to it.
#
#   scripts/make-appcast.sh <Wffl.dmg> <Wffl.app> <tag> <appcast.xml>
#
# Needs SPARKLE_ED_PRIVATE_KEY (the output of `generate_keys -x`, as a string). Without it the script
# warns and exits 0, which suits local or manual runs. The release workflow never reaches that
# branch: it requires the secret up front and runs --check-key first.
# Optional: SPARKLE_SIGN_UPDATE (path to sign_update), GITHUB_REPOSITORY (default PurvarajG/Wffl).
#
#   scripts/make-appcast.sh --check-key <Support/Info.plist>
#
# Release preflight. Fails unless SUPublicEDKey in the plist is a real key (not the placeholder) and
# SPARKLE_ED_PRIVATE_KEY is the private half of it. Without this a release could ship an app whose
# updater never starts, or a feed signed with a key the app rejects.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--check-key" ]; then
  PLIST="${2:?usage: scripts/make-appcast.sh --check-key <Support/Info.plist>}"
  fail() { echo "::error::$1" >&2; exit 1; }
  [ -f "$PLIST" ] || fail "Info.plist not found: $PLIST (relative paths are from the repo root)."
  PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null || true)"
  if [ -z "$PUBLIC_KEY" ] || [ "$PUBLIC_KEY" = "SPARKLE_PUBLIC_ED_KEY_NOT_SET" ]; then
    fail "SUPublicEDKey in $PLIST is still the placeholder. A release built now could never update itself. Run generate_keys and paste the public key in (docs/release-signing.md, section 6)."
  fi
  [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ] || fail "SPARKLE_ED_PRIVATE_KEY is not set (docs/release-signing.md, section 6)."
  SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
  [ -x "$SIGN_UPDATE" ] || fail "sign_update not found at $SIGN_UPDATE (run swift package resolve first)."

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/wffl-keycheck.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$WORK/key"
  echo "wffl" > "$WORK/probe"
  # 1. Sparkle itself must accept the key and sign with it.
  "$SIGN_UPDATE" --ed-key-file "$WORK/key" "$WORK/probe" > "$WORK/signed" 2>&1 \
    || fail "sign_update could not use SPARKLE_ED_PRIVATE_KEY: $(cat "$WORK/signed")"
  grep -q 'sparkle:edSignature="' "$WORK/signed" || fail "sign_update produced no signature: $(cat "$WORK/signed")"
  # 2. Its public half must be the key baked into the app. A Sparkle key file is base64 of either a
  #    32-byte seed (current format) or 96 bytes, private 64 then public 32 (older format).
  tr -d ' \n\r\t' < "$WORK/key" | base64 -D > "$WORK/key.bin" 2>/dev/null || fail "SPARKLE_ED_PRIVATE_KEY is not base64."
  case "$(wc -c < "$WORK/key.bin" | tr -d ' ')" in
    32)
      # Wrap the seed as PKCS#8 Ed25519 so openssl can derive the public key from it.
      { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'; cat "$WORK/key.bin"; } > "$WORK/key.der"
      DERIVED="$(openssl pkey -inform DER -in "$WORK/key.der" -pubout -outform DER | tail -c 32 | base64)"
      ;;
    96) DERIVED="$(tail -c 32 "$WORK/key.bin" | base64)" ;;
    *) fail "SPARKLE_ED_PRIVATE_KEY decodes to an unexpected length; expected the output of generate_keys -x." ;;
  esac
  [ "$DERIVED" = "$PUBLIC_KEY" ] || fail "SPARKLE_ED_PRIVATE_KEY does not match SUPublicEDKey in $PLIST (key derives $DERIVED). Updates signed by this release would be rejected by every install."
  echo "Sparkle key check passed: SPARKLE_ED_PRIVATE_KEY matches SUPublicEDKey."
  exit 0
fi

DMG="${1:?usage: scripts/make-appcast.sh <Wffl.dmg> <Wffl.app> <tag> <appcast.xml>}"
APP="${2:?usage: scripts/make-appcast.sh <Wffl.dmg> <Wffl.app> <tag> <appcast.xml>}"
TAG="${3:?usage: scripts/make-appcast.sh <Wffl.dmg> <Wffl.app> <tag> <appcast.xml>}"
OUT="${4:?usage: scripts/make-appcast.sh <Wffl.dmg> <Wffl.app> <tag> <appcast.xml>}"
REPO="${GITHUB_REPOSITORY:-PurvarajG/Wffl}"

if [ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  echo "::warning::SPARKLE_ED_PRIVATE_KEY is not set; skipping appcast.xml. This release will not reach existing installs through Sparkle. See docs/release-signing.md." >&2
  exit 0
fi

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
[ -x "$SIGN_UPDATE" ] || { echo "error: sign_update not found at $SIGN_UPDATE" >&2; exit 1; }

PLIST="$APP/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"

KEY_FILE="$(mktemp "${TMPDIR:-/tmp}/wffl-ed-key.XXXXXX")"
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"

# Prints: sparkle:edSignature="..." length="..."
SIGNATURE_ATTRS="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")"
ED_SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE_ATTRS")"
LENGTH="$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<<"$SIGNATURE_ATTRS")"
if [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
  echo "error: could not read the signature from sign_update output: $SIGNATURE_ATTRS" >&2
  exit 1
fi

DMG_URL="https://github.com/$REPO/releases/download/$TAG/$(basename "$DMG")"
NOTES_URL="https://github.com/$REPO/releases/tag/$TAG"
PUB_DATE="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")"

cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Wffl</title>
    <link>https://github.com/$REPO/releases</link>
    <description>Updates for Wffl</description>
    <language>en</language>
    <item>
      <title>Wffl $SHORT_VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <pubDate>$PUB_DATE</pubDate>
      <link>$NOTES_URL</link>
      <description><![CDATA[<p>Wffl $SHORT_VERSION is ready. <a href="$NOTES_URL">Read what changed on GitHub</a>.</p>]]></description>
      <enclosure url="$DMG_URL" length="$LENGTH" type="application/x-apple-diskimage" sparkle:edSignature="$ED_SIGNATURE"/>
    </item>
  </channel>
</rss>
EOF

xmllint --noout "$OUT"
echo "Wrote $OUT for Wffl $SHORT_VERSION ($BUILD)"
