#!/bin/zsh
set -euo pipefail
study_dir="${0:A:h}"
study_repo="${study_dir:h:h:h}"
study_bundle="/tmp/wffl-edge-light-study/Wffl Edge Light.app"
mkdir -p "$study_bundle/Contents/MacOS" "$study_bundle/Contents/Resources/Resources/Fonts"
# Compile current product view bodies verbatim. Only exclude unrelated pages.
python3 - "$study_repo" "$study_bundle/Contents/MacOS/NativeShell.swift" <<'PY'
from pathlib import Path
import sys
repo, destination = map(Path, sys.argv[1:])
source = (repo / 'Sources/Wffl/Views/ContentView.swift').read_text()
nav = source[source.index('enum NavSection:'):source.index('enum MeetingNudgePresentation')]
shell = source[source.index('struct AppShell<'):source.index('// MARK: - Meetings page')]
destination.write_text('import SwiftUI\n' + nav + shell)
PY
swiftc -parse-as-library -swift-version 5 -O \
  "$study_dir/EdgeLightTeaser.swift" "$study_dir/ReviewFixtures.swift" "$study_dir/ReviewApp.swift" \
  "$study_dir/ProductStage.swift" \
  "$study_bundle/Contents/MacOS/NativeShell.swift" \
  "$study_repo/Sources/Wffl/Views/HomeView.swift" \
  "$study_repo/Sources/Wffl/Views/InstrumentComponents.swift" \
  "$study_repo/Sources/Wffl/Support/AppFonts.swift" \
  "$study_repo/Sources/Wffl/Support/Theme.swift" \
  "$study_repo/Sources/Wffl/Support/ProcessingDisclosure.swift" \
  "$study_repo/Sources/Wffl/Support/EndpointPolicy.swift" \
  "$study_repo/Sources/Wffl/Welcome/FilmAnchors.swift" \
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
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "${1:-}" == "--render" ]]; then
  "$study_bundle/Contents/MacOS/WfflEdgeLight" "${@:1}"
else
  open "$study_bundle"
fi
