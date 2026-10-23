# Opening animation motion studies

Native SwiftUI components and a standalone review app. Nothing in the shipping app has been replaced. Approve each motion study before the final integration worker stitches the sequence together.

## Study 01: demolition

Revision 12: actual native Old Home → slow 2.35-second fade to black → restrained Hanken Grotesk Light **boring...** → backspace → **I agree!!!** → the old UI returns beneath the response, then TNT is placed across that surface over roughly four seconds → centre-out domino detonation → **Introducing....** typed in the same app font.

The owner's final pacing instruction is explicit: restore the old Home over 2.2 seconds, hold the completely visible old screen for 0.75 seconds, then place TNT over roughly four seconds. The hold runs 10.55–11.30 seconds; TNT starts only after it. The placement wave is normalized to its first grid cell so no hidden radial-stagger delay extends this pause. Preserve the accepted Hanken Grotesk Light typography, small text scale, wording, and centre-out explosion. The review target compiles the actual AppFonts.swift and packages the app's Hanken Grotesk and Fragment Mono files.

The text uses a fixed writing origin and baseline, cached native glyph measurements, deliberate punctuation pauses, accelerating backspaces, and a restrained caret. Existing letters no longer recenter on every keystroke. The old Home returns gently beneath the final held phrase. TNT is placed at fixed positions across the interface, without a flying or dropping entrance. The centre-out blast removes each old-UI region when its TNT detonates, and carries matching interface fragments away. Introduction resumes the same typing language after the debris settles.

### Design-taste audit

Mode: preserve, with targeted motion refinement. Audience: returning Wffl users. Aesthetic: cinematic keynote with the app's own Hanken Grotesk typography. DESIGN_VARIANCE 5, MOTION_INTENSITY 6, VISUAL_DENSITY 2.

Preserve the actual old UI, the owner's exact copy, white-on-black stage, native app fonts, and full-window centre-out TNT. Retire recentering letters, independent slide fades, floating TNT entrances, and decorative preview labels. This is native SwiftUI; React packages, page layouts, SEO, web image generation, and browser performance metrics do not apply to this motion component.

The owner explicitly requests pure black, white, the app's display type, and red TNT, so those brief choices override the skill's defaults. Native glyphs and legacy views are actual product rendering. There are no invented screenshots, decorative imagery, cards, stock content, or dependencies. The standalone host respects Reduce Motion by disabling automatic playback and retaining user-selected stills. Final application integration retains responsibility for the existing welcome coordinator, announcements, and reduced-motion journey.

Compile and open from the repository root:

```sh
zsh design-handoff/opening-reveal/build-study.sh
```

The review app has Play/Pause, Replay, a scrubber, and jumps to each beat. Space toggles playback. The controls are review tooling and will not appear in the finished opening.

To render key frames, run `zsh design-handoff/opening-reveal/build-study.sh --render`. Add `--movie` to render every frame at 60 fps and 2× resolution (2200×1400). Add `--compact` for 900×560 layout checks. Builds use absolute source paths and directly compile the app's unchanged LegacyShell and film-anchor source files into the standalone target.

## Integration contract

`DemolitionScene(legacyPlate: CGImage, elapsed: Double) { LegacyShell() }` fills its parent. The initial old Home is an actual native view. Supply a matching plate rendered at 2× the actual content size for the exploding fragments only. Drive elapsed time with the sequence clock. Duration is 22.65 seconds; the centre-out detonation starts at 16.05 seconds and crosses the window in approximately two seconds. The scene has no navigation, clock, settings access, hit testing, or accessibility announcements. The final application host owns those concerns and its Reduced Motion stills. Both the standalone app and final app use this exact component without translating from HTML.

The PNGs in `assets` are retained as first-study references only; the current study does not load or enlarge them. It displays LegacyShell directly and generates its fragment plate at the current window size. Final integration must reveal the actual live Home, never a screenshot of it.

## Study 02: edge-light teaser

The separate `edge-light/` folder now contains `edge-light-3d-study-v6.mp4` (10.8 seconds, 60 fps, 2200x1400). After rejecting the flat masked light studies, the owner proposed a 3D stage. Revision 6 strengthens the 3D construction with a deeper graphite shell, machined lip, dark recess and inset glass edge, analytic bevel normals, a stronger three-quarter turn and two focused studio lights. The display remains the actual native Home. See `edge-light/README.md` for the current scene and reuse contract. Awaiting owner approval. Study 01 revision 12 and all existing app source are unchanged.

Next study after teaser approval: Gaussian-style radial handoff. Owner also permits a Tetris-style folding-square handoff as an alternative. App integration remains pending approval.
