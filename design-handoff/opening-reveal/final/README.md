# Final release What's New — 26 October 2026

The current native release sequence combines the photographic TV push/pullback, full-window static, original correction and five-second Introducing Wffl with the existing user-controlled feature tour. After Your Mac, equal-sized textured cubes fall, collide and tumble to expose the fixed live Ask interface. The current falling-cube study v8 supplies the geometry, physics and motion; no movie is played inside the application.

The automatic opening lasts 20.1 seconds and stops when the tour appears. Scroll or use arrow keys to explore and reverse the tour/reveal. Space pauses the opening or advances the tour. Skip completes the update; Escape interrupts. Reduced Motion uses manual stills and finishes directly in Ask. Release acknowledgement, replay and busy-state policies retain the existing coordinator.

The 120 Hz physics bake runs off the main actor, with cancellation and readiness gating. During resize, the active cube scene stays visible while the new source image and a separate pending surface are prepared; the replacement takes over at the current progress. Only the outgoing page is captured. The real application remains live underneath and receives focus when the overlay is removed.

Build and launch the isolated review app:

```sh
zsh design-handoff/opening-reveal/final/build-preview.sh --build-only
open '/tmp/wffl-final-opening/Wffl Final Opening.app'
```

Review arguments: `--paused`, `--controls`, `--light`, `--compact`, `--reduce-motion`. The Opening Review menu supports replay, phase jumps and both window sizes. Fixtures are confined to this review executable; it does not link recording, database or model services.

Export the complete native sequence (the review driver supplies tour/reveal progress):

```sh
zsh design-handoff/opening-reveal/final/build-preview.sh --render --movie --draft-30fps
ffmpeg -framerate 30 \
  -i design-handoff/opening-reveal/final/renders/final-release-v1/dark-1100/frame-%04d.png \
  -c:v libx264 -crf 14 -preset medium -pix_fmt yuv420p -movflags +faststart \
  -y design-handoff/opening-reveal/final/final-release-v1.mp4
python3 design-handoff/opening-reveal/final/verify-frames.py \
  --movie design-handoff/opening-reveal/final/final-release-v1.mp4
```

Full-sequence captures use `renders/final-release-v1/`; the verifier writes `verification-final-release-v1.json`. Capture requires an unlocked Mac and serial native window export. The expected review movie is 48.3 seconds at 2200×1400, 30 fps. Old clips, their capture evidence and the rough-frame note below remain historical records.

## Final verification

- The final isolated preview builds, and all 34 selected welcome/film tests pass. The focused source review has no remaining material findings. Logs are `final-release-build.log`, `final-release-tests.log` and `final-release-source-review.md`.
- Four native matrix runs produced 112 keyframes covering dark/light at 1100×700 and 900×560. Every source-to-rest interior comparison exceeds 99.999% within two RGB levels; exact frame equality is not claimed.
- `final-release-v1.mp4` contains 1,449 native frames, 1,256 distinct PNGs, 2200×1400 at 30 fps, duration 48.3 seconds. Metadata, frame ordering/dimensions and complete movie decode pass. The frame scan finds no premature Ask captures.
- All 30 final-hold frames match the uncovered Ask page below the native control region within two RGB levels. Native toolbar/sidebar selection activation changes during that hold: 13 whole frames match within one level, and seven whole frames are pixel-identical to the final uncovered Ask capture. This is recorded explicitly in `verification-final-release-v1.json`; whole-frame equality across the entire hold is not claimed.
- Actual native wheel/keyboard input, reverse travel back into the tour, mid-reveal resize, Skip, Escape, replay, focus restoration, search-field typing/clearing and compact light Reduced Motion completion were checked. The packaged preview's automatic opening reached the first tour page at 0% and stayed there awaiting input. Details are in `native-interaction-checks.md`.
- The approved V5 opening movie, standalone v8 renderer/movie and opening asset hashes are unchanged. The packaged binary matches the binary used for export. The user library and installed application were not used for review.

Runnable delivery: `built/Wffl Release Preview.app`. It is a separate review build with inert fixtures; the same integration is present in the production Swift sources. A first reveal keeps its outgoing page visible while its background physics bake prepares. Native capture still requires an unlocked Mac.

---

# CRT pullback opening preview, 26 October 2026

The approved TV push remains 0.5–8.5 seconds, followed by the quick pullback to a wider view by 8.9 seconds. Full-window static runs 8.9–9.5 seconds; the original correction copy plays full-screen at its original 5.6-second cadence through 15.1 seconds. The TV is absent during static, correction, and Introducing; no TNT or explosion renderer remains in production.

`Introducing Wffl` now has a 5-second slow–fast–slow motion curve. It eases through the opening 1.25 seconds, accelerates from 1.25–2.55 seconds, then settles more slowly for the remaining 2.45 seconds. Existing typography, logo, and layout are preserved. The opening sequence is 20.1 seconds; the preview includes a 0.5-second feature-tour entry.

Current review build: `/tmp/wffl-final-opening/Wffl Final Opening.app`. Build with `zsh design-handoff/opening-reveal/final/build-preview.sh --build-only`. Export with `zsh design-handoff/opening-reveal/final/build-preview.sh --render --opening-only --movie --draft-30fps`; current frames are in `renders/photo-tv-v5/dark-1100/` and the clip is `photo-tv-opening-v5.mp4`.

The v5 review clip contains 618 native 2200×1400 frames at 30 fps, H.264, duration 20.6 seconds. All PNGs have identical dimensions. The complete movie decode passed. The early sequence, including the former anomalous v4 frame time at 2.333 seconds, shows the TV consistently. Intro keyframes include `frame-0490.png` (16.333s, early motion), `frame-0530.png` (17.667s, after the faster phase), and `frame-0600.png` (20.0s, settled mark); native named stills are also saved in the same directory.

Rough-frame note: the v4 PNG `frame-0070.png` at 2.333 seconds showed the live Ask interface, while adjacent `frame-0069.png` and `frame-0071.png` showed the TV. They all had the same 2200×1400 dimensions. The v4 exporter did not record which capture method supplied each frame, so the cause of that v4 anomaly is unconfirmed. The first v5 movie also had three bad frames: `frame-0497.png`, `frame-0498.png`, and `frame-0562.png` showed Ask at ScreenCaptureKit failure times. Those frames came from an AppKit bitmap fallback that captured the window's content view but omitted the production welcome overlay attached above it. The fallback has been removed. The three frames were recaptured from the native window with ScreenCaptureKit, checked against adjacent frames, then the v5 movie was re-encoded and fully decoded. The current v5 sequence has no Ask frame at those points; its frame 0070 also shows the TV. The production app was not checked for either capture anomaly.


# Prior native Wffl opening review (historical)

The following notes document an earlier revision and are retained as historical context.

26 October 2026. Implements the approved `../FINAL-STITCH-HANDOFF.md` in the existing application. The original studies remain intact.

## Delivery and playback

`built/Wffl Final Opening.app` is a separate runnable review app. It uses current native product views with inert sample data and has its own bundle identifier, `dev.wffl.final-opening-preview`. It does not link the recording, database, model-download or library services. The installed Wffl application is separate.

The opening plays the revision 14 legacy demolition/introduction for 22.65 seconds, followed by the selected dark 10.8-second 3D teaser. It then stops at the settled Silence page. Scroll or use the arrow keys to explore Silence, Voice, Voices, Minutes and Your Mac, including backward travel. Further input cuts and folds the current page into live Ask. Space pauses/resumes the automatic opening; in the tour it advances. Skip finishes; Escape interrupts.

Reduced Motion offers manual opening and feature stills with Back/Next and direct completion from Your Mac to Ask. The preview's `Opening Review` menu provides replay, phase jumps and the two review sizes. Its shortcuts are Command–Option–1 through 7 in menu order. Those menu items and the optional review control panel are absent from the production application.

## Native integration

- `Sources/Wffl/Support/WelcomeOpeningModel.swift` coordinates the automatic opening, input-driven tour and reversible fold. The automatic clock never advances the feature tour.
- `Sources/Wffl/Views/ContentView.swift` preserves the welcome coordinator and acknowledgement policy and prepares the real Ask route beneath the opening. Starting recording or explicitly importing interrupts the welcome rather than obscuring that work.
- `Sources/Wffl/Welcome/ProductionOpening/WelcomeWindowOverlay.swift` installs the native overlay above the complete content area, including its toolbar. The underlying app stays in its final layout. Removing the overlay restores the previous native focus after SwiftUI teardown.
- `WelcomeFoldHost.swift` owns SwiftUI and SceneKit as siblings. It captures the actual outgoing native window once, hides the outgoing host, and scrubs the approved v5 hinged geometry over the live app. Reversal uses the same captured faces. Resize refreshes the settled outgoing page at the new viewport through an occluded native window, without photographing the exposed Ask or flattening the visible fold. Capture jobs are cancelled when superseded or removed.
- `OpeningNativeAskCapture.swift` builds the teaser's dark native texture from the current Sidebar, WindowToolbar, AskHome and real app/readiness state. It supplies the normal model-manager environment and closes its temporary occluded window after capture.
- The demolition, correction, brand, typography, product geometry and panel renderer are approved source copies with provenance comments. The stale v13 demolition movie is never played. The accepted restoration, 0.75-second hold, TNT placement and 16.05-second detonation remain unchanged.

The native Record toolbar item now declares its flexible spacing on macOS 26+, keeping its position stable through the handover. The tour's Minutes copy calls the current destination Ask. Fonts, logo, feature scenes and qualified privacy copy otherwise retain their existing implementations.

## Build and reproduce

From the repository root:

```sh
swift build
swift test --filter 'WelcomeJourneyTests|UpdateFilmTests'
zsh design-handoff/opening-reveal/final/build-preview.sh --build-only
open '/tmp/wffl-final-opening/Wffl Final Opening.app'
```

Preview options: `--paused`, `--light`, `--compact`, `--reduce-motion`, and `--controls`. Pass them using `open ... --args ...`, after quitting an already-running review instance. The compact window is 900×560; the default is 1100×700.

For native keyframes or the continuous recording:

```sh
zsh design-handoff/opening-reveal/final/build-preview.sh --render
zsh design-handoff/opening-reveal/final/build-preview.sh --render --movie
ffmpeg -framerate 60 \
  -i design-handoff/opening-reveal/final/renders/dark-1100/frame-%04d.png \
  -c:v libx264 -crf 14 -preset medium -pix_fmt yuv420p -movflags +faststart \
  -y design-handoff/opening-reveal/final/final-opening.mp4
```

Native window capture requires an unlocked Mac. Run export instances serially. `--light` and `--compact` select the other matrix entries. The movie driver supplies a 20-second review input path through the tour and a 7.2-second fold; it does not enable automatic tour progression in the app. Every frame comes from the same production native renderer and window, with no review-MP4 playback or concatenation.

From this `final/` directory, `python3 verify-frames.py --movie final-opening.mp4` checks native frame counts/sizes, the source-to-rest pixel comparison, the final uncovered Ask hold, movie metadata and a complete decode. It requires Python with Pillow and NumPy; the Codex bundled Python includes both. Its output is saved to `verification.json`.

## Verification results

Reviewed on macOS 27.0.1 using one GPT-6 Luna High integration worker and the lead's final technical and visual review.

- The full Swift package builds, and all **30 selected welcome/film tests pass**: 13 welcome/controller/policy tests and 17 existing native scene tests. Existing vendor-library deployment-target warnings are unchanged.
- **108 native keyframes** cover dark/light at 1100×700 and 900×560, exported at 2× resolution. Both appearances and sizes were visually inspected, including the selected dark teaser, qualified copy, source faces and uncovered Ask.
- `final-opening.mp4` is **61.65 seconds, 2200×1400, 60 fps, 3699 native frames**. There are 3134 distinct captured PNGs. A complete MP4 decode passes. All **60 final-hold frames are pixel-identical to uncovered live Ask**.
- Across the four viewports, more than **99.999%** of the outgoing page's interior pixels match the flat panel surface within two color levels. The comparison excludes the chrome strip and native window fringe; it does not claim byte equality for every antialiased edge.
- Actual native wheel input opened the fold, reversed from 32% to 18%, retraced into the tour, and completed to live Ask. Keyboard progression, Skip during a resized fold, Escape, replay, previous-field focus restoration and typing/clearing a test search were checked. The automatic opening reached Silence at 0% and remained stationary awaiting input.
- The fold was resized in progress to 900×560; 1100×700 was checked separately. Reduced Motion's full manual still sequence, Back/Next, compact light copy and direct Done-to-Ask completion were checked without changing the system preference.
- All 16 study-source hashes recorded at the start of this integration are unchanged. Both installed Wffl executable hashes are unchanged. Review builds link inert fixtures instead of the live library and recording services.

`verification.json`, `welcome-tests.log` and `build.log` retain the verification evidence. The native preview is saved under `built/`; the same source can be rebuilt with the commands above.

## Review scope

The native review app deliberately uses fixed meetings and readiness fixtures. Production source reads the application's actual state; the updated production binary has not been launched against the owner's live library. No publishing or installed-app replacement is part of this delivery. Accessibility summaries and keyboard behavior are checked in the native accessibility tree; an audible VoiceOver session is not part of the recorded review.
