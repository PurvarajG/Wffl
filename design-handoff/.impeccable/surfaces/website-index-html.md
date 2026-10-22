---
version: 1
slug: "website-index-html"
primary_target: "website/index.html"
related_targets: ["mockups/index.html"]
---

## Scope

Surface: website/index.html (public landing page). Mode: Persuade. Visitor: a Mac user who records meetings and distrusts uploading audio. Action: download the DMG (one label, "Download for macOS"). Proof: the product transcribing in front of them with no network involved; no testimonials, customers or benchmarks exist and none are invented. Sample transcript content is labeled as sample.

Companion: mockups/index.html (Operate mode mockups of every app screen in the same world; the app source is not touched).

Revision 2 (2026-10-21): the user rejected the yellow Swiss "departures poster" world (colour scheme and block system) and supplied a reference folder (~/Downloads/Wffl Inspo): monochrome black/white/light-grey interfaces, soft blurred orange and lavender light with grain, waveform and elliptical-bar logos, dot-matrix instruments, light-weight large numerals, big radii, small mono captions. The user-pinned direction beats the roll; no concept-seed was run for this revision.

## Direction contract

THESIS: A quiet instrument for voice. A monochrome page with exactly one soft, grainy light (ember orange into cool lavender) and one working instrument: a dot-matrix "voice" field that resolves speech into words, on the Mac, offline. It refuses the category default (centered logo, tagline, chips, three equal icon cards, fake window screenshot) and the previous yellow block system.

OWN-WORLD: Cool off-white ground (#F2F2F0) with true black ink and graphite greys; white surfaces with 24px radius; pill buttons and tags; hairlines at 8% black. Dark mode is near-black (#0A0A0A) with off-white ink. One accent, ember orange (#FF5B1F), used only for the live lamp, the playhead and the glow. The glow is a blurred orange, peach and lavender light with a grain overlay, used at most once per section and never behind text smaller than a headline. Hanken Grotesk at light and regular weights for display, with light large numerals; Fragment Mono at 11 to 12px only for captions, timecodes and status words. Waveform mark: eight vertical ellipses whose heights trace a W.

STORY: The visitor watches words resolve out of a dot field with a "Transcribing on this Mac" line under it, understands what the product does and that it is local, then reads a privacy panel that lists each place audio could go and marks it cancelled, and downloads the DMG.

FIRST VIEWPORT: Left 6 columns: headline "Meetings, kept private." in light-weight Hanken at about 5.5rem, second line in mid-grey, one 14-word lede, a black pill Download button and a quiet View source link. Right 6 columns: a white 28px-radius live card floating over the soft glow: mono caption and ember lamp, a big light timer, a dot-matrix voice field, and the last three transcript lines resolving word by word, then "Saved". Nav is one line at 64px: waveform mark and wordmark left; Features, Privacy and a pill Download right.

FORM: Monochrome modernist voice instrument, derived from the user's inspiration folder (user-pinned, no seed). Not from the dealt roll.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Revision 3 (2026-10-21): the user liked the monochrome direction and asked for a final site with motion and a journey feel. The features section became a scroll-driven journey through one meeting: six chapters (record, transcribe, name speakers, clean up, write minutes, keep and find), a sticky stage whose scene changes with the active chapter, a timecode that runs from 00:00 to 47:41, a vertical rail, and a top progress hairline. Hero entrance, privacy rows and setup numerals reveal once. Everything honors reduced motion.

## Unresolved

Image generation is unavailable, so the build is code-led and the grain and glow are CSS. The waveform mark replaces the old W stroke mark as a proposal; the old mark is kept in git history. The dark-section question (privacy panel inverts inside the page) is one deliberate inversion, not a theme flip.
