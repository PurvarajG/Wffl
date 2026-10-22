# TODO for the next pass

Ordered. Items 1 to 8 are the open fixes from the last independent review of the journey website and the mockup page. Everything else in `README.md` is done. Keep the single grainy light, the dot-field hero, the sticky-stage journey, the privacy table and the zero-dash copy. Do not add more effects: the motion budget is spent.

## Website (`website/index.html`)

1. **Speaker scene is wrong (truth).** The app's diarizer produces numbered placeholders ("Speaker 1", "Speaker 2") that the user renames once; the voice library then recognizes that voice in later meetings. The journey scene 3 auto-swaps "Them" to "Priya" and "Marcus" and the copy says "given stable names". Rework: show "Them" becoming "Speaker 1" and "Speaker 2", then a visible rename affordance turning one into a name. Retitle chapter "Everyone gets a name" to something like "Tell the voices apart." New copy along the lines of: "Other voices are separated as Speaker 1, Speaker 2. Rename one once and Wffl recognizes that voice in later meetings. Your microphone is always Me." Fix the scene note to match.
2. **Label the stage as sample data.** Add a visible, non-aria-hidden caption under the sticky stage, e.g. "Sample meeting, invented for this page." (PRODUCT.md requires demonstration material to be labeled.)
3. **Reduced motion must show end states.** With animations disabled the scenes sit on their start states: scene 2 never shows names (`.pill-n .b` stays opacity 0), scene 3 stays on "Raw" with fillers visible, scene 4 todo boxes stay empty. Under `prefers-reduced-motion: reduce` render the end states. The hero should show "Saved" (not a frozen "Recording 18:24" lamp).
4. **WCAG 2.2.2.** Auto-moving content needs a keyboard-reachable pause. Add a "Pause motion" toggle (footer or nav) that stops the hero script, the dot field and all CSS loops (`.eq` and `.fl` in scene 0 loop forever; make them finite or run only while the scene is on screen).
5. **Remove the eyebrow pattern.** The mono timecode above each chapter title (`.tc`) reads as a kicker, and "Any time" on chapter 5 is not data. Drop it from above the h3 (the stage clock already carries the time), or move it into the rail gutter beside the marker.
6. **Stage craft.** Desktop stage is 500px and scenes 1, 3, 5 leave it half empty: reduce to about 380 to 420px or scale the scene type up. Add `min-height: 360px`. Below about 700px viewport height scenes 3 and 5 clip under `overflow: hidden`: make scenes scroll or auto-fit. Scene 5 (library) shows a recording timer over a search UI: swap the stage header to "Library" and drop the timer there.
7. **Clean-up scene polish and contrast.**
   - Wrap "Um," in `.f` and trim spaces so the cleaned line has no double spaces (currently "so the  download flow works,  but").
   - Inactive chapters use `opacity: 0.34`, which fails contrast (about 1.5:1 for dim body, 2.4:1 for the h3). Raise to about 0.55 to 0.6.
   - Mobile nav says "Download" while the hero and closing say "Download for macOS". Keep one label per intent if the nav layout allows.
8. (Low) The glow is used in hero, stage bed, privacy panel and closing. Keep at most one per viewport as you scroll.

## Mockups (`mockups/index.html`)

- Wire or remove `cursor: pointer` on `.proto .li` (meeting rows in the prototype sidebar have no click handler).
- `startRec()` does not reset the waveform bars or transcript rows, so a second visit shows leftovers. Reset state on entry.
- Duplicate ids (`rtime`, `wbars`, `rtx`) exist in both the prototype and the flat Recording screen. Scope or rename.
- Light-mode `--soft` (`#9A9A96`) is about 2.6:1 on `#F2F2F0` and is used for 11.5 to 12px text (group headings, counts, search placeholder). Darken to about `#75756F` for text uses.
- Collapsed recording bar hardcodes `#0B0B0B`, `#F2F2F0`, `#FF6A33` instead of tokens (fine if it is meant to float dark over any desktop; otherwise tokenize).
- The Operate dark token set is defined twice (media query and `[data-theme="dark"]`); keep them in sync or dedupe.
- Note: a reviewer claimed "Mute mic" does not exist in the app. It does (`RecordingBar.swift` has `micMuteButton` and `toggleMicMute`), so leave it.

## Design system drift (from DESIGN.md)

- Ember is also used for the search-match underline and the privacy "Cancelled" dots, which stretches "ember means live". Either keep as a deliberate exception or switch those to ink.
- Nav height is 68px in the build against 64px in the contract; hero h1 tops out at 5.75rem against "about 5.5rem". DESIGN.md records the built values.

## For the app redesign ("mad update")

- The mockups are proposals for every screen; nothing in `Sources/Wffl` has been changed. Use the screen-to-file mapping in `README.md`.
- The logo mark is a proposal. Decide before replacing `Support/AppIcon.icns` and the in-app wordmark.
- Verify every capability shown in the mockups against 1.9 before building (engine names and sizes, "Network: model downloads only", the call-detect nudge, speaker naming flow).
- After the redesign, re-run an Impeccable pass or `/impeccable document` so `DESIGN.md` reflects the shipped app, not the mockups.
