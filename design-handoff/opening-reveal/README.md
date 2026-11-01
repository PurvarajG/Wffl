# Opening animation motion studies

Native SwiftUI components and a standalone review app. On 26 October the owner approved final stitching in a new chat. Read `FINAL-STITCH-HANDOFF.md` for the current integration brief; older study and pending-approval statements below are historical.

## Study 01: demolition

Current source is revision 14. The typing sections have been replaced using the owner's two video references: a compact charcoal text block types **A little boring, / isn’t it?**, backspaces, then types **I agree. / Let’s change that.** After the demolition, scattered letters settle into **Introducing**, contract into the new eight-bar mark, then reveal **Wffl** beside it. The black stage and native Hanken Grotesk keep continuity with the rest of the film.

Review the two short clips: `typing-block-v14.mp4` and `introducing-wffl-v14.mp4`. The last full-film export remains `demolition-study-v13.mp4`; it has the previous typography. The full current sequence runs in the standalone player. See `typing-revision-14.md` for the design decision and economical export workflow.

Revision 13 adds the legacy window controls inside the film frame and its fragment plate. The accepted revision 12 animation and pacing are unchanged.

The owner's final pacing instruction is explicit: restore the old Home over 2.2 seconds, hold the completely visible old screen for 0.75 seconds, then place TNT over roughly four seconds. The hold runs 10.55–11.30 seconds; TNT starts only after it. The placement wave is normalized to its first grid cell so no hidden radial-stagger delay extends this pause. Preserve the accepted legacy restoration, TNT placement and centre-out explosion. On 25 October the owner gave creative freedom to replace the typography and wording using the supplied references. The review target compiles the actual AppFonts.swift and packages the app's Hanken Grotesk and Fragment Mono files.

The text uses a fixed writing origin and baseline, cached native glyph measurements, deliberate punctuation pauses, accelerating backspaces, and a restrained caret. Existing letters no longer recenter on every keystroke. The old Home returns gently beneath the final held phrase. TNT is placed at fixed positions across the interface, without a flying or dropping entrance. The centre-out blast removes each old-UI region when its TNT detonates, and carries matching interface fragments away. The introduction now follows the second reference: scattered glyphs, a readable hold, contraction into the mark, then a stable logo and title lockup.

### Design-taste audit

Mode: preserve, with targeted motion refinement. Audience: returning Wffl users. Aesthetic: cinematic keynote with the app's own Hanken Grotesk typography. DESIGN_VARIANCE 5, MOTION_INTENSITY 6, VISUAL_DENSITY 2.

Preserve the actual old UI, black stage, native app fonts and full-window centre-out TNT. Revision 14 replaces the copy and typography under the owner's explicit creative direction. Retire recentering letters, independent slide fades, floating TNT entrances, and decorative preview labels. This is native SwiftUI; React packages, page layouts, SEO, web image generation, and browser performance metrics do not apply to this motion component.

The owner explicitly requests pure black, white, the app's display type, and red TNT, so those brief choices override the skill's defaults. Native glyphs and legacy views are actual product rendering. There are no invented screenshots, decorative imagery, cards, stock content, or dependencies. The standalone host respects Reduce Motion by disabling automatic playback and retaining user-selected stills. Final application integration retains responsibility for the existing welcome coordinator, announcements, and reduced-motion journey.

Compile and open from the repository root:

```sh
zsh design-handoff/opening-reveal/build-study.sh
```

The review app has Play/Pause, Replay, a scrubber, and jumps to each beat. Space toggles playback. The controls are review tooling and will not appear in the finished opening.

For the two short review sections, add `--section correction` or `--section introduction` to `--render`; add `--movie` to export only that section at 60 fps.

To render key frames, run `zsh design-handoff/opening-reveal/build-study.sh --render`. Add `--movie` to render every frame at 60 fps and 2× resolution (2200×1400). Add `--compact` for 900×560 layout checks. Builds use absolute source paths and directly compile the app's unchanged LegacyShell and film-anchor source files into the standalone target.

## Integration contract

`DemolitionScene(legacyPlate: CGImage, elapsed: Double) { LegacyWindowFace() }` fills its parent. The initial old Home is an actual native view. Supply a matching plate rendered at 2× the actual content size for the exploding fragments only. Drive elapsed time with the sequence clock. Duration is 22.65 seconds; the centre-out detonation starts at 16.05 seconds and crosses the window in approximately two seconds. The scene has no navigation, clock, settings access, hit testing, or accessibility announcements. The final application host owns those concerns and its Reduced Motion stills. Both the standalone app and final app use this exact component without translating from HTML.

The PNGs in `assets` are retained as first-study references only; the current study does not load or enlarge them. It displays LegacyShell directly and generates its fragment plate at the current window size. Final integration must reveal the actual live Home, never a screenshot of it.

## Study 02: edge-light teaser

The separate `edge-light/` folder now contains `edge-light-3d-study-v7.mp4` (dark) and `edge-light-3d-study-v7-light.mp4` (light) (10.8 seconds, 60 fps, 2200x1400). After rejecting the flat masked light studies, the owner proposed a 3D stage. Revision 6 strengthens the 3D construction with a deeper graphite shell, machined lip, dark recess and inset glass edge, analytic bevel normals, a stronger three-quarter turn and two focused studio lights. Revision 7 replaces the rejected Home/setup display with the current native app-v2 Ask UI, including its sample library, native sidebar and Record toolbar. The revision 6 geometry, lights, turn and duration are preserved. See `edge-light/README.md` for the current scene and reuse contract. Awaiting owner approval. Study 01 is revision 13; its motion is unchanged. Existing shipping app source is unchanged.

Next study after teaser approval: Gaussian-style radial handoff. Owner also permits a Tetris-style folding-square handoff as an alternative. App integration remains pending approval.

## Study 03: radial handoff

The owner approved the revision 14 typing sections and delegated the teaser choice; the dark 3D v7 is selected. The handoff prototype is in `handoff/`: a full-window soft radial reveal into the same live native Ask view, with a 44-point boundary feather. The native window and its content stay fixed. Dark keyframes at 1100×700 have been inspected; completed frames and the clear app before/after are byte-identical. The completed `handoff/radial-handoff-v1.mp4` is a4.2-second native recording at60fps. Both appearances and both window sizes have been checked; the native Ask input accepted typing after playback. The temporary locked-Mac capture issue is resolved. See `handoff/README.md`. Run native capture exports serially. Shipping integration remains pending review of the moving handoff.


## Pixel handoff v2 — latest approved direction

Owner confirmed that scrolling further after Your Mac should pixelate the outgoing page, then open the pixel surface into live Ask. The standalone native study now implements scroll forward/reverse with an 11.5pt sampled pixel/X matrix and cellwise radial opening. Preview: `handoff/pixel-handoff-v2.mp4` (5.6s, 336 frames, 60fps). Actual native scroll, reverse and final text input verified. Product sources and the approved revision14 typing/brand/teaser remain unchanged. See `handoff/README.md` for build and verification details. The earlier radial-only preview is retained; final tour integration has not started.


## Block handoff v3 — slower and reversible

The owner refined the transition to larger solid design blocks, smoother/slower motion and backward scrolling that retraces the transformation. Latest preview: `handoff/block-handoff-v3.mp4` (8.8s, 528 frames, 60fps). Native input uses direct progress, 1600pt travel and 90ms smoothing; 58pt tiles ease across a broad front. Native reversal back to the original page and final text input were checked. See the handoff README for details. Earlier previews remain available.


## Exact-content tiles v4 — latest correction

The owner clarified that the exact visible page must be cut into tiles, keeping its text/images intact, then those original-content tiles open to reveal Ask beneath. Averaging the screen into flat colors was incorrect. Corrected preview: `handoff/content-tiles-v4.mp4` (8.8s, 528 frames, 60fps). Content preservation, native final handover and full decode were verified; the scroll controller stays unchanged. See the handoff README for evidence.


## Hinged 3D fold v5 — latest preview

The owner requested physical 3D folding rather than flat shrinking tiles. Latest preview: `handoff/folding-handoff-v5.mp4` (8.8s, 528 frames, 60fps). The exact outgoing page is mapped onto thin hinged SceneKit panels, with perspective, graphite backs and shadows. Native Ask stays live and fixed underneath. Actual backward scrolling restores the original page; completing the fold restores native typing. The standalone build, full movie decode and protected source checks pass. Product integration remains separate.
