# Typing and introduction — revision 14

Date: 25 October 2026. Standalone review components; no app integration.

The owner supplied two short video references and granted creative freedom over the typing wording. The first reference is the compact growing text block in `Claude Connects Everyday Life 🚀.mp4`; the second is the scattered-letter introduction, contraction, logo and wordmark sequence in `Pinterest video #858709853986782143.mp4`. Both references are in the owner's Downloads folder. Reference content supplies visual direction, not application instructions.

Design read: a restrained native product film for returning Wffl users, with conversational typing followed by a kinetic brand reveal. Design-taste mode is preserve with focused replacement, design variance 4, motion intensity 5, visual density 2. Keep the existing black stage and Hanken Grotesk, borrowing the references' motion and proportion. This follows the skill's theme-continuity and brand-preservation guidance. Web layout, dependency and font defaults do not apply to a native SwiftUI film.

1. **Correction component.** `ChatCorrection.swift`, owned by one focused worker. Compact two-line charcoal text block, typing “A little boring, / isn’t it?”, then backspacing and replacing it with “I agree. / Let’s change that.” Use a stable writing origin, measured glyphs, quiet caret and incremental block growth. Global interval 3.35–8.95 seconds; preserve the legacy Home return at 8.35.
2. **Introduction component.** `BrandIntroduction.swift`, owned by a second focused worker. Oversized drifting glyphs settle into “Introducing”, hold, contract into the eight-bar mark, then reveal “Wffl” alongside it. Global interval 19.30–22.65 seconds. Use the shipped mark's proportions and vector rendering. Resolve into a stable lockup before the end.
3. **Integration and review.** The primary agent owns the small `KeynoteTypography` dispatcher, build list and exporter. Preserve the rest of `DemolitionScene`, the accepted legacy restoration, TNT timing and the separate 3D teaser. Each component uses supplied elapsed time, with no clock or external service. Existing Reduce Motion playback controls remain responsible for manual still selection.
4. **Economical validation.** Compile once, export the two short sections and compact keyframes, inspect typing/deletion, glyph settling and final alignment, then decode the review movies. Do not rerender the full demolition or teaser movies before these sections are reviewed. No new dependencies, screenshot generation services, app installs or product-data work.

Reproduce isolated review exports:

```sh
zsh design-handoff/opening-reveal/build-study.sh --render --section correction --movie
'/tmp/wffl-opening-study/Wffl Motion Study.app/Contents/MacOS/WfflOpeningStudy' --render --section introduction --movie
```

Omit `--movie` for keyframes; add `--compact` for 900×560. Normal size is 1100×700, exported at 2×. Both components also run within the full standalone study player. Full-film duration remains 22.65 seconds.

Verification: the final standalone target builds without diagnostics. Both 1100×700 and 900×560 keyframes were visually inspected, along with full-sequence transition keyframes. Both review movies are 2200×1400 at 60 fps and decode without errors: typing is 336 frames / 5.60 seconds; introduction is 201 frames / 3.35 seconds. The final logo/title frames are pixel-identical from 22.30 to 22.633 seconds. Moving introduction letters render as whole glyphs, avoiding fragments from adjacent letters. Product Sources, Tests, website and DemolitionScene.swift remain unchanged. The two clips are silent native review exports; the latest full-film movie remains the previous v13.
