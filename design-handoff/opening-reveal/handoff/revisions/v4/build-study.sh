#!/bin/zsh
set -euo pipefail
study_dir="${0:A:h}"
study_repo="${study_dir:h:h:h}"
study_bundle="/tmp/wffl-handoff-study/Wffl Handoff.app"
mkdir -p "$study_bundle/Contents/MacOS" "$study_bundle/Contents/Resources/Resources/Fonts"
python3 "$study_dir/../edge-light/prepare-native-face.py" "$study_repo" "$study_bundle/Contents/MacOS/NativeAsk.swift"
python3 "$study_dir/prepare-study.py" "$study_repo" "$study_bundle/Contents/MacOS"
xcrun -sdk macosx metal -c "$study_dir/PixelHandoff.metal" -o "${study_bundle:h}/PixelHandoff.air"
xcrun -sdk macosx metallib "${study_bundle:h}/PixelHandoff.air" -o "$study_bundle/Contents/Resources/default.metallib"
swiftc -parse-as-library -swift-version 5 -O \
  "$study_dir/RadialHandoff.swift" "$study_dir/PixelHandoff.swift" "$study_dir/HandoffApp.swift" "$study_dir/HandoffHost.swift" \
  "$study_dir/../edge-light/ReviewFixtures.swift" \
  "$study_bundle/Contents/MacOS/NativeAsk.swift" "$study_bundle/Contents/MacOS/NativeTour.swift" \
  "$study_repo/Sources/Wffl/Welcome/FilmTimeline.swift" \
  "$study_repo/Sources/Wffl/Views/Instruments.swift" \
  "$study_repo/Sources/Wffl/Support/AppFonts.swift" \
  "$study_repo/Sources/Wffl/Support/Theme.swift" \
  "$study_repo/Sources/Wffl/Support/ProcessingDisclosure.swift" \
  "$study_repo/Sources/Wffl/Support/EndpointPolicy.swift" \
  -o "$study_bundle/Contents/MacOS/WfflHandoff"
cp "$study_repo/Sources/Wffl/Resources/Fonts/"{HankenGrotesk-Variable,FragmentMono-Regular}.ttf \
  "$study_bundle/Contents/Resources/Resources/Fonts/"
cat > "$study_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WfflHandoff</string>
<key>CFBundleIdentifier</key><string>dev.wffl.handoff-study</string>
<key>CFBundleName</key><string>Wffl Handoff</string>
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
if [[ "${1:-}" == "--build-only" ]]; then
  print "Built $study_bundle"
elif [[ "${1:-}" == "--render" ]]; then
  "$study_bundle/Contents/MacOS/WfflHandoff" "${@:1}"
else
  open "$study_bundle"
fi
