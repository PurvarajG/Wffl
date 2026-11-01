# Current release integration — completed 26 October 2026

The final What's New integration now uses the photographic TV opening, full-window static/correction, five-second Introducing Wffl, the native user-paced product tour, and the approved v8 equal-sized falling/colliding cubes into live Ask. This supersedes the TNT, teaser, curtain and hinged-fold directions in the historical handoff below.

Current delivery and evidence: `final/README.md`, `final/final-release-v1.mp4`, `final/built/Wffl Release Preview.app`, `final/verification-final-release-v1.json` and `final/native-interaction-checks.md`. The 48.3-second native recording and isolated preview are built; 34 selected tests and full decode pass. Integration sources include the cancellable background bake, active/pending resize swap, reversible input and unchanged welcome lifecycle. No installation or publication was performed.

## Historical approved integration handoff

Updated 26 October 2026. This is the current brief; it supersedes old approval gates and rejected directions in the historical notes.

## Owner authorization

The owner reviewed the final hinged 3D fold and said: “yeah go ahead in a new chat stitch it alltogher into a final thing”. The separate motion studies are now approved for stitching. Execute the final integration and deliver a continuous review recording plus a playable native result; do not ask for the same design approvals again. Keep tasks split sensibly and credit efficient, reusing the completed native components. The recorded credit-conscious execution plan is one GPT-6 Luna High integration worker owning the coupled phase boundaries, followed by the lead’s visual and technical review; avoid redispatching the already completed scene designs.

Workspace: `/Users/purvarajsinhgohil/Developer/Wffl`. At handoff the branch is `master`, with modified and untracked study files. Preserve all existing work. The approved files are not committed: a clean worktree or checkout will not contain all of them unless deliberately carried over. Do not reset, clean, overwrite the installed Wffl app/library or publish changes.

## Final sequence

1. Actual legacy Home, gentle fade to black.
2. Approved revision 14 typing block: “A little boring, / isn’t it?” → visible backspace → “I agree. / Let’s change that.”
3. Accepted legacy restoration, TNT placement and centre-out demolition.
4. Approved revision 14 scattered Introducing letters → current eight-bar W logo → Wffl title lockup.
5. Selected dark revision 7 3D edge-light teaser.
6. Full reveal into the existing native, website-style product tour. Keep the real app-v2 feature scenes and qualified wording: Silence, Voice, Voices, Minutes, Your Mac. Reuse the product scene implementations and the supplied real app film/frame sheets rather than inventing another UI. Stop the automatic clock at the tour; the owner drives the tour with scroll/keyboard and can move backward within it.
7. After Your Mac, further scrolling cuts the EXACT visible page into content panels and folds them outward in real 3D. Use the approved v5 hinged renderer, preserving text/images on the faces. The same progress retraces backward until completion.
8. Reveal the actual live app-v2 Ask home underneath, already at its final size and position. Remove the tour overlay once fully open and restore native interaction/focus. No sample-to-live swap, app scale/position jump or extra fade back to a mockup.

The latest design is **v5 hinged folding**, not the earlier radial wipe, fine X grid, flat averaged-color mosaic, or shrinking content tiles. All those are superseded. The correct final UI is **Ask the library**, with native sidebar Ask / Action Items / Audio Files, meetings, Recent, Open action items and top-right Record. The old cream Home is only the legacy opening. The macOS purple recording pill is not app UI.

## Approved components and evidence

- `design-handoff/opening-reveal/DemolitionScene.swift`, `LegacyWindowFace.swift`, `ChatCorrection.swift`, `BrandIntroduction.swift`, `KeynoteTypography.swift`, `StudyApp.swift`, `build-study.sh`.
- Typography review movies: `typing-block-v14.mp4`, `introducing-wffl-v14.mp4`. **The full demolition-study-v13.mp4 has stale typography**; stitch from current reusable source, not that old movie.
- Preserve the 22.65s demolition/introduction composition and accepted pacing: old Home returns over 2.2s (8.35–10.55), then a clear 0.75s hold (10.55–11.30); TNT placement takes about four seconds, with centre-out detonation starting at 16.05. Do not shorten the TNT placement.
- `design-handoff/opening-reveal/edge-light/ProductStage.swift`: current native 3D chassis, bevels, lighting and turn. Selected reference `edge-light/edge-light-3d-study-v7.mp4` (dark, 10.8s); light variant exists but dark was chosen. `NativeAskFace.swift`, `prepare-native-face.py` and `ReviewFixtures.swift` supply inert study data and real UI extraction.
- `design-handoff/opening-reveal/handoff/FoldSurfaceView.swift`: approved real SceneKit panel geometry. About 80pt panels, 1pt thickness, 30° perspective, outer-edge hinges to 122°, radial phase wave, front content, graphite edges/backs and shadows. `setProgress(_:)` is deterministic. Reference `handoff/folding-handoff-v5.mp4` (8.8s, 528 native frames, 2200×1400, 60fps).
- `handoff/HandoffHost.swift`: proven capture/overlay architecture and normalized scroll follow (1600pt travel, 90ms smoothing, immediate reversal from visible progress). A plain NSView contains SwiftUI and SceneKit as siblings; placing SceneKit directly inside NSHostingView lets SwiftUI remove it. Capture ONLY the outgoing page once, then clear that original layer. Keep the real Ask host live underneath. This sample host is a harness, not the production coordinator.
- `handoff/HandoffApp.swift`, `handoff/build-study.sh`, `handoff/README.md`: controls, capture/build workflow and verification. Inactive older PixelHandoff/Metal/RadialHandoff components are not the selected final effect.
- Current product sources: `Sources/Wffl/Welcome/FilmTimeline.swift`, `FilmStage.swift`, `FilmScenes.swift`; `Sources/Wffl/Support/WelcomeJourney.swift`, `Views/WelcomeJourneyView.swift`, `Views/ContentView.swift` and `Views/AskHome.swift`. Relevant tests: `Tests/WfflTests/UpdateFilmTests.swift` and `WelcomeJourneyTests.swift`. The existing `website/index.html` is the local motion/copy reference.

The studies passed native builds, relevant visual captures and narrow reviews. V5 actual scrolling advanced to 42%, reversed to 31%, returned fully to 0%, then completed to live Ask; native typing worked and temporary text was cleared. All 60 final-hold PNGs matched the uncovered Ask capture. A full MP4 decode passed. The prior protected product and approved source hashes are recorded in `/tmp/wffl-pixel-source-baseline.json` if still available.

## Integration and delivery requirements

Use code-level native integration, not concatenated MP4 playback. Reuse approved components; adjust only the boundaries and coordination needed to make the sequence continuous. Preserve app fonts (Hanken Grotesk / Fragment Mono), current logo, qualified privacy/feature copy and existing welcome replay, Skip, Escape, acknowledgement and interruption policy.

Retain user-paced Reduced Motion stills with direct live-app completion, keyboard progression, readable accessibility announcements, resize handling and final focus restoration. Stop/release temporary rendering resources after completion. The 3D source image must be the exact current outgoing content, while the revealed app must remain real and live. Resolve the production viewport/source refresh during resizing rather than blindly relying on the study's frozen-image resize behavior.

Use the current app's real readiness/library state in production. Sample fixtures belong only in an isolated review build; never read/write the user's live library for a visual test or overwrite the installed application. Preserve unrelated work and current data.

Run appropriate native build/welcome tests and inspect actual continuous playback, forward/reverse tour/fold control, automatic-to-scroll boundary, Skip/Escape/replay/acknowledgement, Reduced Motion, keyboard/focus, resize and both light/dark at 1100×700 and 900×560. Deliver a final continuous native recording and runnable preview/build, with a concise report of changes and any real remaining limitation. Review the whole result after stitching. Avoid reopening or regenerating every rejected study.

For detail, consult the three study READMEs and `typing-revision-14.md`. `docs/design-review/opening-reveal-storyboard.md` and `re-fresh-opening-reveal.md` contain useful historical contracts, but their old Home names, typography, radial effect and pending-approval statements are superseded by this file and the owner's latest approval.
