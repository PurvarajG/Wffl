#!/bin/zsh
set -euo pipefail
study_dir="${0:A:h}"
study_repo="${study_dir:h:h}"
study_bundle="/tmp/wffl-opening-study/Wffl Motion Study.app"
mkdir -p "$study_bundle/Contents/MacOS"
swiftc -parse-as-library -swift-version 5 -O \
  "$study_dir/DemolitionScene.swift" "$study_dir/StudyApp.swift" \
  "$study_dir/KeynoteTypography.swift" \
  "$study_repo/Sources/Wffl/Support/AppFonts.swift" \
  "$study_repo/Sources/Wffl/Welcome/Legacy/LegacyApp.swift" \
  "$study_repo/Sources/Wffl/Welcome/FilmAnchors.swift" \
  -o "$study_bundle/Contents/MacOS/WfflOpeningStudy"
mkdir -p "$study_bundle/Contents/Resources/Resources/Fonts"
cp "$study_repo/Sources/Wffl/Resources/Fonts/HankenGrotesk-Variable.ttf" \
   "$study_repo/Sources/Wffl/Resources/Fonts/FragmentMono-Regular.ttf" \
   "$study_bundle/Contents/Resources/Resources/Fonts/"
cat > "$study_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WfflOpeningStudy</string>
<key>CFBundleIdentifier</key><string>dev.wffl.opening-study</string>
<key>CFBundleName</key><string>Wffl Motion Study</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "${1:-}" == "--render" ]]; then
  "$study_bundle/Contents/MacOS/WfflOpeningStudy" --render "${@:2}"
else
  open "$study_bundle"
fi
