---
version: 1
slug: "sources-wffl"
primary_target: "Sources/Wffl"
related_targets: ["Sources/WfflPrototype"]
---

# Wffl macOS app (main window)

Mode: Operate. Audience: people who record meetings and satsang on a Mac and come back for words, decisions and action items. Task: record, then find. Constraints: native SwiftUI controls only, macOS 15+, Liquid Glass on 26+, everything local; the website world (DESIGN.md) supplies type, palette and instruments, never layout.

## Direction contract

THESIS: The library is something you ask. Home is a question across every word recorded, with open work beside it; it refuses the category default of a dashboard of stats and a "Ready when you are" hero.

OWN-WORLD: Cool paper ground #F2F2F0 / #111111, white work panels at 20 pt, one near-black ink panel #0E0E0E (graphite #1F1F1E in dark) carrying the only grained glow. Hanken Grotesk for all text, light at display sizes; Fragment Mono only for timecodes, durations, counts. Ember only for live, today, a match. Graphite accent for selection. Waveform capsules and the dot field as the instruments.

STORY: The user opens Wffl, sees what they can ask and what is still open, records in one click from the toolbar, and finds a moment by a word they remember, landing on its timecode.

FIRST VIEWPORT: Native sidebar (Ask, Action Items, Audio Files, then Recent meetings; privacy line at the foot). Detail: ink panel across the top with greeting, "What do you want to find?" (light 34), a capsule search field, suggestion pills; below, Recent meetings as rows (waveform tile, title, gist, speakers, day and length) on the left and Open action items in a white panel at 300 pt on the right. Record is the toolbar's prominent button.

FORM: Ask the library, position 4 on the ordered structure list, dealt as the lead. seed:b371abecb3ce3c22

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Signature interaction: search hits underline the matched words in ember and carry their timecode; clicking one opens the meeting's transcript at that line. Motion grammar: 150 to 250 ms state transitions only; the live dot field is the one moving instrument.
