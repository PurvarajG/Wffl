#!/bin/zsh
set -euo pipefail
preview_dir="${0:A:h}"
preview_repo="${preview_dir:h:h:h}"
preview_bundle="/tmp/wffl-final-opening/Wffl Final Opening.app"
mkdir -p "$preview_bundle/Contents/MacOS" "$preview_bundle/Contents/Resources/Resources/Fonts"
python3 "$preview_dir/../edge-light/prepare-native-face.py" "$preview_repo" "$preview_bundle/Contents/MacOS/NativeAsk.swift"
python3 - "$preview_dir" "$preview_bundle" <<'PY'
from pathlib import Path
import sys
folder, bundle = map(Path, sys.argv[1:])
fixtures = (folder / '../edge-light/ReviewFixtures.swift').resolve().read_text()
fixtures = fixtures.replace('enum PreviewRuntime { static let isRecordingFixture = false }', '''enum PreviewRuntime {
    static let isRecordingFixture = false
    static var forceReduceMotion: Bool { CommandLine.arguments.contains("--reduce-motion") }
}''')
fixtures += '''
// ReadinessNotice is a fixed fixture in this executable. These empty environment
// holders let the unchanged production capture host supply its usual dependencies.
// The production sidebar words its invitation by the coordinator's mode.
extension WelcomeJourneyCoordinator { var mode: WelcomeMode { .film } }
// Setup compiles from production, and its live session names these services. They are inert here:
// the review app injects a fixture session, so none of this runs.
enum TranscriptionEngine: String { case baps, parakeet, whisper }
extension Prefs {
    static var effectiveEngine: TranscriptionEngine { .baps }
    static var effectiveWhisperModel: String { "large-v3-turbo" }
}
struct WhisperModelInfo: Identifiable, Hashable { let id: String; let sizeMB: Int }
@MainActor final class ModelManager: ObservableObject {
    static let shared = ModelManager()
    static let catalog: [WhisperModelInfo] = []
    @Published var downloaded: Set<String> = []
    @Published var progress: [String: Double] = [:]
    @Published var errors: [String: String] = [:]
    func isDownloaded(_ id: String) -> Bool { downloaded.contains(id) }
    func download(_ model: WhisperModelInfo) {}
    func cancelDownload(_ id: String) {}
}
@MainActor final class ParakeetModelManager: ObservableObject {
    enum State: Equatable { case notDownloaded, downloading, ready, failed(String) }
    static let shared = ParakeetModelManager()
    @Published private(set) var state: State = .notDownloaded
    func download() {}
}
@MainActor final class BapsModelManager: ObservableObject {
    enum State: Equatable { case notDownloaded, downloading(Double), loading, ready, failed(String) }
    static let shared = BapsModelManager()
    @Published private(set) var state: State = .notDownloaded
    func download() {}
}
'''
(bundle / 'Contents/MacOS/ReviewFixtures.swift').write_text(fixtures)
face = (folder / '../edge-light/NativeAskFace.swift').resolve().read_text()
(bundle / 'Contents/MacOS/NativeFace.swift').write_text(face[:face.index('@MainActor enum NativeAskCapture')])
PY
swiftc -parse-as-library -swift-version 5 -O \
  "$preview_dir/FinalOpeningApp.swift" \
  "$preview_bundle/Contents/MacOS/NativeAsk.swift" \
  "$preview_bundle/Contents/MacOS/NativeFace.swift" \
  "$preview_bundle/Contents/MacOS/ReviewFixtures.swift" \
  "$preview_repo/Sources/Wffl/Welcome/ProductionOpening/"*.swift \
  "$preview_repo/Sources/Wffl/Views/WelcomeJourneyView.swift" \
  "$preview_repo/Sources/Wffl/Welcome/Setup/"*.swift \
  "$preview_repo/Sources/Wffl/Support/WelcomeMode.swift" \
  "$preview_repo/Sources/Wffl/Support/ResourceBundle.swift" \
  "$preview_repo/Sources/Wffl/Welcome/FilmTimeline.swift" \
  "$preview_repo/Sources/Wffl/Welcome/FilmStage.swift" \
  "$preview_repo/Sources/Wffl/Welcome/FilmScenes.swift" \
  "$preview_repo/Sources/Wffl/Welcome/FilmAnchors.swift" \
  "$preview_repo/Sources/Wffl/Welcome/Legacy/LegacyApp.swift" \
  "$preview_repo/Sources/Wffl/Views/Instruments.swift" \
  "$preview_repo/Sources/Wffl/Support/AppFonts.swift" \
  "$preview_repo/Sources/Wffl/Support/WelcomeOpeningModel.swift" \
  "$preview_repo/Sources/Wffl/Support/Theme.swift" \
  "$preview_repo/Sources/Wffl/Support/ProcessingDisclosure.swift" \
  "$preview_repo/Sources/Wffl/Support/EndpointPolicy.swift" \
  -o "$preview_bundle/Contents/MacOS/WfflFinalOpening"
cp "$preview_repo/Sources/Wffl/Resources/Fonts/"{HankenGrotesk-Variable,FragmentMono-Regular}.ttf "$preview_bundle/Contents/Resources/Resources/Fonts/"
if [[ -d "$preview_repo/Sources/Wffl/Resources/Opening" ]]; then
  mkdir -p "$preview_bundle/Contents/Resources/Resources/Opening"
  cp -R "$preview_repo/Sources/Wffl/Resources/Opening/." "$preview_bundle/Contents/Resources/Resources/Opening/"
fi
cat > "$preview_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WfflFinalOpening</string>
<key>CFBundleIdentifier</key><string>dev.wffl.final-opening-preview</string>
<key>CFBundleName</key><string>Wffl Final Opening</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSAccentColorName</key><string>AccentColor</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xcrun actool "$preview_repo/Support/Assets.xcassets" --compile "$preview_bundle/Contents/Resources" \
  --output-partial-info-plist "${preview_bundle:h}/assets.plist" \
  --target-device mac --minimum-deployment-target 15.0 --platform macosx >/dev/null
if [[ "${1:-}" == "--build-only" ]]; then
  print "Built $preview_bundle"
elif [[ "${1:-}" == "--render" ]]; then
  "$preview_bundle/Contents/MacOS/WfflFinalOpening" "$@"
else
  open "$preview_bundle" --args "$@"
fi
