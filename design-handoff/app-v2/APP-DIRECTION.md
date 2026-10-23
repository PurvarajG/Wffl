# Wffl app v2: direction brief

Owner verdict (2026-10-22): the website is right; the app is clunky, worse than before, and the welcome film inherits it. Atlas is the bar for cohesion and Mac feel (not something to copy).

This brief replaces the "build the SPEC literally" rule for the app. One agent owns the app's design; the website stays as it is.

## What went wrong (from the current build, see `ref/`)

1. **Website idioms pasted into a utility window.** 52 pt hero headline, pill CTAs and a "Your setup" checklist make Home a landing page squeezed beside a sidebar. The checklist is cut off at the default window size.
2. **Heavy chrome, no tonal system.** Solid black capsule for the selected row; 22 pt cards with borders for everything, including a privacy note. Atlas separates with small tone steps (shell, sidebar, panel, surface, hover, active) and almost no strokes.
3. **Not built as a Mac app.** Hand-made `HStack` sidebar (no glass, no collapse, no resize), 38 pt padding hack under the traffic lights that leaves a mismatched band, a custom search strip instead of the toolbar search field, no toolbar at all. Settings is both a sidebar page and the Settings window.
4. **Muddled information architecture.** Home, Dashboard, Meetings and Audio Files are four places for one library.
5. **The film is chained to the shell.** It morphs into the live Home under pixel-diff tests, so it cannot be better than the Home it lands on. Mid-film frames are blurred fragments behind a caption card.

6. **The shipped build runs in compatibility mode.** SwiftPM stamps the binary `sdk 15.0` (`otool -l … | grep -A4 LC_BUILD_VERSION`), so macOS 26+ draws `~/Applications/Wffl.app` with the old pre-Liquid-Glass chrome. The 1.8 app in `/Applications` says `sdk 26.5`, Atlas says `sdk 27.0`. Fix in `scripts/bundle.sh`: `vtool -set-build-version macos 15.0 "$(xcrun --show-sdk-version)" -replace` before signing (the prototype script does this). Also add an `AccentColor` asset (graphite) so sidebar selection is not system blue.

## Prototype

Branch `app-v2-prototype`, worktree `../Wffl-app-v2`. Run `scripts/prototype.sh` there (⌘1 / ⌘2 switch direction, ⌘R toggles recording, ⌘, Settings). Screens: `board.html` in this folder (`python3 -m http.server -d design-handoff/app-v2`).

## What we keep from the website

Monochrome. Hanken Grotesk light for big words, two-tone headlines (ink line, grey line). Fragment Mono for small labels and timestamps. White capsule waveform bars. Dot-matrix as the "listening" instrument. Ember only means live. One soft grainy glow, at most one per window.

## What we take from Atlas (the quality, not the look)

- One token file; surfaces differ by tone, not by borders.
- A real window frame: content sits in a calm field; small type in chrome; a quiet status line.
- Big moments (setup, what's new) take the whole window with no chrome, and leave it again.
- One display voice for character; everything else is quiet and small.

## Native rules (both directions)

- `NavigationSplitView`: system sidebar (Liquid Glass on macOS 26+), collapsible (⌘⌃S), resizable, traffic lights over the sidebar.
- A toolbar on every screen: Record (primary), search via `.searchable` (⌘F), and an actions menu on a meeting.
- Library-first IA: the sidebar is the library (Meetings, Imported; then the list). Home and Dashboard merge into the empty state shown when nothing is selected. Settings only in the Settings window (⌘,).
- Lists are native `List` selection: arrow keys, ⌫ to delete, type-to-select.
- Text sizes come from one scale (11 / 13 / 15 / 22 / 34 / 56 and the light display).
- Light and dark are both first-class; Increase Contrast respected.
- The website's ideas are allowed in exactly three places: the empty state, the recording instrument, and the film.

## Two directions to choose from

**A · Quiet Native.** Feels like a first-party Apple app built by a type-loving studio. Glass sidebar over a warm off-white (or near-black) field. Meeting opens as a reading document: big light title, mono meta line, Summary / Transcript / Notes as a segmented control in the toolbar. Recording happens inside the window: the detail becomes the instrument (big light timer, dot-matrix level, live lines), the toolbar Record turns into an ember Stop. The website shows up only as restraint: type, waveform mark, mono labels.

**B · Cinematic Stage.** The website, made usable. Same native chrome (glass sidebar, toolbar, search), but the detail is a stage: dark-first ground, the grainy lavender/peach glow behind the empty state, giant two-tone headline, transcript set large like the website's Minutes scene, a waveform strip across the top of a meeting. Recording takes over the stage with the dot-matrix instrument and ember. Light mode is the website's light scenes.

The owner picks one (or a mix: "A's library with B's recording"). The prototype is a real SwiftUI app (`Sources/WfflPrototype` on branch `app-v2-prototype`), switch with the Direction menu or ⌘1 / ⌘2.

## Film (Phase 4, after the build)

Drop the morph-into-Home pixel lock. Full window, no chrome, borrowing the website's scenes (silence → voice → voices → minutes → your Mac), then a single clean cut or cross-fade to the new library. The film ends on the real app; it no longer has to *become* it.

## Acceptance (replaces the pixel-diff tests for the app)

1. Sidebar collapses and resizes; nothing overlaps the traffic lights in either state.
2. ⌘F focuses toolbar search; arrow keys move through the list; ⌫ deletes with confirmation; ⌘, opens Settings.
3. At 900×560 (minimum) and 1440×900 nothing is clipped; no screen needs scrolling to reach its primary action.
4. Light, dark and Increase Contrast checked by screenshot; body text ≥ 4.5:1.
5. Ember appears only while recording.
6. No card has both a fill change and a border; selection is tonal, not a black pill.
