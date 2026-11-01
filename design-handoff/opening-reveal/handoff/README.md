# Study 03: block handoff

## Current preview: falling cubes v8 — 26 October 2026

Owner correction: equal-sized cubes falling into each other. `falling-cubes-v8.mp4` replaces the tetromino motion for review. The outgoing screen now consists of uniform 80×80×80pt cubes, including full cubes extending beyond the viewport edge with clamped source UVs. Their fronts reconstruct the original screen at rest. Bottom-up staggered releases, gravity, mixed-axis rotation, and actual SceneKit box collisions create a tumbling heap. A temporary floor catches the cubes before releasing them below the window.

The physics runs once in a separate scene at 120Hz for five simulated seconds, driven by tiny offscreen snapshots. Playback interpolates saved positions/quaternions; scrolling backward retraces the same bake without reversing a live physics solver. No physics bodies run in the display scene. The initial tightly constrained cube experiment is archived under `revisions/v8-cubes/`; v7 is under `revisions/v7-tetris/`.

Verified dark preview: 126 equal cubes, 601 baked pose frames, 29,040 contact callbacks in the final viewport bake. The native movie has 264 frames, 2200×1400, 30fps, duration 8.8s; full decode passed. Forward/reverse native captures at 32% are byte-identical and every saved transform restores exactly. Restored source: 99.990% of pixels within one RGB level, with small edge/raster differences; full source equality is not claimed. Ask host identity/window frame remain fixed and the overlay is removed at completion. All 30 final-hold frames match uncovered Ask within one RGB level. Native keyframes were inspected for cube depth, tumbling and the visible pile.

Build and controls are as below; frames now use `renders/v8-cubes/`. Compact light export began but failed with ScreenCaptureKit error -3811 (reported by the harness as capture failure requiring an unlocked Mac); no completed v8 light check is claimed. Dark export is complete and the revised movie was opened in QuickTime with playback active. Production files, corrected opening V5 and its rough-frame note remain unchanged, verified by hashes.

## Previous preview: 3D Tetris rollout v7 — 26 October 2026

`tetris-rollout-v7.mp4` is the standalone motion review requested before stitching the full opening. Connected L/O/J/I pieces tile the captured outgoing screen, retaining its text and imagery. Each piece has a 12-point solid back and perimeter side walls. A centre-out wave rolls the pieces before carrying them beyond the window. Geometry is constructed once per viewport; progress only updates deterministic transforms.

The production renderer and corrected `final/photo-tv-opening-v5.mp4` are unchanged. The previous curtain study sources are archived in `revisions/v6-curtain/`. Older descriptions below are historical.

Build/open with `zsh design-handoff/opening-reveal/handoff/build-study.sh`. Controls include Play, Replay, Separate blocks, Mid rollout, Live Ask and scrubbing. Scroll down to advance and up to reverse before completion. The executable also accepts `--autoplay`.

Export with `zsh design-handoff/opening-reveal/handoff/build-study.sh --render --movie`. Frames are under `renders/v7-tetris/dark-1100/`; compact light stills use `--render --light --compact` and `renders/v7-tetris/light-900/`. Run `verify-tetris.py <capture-folder>` with the bundled Python runtime (Pillow/NumPy) for pixel comparisons.

Verified: native build passed. Dark movie contains 264 frames at 2200×1400, 30fps, 8.8 seconds; full H.264 decode passed. Fifteen compact light frames are 1800×1120. Grid setup asserts complete non-overlapping coverage and connected pieces. Every node transform restores exactly after reversal; forward/reverse native captures at 32% are byte-identical in both appearances. The restored source has 99.989% of pixels within one RGB level in dark, and 99.983% in compact light; small raster/seam differences remain, so whole-frame source equality is not claimed. The native Ask host identity and window frame remain unchanged during forward/reverse export, and the overlay is removed at completion. All 30 final-hold dark frames match uncovered Ask within one RGB level.

Manual native input verified scroll 0→42%→27%→0%, then forward completion, overlay removal and live search-field typing. Test text was cleared. Reduced Motion remains supported by the existing host; the system preference was not changed for a manual test. The exact captured outgoing page is retained on resize, as in the previous study.

Standalone native review study. Latest owner refinement: the exact current screen should fold outward in 3D. Its text and images remain on thin hinged panels, which expose the live native Ask view underneath. Prior flat-mask previews and archived source revisions remain available.

## Current design and interaction

The host captures the actual outgoing Your Mac window once after layout settles. This image is partitioned into approximately 80pt, one-point-thick SceneKit panels; each front face retains its original portion of the text and imagery. A 30° perspective camera fits the source plane exactly at rest. Seams develop through progress 0.24. A broad radial wave then rotates panels toward the viewer around their outer edges, with visible graphite edges and backs, angle shading and directional shadows. Panels rotate to 122° before clearing. There is no scale-based shrinking of the panels.

Only the outgoing page is captured. Ask remains one live native view underneath the transparent scene. A plain AppKit overlay owns SwiftUI and SceneKit as sibling views, so SwiftUI updates cannot remove the native scene. A shadow-only receiver permits panel shadows to fall over the underlying app without inserting a background image of Ask.

Scroll down to advance; scroll up before completion to reverse. Input controls normalized progress across roughly 1600 points of travel. A 90ms response smooths wheel steps and trackpad motion; changing direction immediately resets residual forward lag to the visible position. When input stops, only the small smoothing gap settles. The transformation itself is a pure function of progress, so reversal follows the same block geometry.

The timed export demonstrates the same progress states in 8.8 seconds: 0.6s original page, 7.2s transformation, 1s live app. The native preview starts stationary and scrolling controls its position. Controls provide Tour, Cut screen, Half fold, Live Ask, scrubbing and light appearance. Playback/scrubbing cancels scroll-follow smoothing. Reduced Motion disables timed playback and forward scrolling goes directly to Ask.

At completion the overlay is removed, restoring native input. Only the finishing gesture's momentum is consumed; fresh gestures immediately reach Ask.

## Components

- `FoldSurfaceView.swift`: real SceneKit panel geometry, upright source crops, perspective camera, outer-edge hinges, lighting, shadows and deterministic progress. Rebuilds geometry/camera on viewport size changes using the retained outgoing image.
- `HandoffHost.swift`: captures the outgoing page, keeps the native Ask host fixed beneath the transparent folding surface, consumes native scroll and removes the overlay at completion.
- `HandoffApp.swift`: separate study controls and deterministic review clock.
- `PixelHandoff.swift` / `.metal` and `RadialHandoff.swift`: retained earlier flat studies, not the active renderer. Their prior source is also archived in `revisions/`.
- Current product source extraction and inert sample fixtures still provide the native Your Mac and Ask views. No real recording or library services run.

## Build and export

```sh
zsh design-handoff/opening-reveal/handoff/build-study.sh
zsh design-handoff/opening-reveal/handoff/build-study.sh --build-only
zsh design-handoff/opening-reveal/handoff/build-study.sh --render --movie
```

Requires the official Xcode Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`). It compiles the shader into this review bundle only. The toolchain was installed while preparing v2.

The built app is `/tmp/wffl-handoff-study/Wffl Handoff.app`. Reuse its executable for additional captures without recompiling:

```sh
'/tmp/wffl-handoff-study/Wffl Handoff.app/Contents/MacOS/WfflHandoff' --render --light --compact
```

Add `--movie` for 528 frames at 60fps, omit it for 15 keyframes. Default is dark, 1100×700; `--light` selects the underlying app's light appearance and `--compact` selects 900×560. Captures are 2× resolution in `renders/v5/<appearance>-<width>/`. Each folder has the original captured `source-tour.png` plus uncovered `live-before.png` and `live-after.png`.

The installed app, approved typography/brand/demolition, 3D teaser and product sources remain separate from the study. The full user-controlled tour and shipping welcome lifecycle remain integration work after this preview.

## Capture environment

Native export requires an unlocked macOS session. If the Mac locks, ScreenCaptureKit can fail with error -3811; the exporter reports that condition and exits cleanly. Unlock manually before retrying. Run native window capture jobs serially. `build-study.sh --build-only` checks the standalone target without opening or recording windows. The initial export was interrupted when the Mac locked. After the owner unlocked it, recording and all size/appearance checks completed successfully.


## Verified folding v5 preview

`folding-handoff-v5.mp4`: 8.8 seconds, 528 native frames, 2200×1400, 60fps. Full decode passed; 407 distinct captured frames show the fold progression. All 60 final-hold PNGs exactly match the final uncovered live Ask capture. Runtime checks passed for unchanged native host identity/window frame and final overlay removal.

Source, flat panel surface, intermediate hinges, back faces and near-complete fold were visually checked in the native window. Upright text and source-image orientation are correct. All 15 compact light keyframes have the expected 1800×1120 dimensions; their transparent opening was inspected over the light app. The encoded movie's middle frame was inspected too. Native scrolling advanced to 42%, reversed to 31%, then fully returned to 0%, restoring the original page. Forward scrolling then fully removed the overlay; the native search field accepted “fold check”, which was cleared.

The full native build completes without diagnostics, the independent narrow code review passes and all 63 protected product/approved source hashes remain unchanged. Previous source/movie revisions remain available. The source texture is frozen at the start of this standalone final-page study; a mid-fold resize scales that retained capture while rebuilding the panel geometry/camera. Reduced Motion support is retained without changing the system setting for testing. Shipping integration remains separate.

## Previous exact-content v4 verification

`content-tiles-v4.mp4`: 8.8 seconds, 528 native frames, 2200×1400, 60fps, full decode passed. All 60 final-hold PNGs match the final uncovered native Ask capture. Native host identity, window geometry and final overlay-removal checks passed.

The original page and fully cut page were compared away from seam lines: 2,636,222 pixels checked, with 99.9985% within one RGB level and a maximum difference of two levels. Text/image pixels were checked separately, with 99.97% within one level. The shader returns the original source sample in tile interiors and uses the complete original tile image while opening; it contains no color averaging.

Native formation/opening frames and the encoded middle frame were visually checked. All 14 compact light keyframes have the expected 1800×1120 dimensions. The scroll/timing controller is unchanged from v3, except for its export folder. All 63 protected source hashes remain unchanged. The native study compiles cleanly. Product integration remains separate.

## Previous block v3 verification

`block-handoff-v3.mp4`: 8.8 seconds, 528 frames, 2200×1400, 60fps; full decode passed. There are 399 distinct native captured frames. All 60 final-hold PNGs match the final uncovered native Ask capture exactly. The initial and final native captures have small compositor color differences (8340 channel values, maximum 5/255); initial/final byte equality is not claimed. Runtime checks enforce the same native host identity and window frame, and final overlay removal.

Full-size dark and compact light keyframes were inspected, including formed tiles and the broad moving front. Fourteen compact light keyframes have the expected 1800×1120 dimensions. The encoded dark movie's middle frame was inspected too. Native scroll advanced 0→21→43%, reverse 35%, held at 35%, and reversed fully to 0% restoring the original page. Forward scrolling reached97%; final Live Ask control removed the overlay and the real search field accepted “block movement check”, then was cleared. Final completion was also verified across the native export's entire hold.

Fresh native Swift/Metal compilation and narrow independent code review passed. All 63 protected product/approved source hashes remain unchanged. Reduced Motion is supported without changing the system preference for testing. Product integration remains separate from this standalone study.

## Previous pixel v2 verification

`pixel-handoff-v2.mp4` is the completed 5.6-second native recording: 336 frames, 2200×1400, 60fps, 184 distinct captured frames. Full MP4 decode passed. All 66 final-hold PNG frames match the uncovered native Ask capture byte for byte. Runtime checks passed for unchanged native host identity/window frame and final overlay removal.

Sixteen keyframes were captured at each of dark/light × 1100×700/900×560, with all output dimensions checked. Formed grid and opening were visually inspected in native captures, including compact light; the encoded movie's middle frame was also inspected. Dark uncovered before/after captures are byte-identical. Light captures have native rounding variation, so byte equality is not claimed for light.

Actual native UI scroll checks showed progress 0 → 5 → 35%, reverse to 22%, forward to 58%, then complete overlay removal. The real Search every meeting field accepted “pixel handoff check”; the text was cleared. A narrow independent code review passed after replacing the initial time-based momentum guard with gesture-phase tracking. A fresh native Swift/Metal build has no diagnostics. All 63 protected product/approved source hashes remain unchanged; `git diff --check` and shell syntax checks passed.

Reduced Motion's direct completion is implemented; the system preference was not changed for a manual test. This remains a standalone final-page study, pending integration into the complete tour.

## Previous radial-only verification

`radial-handoff-v1.mp4` is the completed 4.2-second native recording: 252 frames, 2200×1400, 60 fps, full decode verified. The 135 unique captured frames confirm actual progress through the transition; all 72 final-hold frames match the original uncovered Ask capture byte for byte. Native host identity, window frame and complete tour removal are checked during export.

Keyframes were visually checked in dark and light at both 1100×700 and 900×560. Dark endpoints are byte-identical; light endpoints differ by at most one channel level out of255 from native capture rounding. The review host fixes its viewport after toolbar installation, preventing AppKit's added20points from turning the900×560 check into900×580. The normal native player completed Play/Pause playback; the uncovered actual Ask field accepted “handoff check”, and the test text was cleared. The sample harness has inert recording/library actions, while native input is live.

Approved typography, demolition, 3D geometry and product view source hashes remain unchanged. The transition is ready for the owner's visual review; shipping integration has not started.
