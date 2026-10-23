# Study 02: 3D product stage

Revision 6, awaiting owner approval. Revision 5 established the 3D direction; the owner requested stronger edge construction and more convincing depth. The owner rejected the flat gradient-mask studies and proposed a shallow 3D object with edge lighting. This study replaces those effects with actual SceneKit geometry, a perspective camera and two focused studio lights with feathered cones and a matching HDR reflection environment. No app integration has occurred. Study 01 revision 12 remains unchanged.

## Current direction

A native Home render is mapped to the front of a layered panel. The chassis is a physically lit graphite metal material with visible thickness. The screen is independently emissive, so lights illuminate the geometry without painting circular highlights onto the UI. The scene sits in a black studio void, without a horizon, floor wash, bloom or screen-space lighting masks. Two lights change angle slowly and the panel turns slowly through about eighteen degrees.

Reading this as a premium native product showing for returning Wffl users. DESIGN_VARIANCE 5, MOTION_INTENSITY 5, VISUAL_DENSITY 3. Existing typography, copy, appearance tokens and UI geometry are preserved on the native face. The 3D chassis is presentation geometry for the opening, not a proposed app redesign.

## Material and form changes in revision 6

The frame now has five separate solids: a deeper graphite shell, rear closure, narrow machined metal lip, dark gasket and glass edge. Each solid is an explicit rounded-rectangle mesh with analytic normals and eight segments through each small bevel. Corner radius and edge cross-section are independent. The thicker sidewall and stronger three-quarter angle make depth visible; the slow turn relaxes toward the display without reaching a flat front view.

Two moving spotlights use a broad penumbra. Two softboxes in a floating-point HDR environment supply surface reflections. Exposure adaptation and bloom remain disabled. Self-shadowing is disabled for this isolated object: there is no receiving surface, and shadow-map precision was causing speckles and incorrectly shadowing the emissive display. The display emerges more slowly during the first light pass.

The design-taste-frontend skill was applied to the motion and brand fidelity; high-end-visual-design informed the nested material construction. Existing app typography and layout remain native. Web layout and font prescriptions do not apply to this study.

## Playback

`edge-light-3d-study-v6.mp4` is the review clip: 10.8 seconds, 2200x1400, 60 fps. Earlier clips remain for comparison.

```sh
zsh design-handoff/opening-reveal/edge-light/build-study.sh
```

The separate native player has Play/Pause, Replay, scrubbing, light appearance and beat jumps. Space toggles playback. Reduce Motion disables playback and permits manual still selection.

| Time | Composition |
| --- | --- |
| 0-0.35s | Black |
| 0.35-2.5s | First light slowly catches the top and left bevel; the display begins emerging after 2.1s |
| 2.5-5.1s | Hold the form while the first light changes angle slowly |
| 4.6-6.9s | The opposing light rises and picks up the right edge and thickness |
| 6.9-9.4s | Whole app face remains visible at restrained brightness, with a brighter right rim |
| 9.4-10.6s | Lights and screen resolve to black |
| 10.6-10.8s | Black |

## Rendering and native fidelity

ProductStage.swift owns the actual SceneKit scene, chassis, display, two lights and camera. It takes a supplied CGImage rendered from native Home at 2x. ProductStageView displays SceneKit-rendered frames through a correctly sized native NSImageView; ProductStagePreview prepares the native texture in a task after layout, outside SwiftUI body evaluation. Preview and export use SCNRenderer with locked camera exposure, rather than automatic eye adaptation. Native texture preparation no longer requires anchor preferences or their obsolete assertion. Offline export uses SCNRenderer and the same scene, camera and update function. Eight-sample antialiasing is used for both live and exported rendering. The encoded review clip uses CRF 14 H.264.

The build compiles the current unchanged HomeView, InstrumentPill, Theme, AppFonts, ProcessingDisclosure and FilmAnchors. AppShell, SidebarView and NavSection are extracted verbatim into a temporary source file. ReviewFixtures supplies inert dependencies and filmSample bypasses permission, model and service work. No network assets or low-resolution screenshots are used. Revision 6 keyframes were exported at 1100x700 in both appearances and at 900x560 in dark appearance.

The old EdgeLightTeaser SwiftUI mask component is retained solely as previous study code and is no longer instantiated by the player or exporter. The current integration candidate is ProductStage. ReviewApp and ReviewFixtures remain standalone tooling.

## Reuse and integration boundary

Construct ProductStage(plate:size:) outside view evaluation, then drive update(elapsed) with the sequence clock. The scene does not own application navigation, settings, acknowledgement or persistence. Supply a native face render at the intended content dimensions. The stage's perspective is confined to this opening study. It does not change the actual Home beneath the eventual radial handoff, whose size and position must still remain fixed.

Introduction continuity, the tour, the live Home handoff, Skip, focus restoration, reduced-motion journey and final resource teardown remain integration work after approval. No worker has been dispatched.

## Reproduce export

```sh
zsh design-handoff/opening-reveal/edge-light/build-study.sh --render --movie
ffmpeg -framerate 60 -i design-handoff/opening-reveal/edge-light/renders/v6/dark-1100/frame-%04d.png -c:v libx264 -crf 14 -preset slow -pix_fmt yuv420p -movflags +faststart -y design-handoff/opening-reveal/edge-light/edge-light-3d-study-v6.mp4
```

Omit --movie for keyframes. Add --light or --compact for the other appearance or 900x560 layout. The full movie has 648 frames. Pure black is the explicitly requested stage; web layout, SEO, React libraries and generated photography are outside this native motion study.

## Verification

The standalone target builds. Revision 6 completed native playback through 10.8 seconds without a crash; the fitted panel and right-light composition were inspected in the native player. Export uses 648 frames at 60 fps and 2200x1400. An encoded movie frame was inspected after exposure was locked. Native keyframes render in both appearances at the default size and in dark appearance at the compact size. SHA-256 checks confirm the accepted demolition sources, v12 movie and existing product source remain unchanged.

The initial 3D preview exposed an obsolete anchor assertion and a hosting/render sizing issue. Texture generation now requires only the native image, and the player uses the same SCNRenderer path as export in a fitted NSImageView. These were review harness fixes; no shipping application source was edited.
