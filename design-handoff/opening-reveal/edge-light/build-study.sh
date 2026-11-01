#!/bin/zsh
set -euo pipefail
study_dir="${0:A:h}"
study_repo="${study_dir:h:h:h}"
study_bundle="/tmp/wffl-edge-light-study/Wffl Edge Light.app"
mkdir -p "$study_bundle/Contents/MacOS" "$study_bundle/Contents/Resources/Resources/Fonts"
# Extract current Ask/Sidebar/toolbar bodies; review fixtures replace services only.
python3 "$study_dir/prepare-native-face.py" "$study_repo" "$study_bundle/Contents/MacOS/NativeAsk.swift"
swiftc -parse-as-library -swift-version 5 -O \
  "$study_dir/ReviewFixtures.swift" "$study_dir/ReviewApp.swift" \
  "$study_dir/ProductStage.swift" \
  "$study_bundle/Contents/MacOS/NativeAsk.swift" \
  "$study_dir/NativeAskFace.swift" \
  "$study_repo/Sources/Wffl/Views/Instruments.swift" \
  "$study_repo/Sources/Wffl/Support/AppFonts.swift" \
  "$study_repo/Sources/Wffl/Support/Theme.swift" \
  "$study_repo/Sources/Wffl/Support/ProcessingDisclosure.swift" \
  "$study_repo/Sources/Wffl/Support/EndpointPolicy.swift" \
  -o "$study_bundle/Contents/MacOS/WfflEdgeLight"
cp "$study_repo/Sources/Wffl/Resources/Fonts/"{HankenGrotesk-Variable,FragmentMono-Regular}.ttf \
   "$study_bundle/Contents/Resources/Resources/Fonts/"
cat > "$study_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WfflEdgeLight</string>
<key>CFBundleIdentifier</key><string>dev.wffl.edge-light-study</string>
<key>CFBundleName</key><string>Wffl Edge Light</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSAccentColorName</key><string>AccentColor</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xcrun actool "$study_repo/Support/Assets.xcassets" \
  --compile "$study_bundle/Contents/Resources" \
  --output-partial-info-plist "${study_bundle:h}/assets.plist" \
  --target-device mac --minimum-deployment-target 15.0 --platform macosx >/dev/null
if [[ "${1:-}" == "--render" ]]; then
  "$study_bundle/Contents/MacOS/WfflEdgeLight" "${@:1}"
else
  open "$study_bundle"
fi
