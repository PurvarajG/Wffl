---
name: Wffl
description: A quiet instrument for voice. Monochrome page, one soft grainy light, one working dot-matrix instrument that turns speech into words on the Mac.
colors:
  ground-light: "#F2F2F0"
  surface-light: "#FFFFFF"
  surface-2-light: "#F7F7F5"
  ink-light: "#0B0B0B"
  text-light: "#2B2B29"
  dim-light: "#6B6B67"
  soft-light: "#8A8A86"
  ground-dark: "#0A0A0A"
  surface-dark: "#151515"
  surface-2-dark: "#1B1B1B"
  ink-dark: "#F2F2F0"
  text-dark: "#D7D7D3"
  dim-dark: "#9B9B96"
  soft-dark: "#7A7A76"
  ember: "#FF5B1F"
  ember-dark: "#FF6A33"
  glow-lavender: "#9DA9F6"
  glow-peach: "#FFB27A"
  panel-light-theme: "#0B0B0B"
  panel-dark-theme: "#F2F2F0"
  app-ground-dark: "#111111"
  app-card-dark: "#1A1A1A"
  app-tone-light: "#E9E9E6"
  app-tone-dark: "#0C0C0C"
  app-secondary-light: "#666662"
  app-secondary-dark: "#AAAAA5"
  app-tertiary-light: "#6E6E69"
  app-tertiary-dark: "#8C8C87"
  app-fill-light: "rgba(0,0,0,0.05)"
  app-fill-dark: "rgba(255,255,255,0.07)"
  app-line-light: "rgba(0,0,0,0.08)"
  app-line-dark: "rgba(255,255,255,0.09)"
  app-ink-panel-light: "#0E0E0E"
  app-ink-panel-dark: "#1F1F1E"
  app-ember-text-light: "#B8390C"
  app-ember-text-dark: "#FF8A62"
  app-accent-graphite-light: "#4A4A47"
  app-accent-graphite-dark: "#6E6E6A"
typography:
  display:
    fontFamily: "Hanken Grotesk, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "clamp(3rem, 6.6vw, 5.75rem)"
    fontWeight: 400
    lineHeight: 0.98
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Hanken Grotesk, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "clamp(2.2rem, 4.6vw, 3.75rem)"
    fontWeight: 400
    lineHeight: 1.02
    letterSpacing: "-0.035em"
  title:
    fontFamily: "Hanken Grotesk, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "1.35rem to 1.5rem"
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "-0.03em"
  numeral:
    fontFamily: "Hanken Grotesk, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "clamp(2.6rem, 5vw, 4rem)"
    fontWeight: 300
    lineHeight: 1
    letterSpacing: "-0.05em"
    fontFeature: "tabular-nums"
  body:
    fontFamily: "Hanken Grotesk, Helvetica Neue, Helvetica, Arial, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Fragment Mono, ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 400
    letterSpacing: "0.02em"
  app-display:
    fontFamily: "Hanken Grotesk"
    fontSize: "34pt"
    fontWeight: 300
    letterSpacing: "-1pt"
  app-timer:
    fontFamily: "Hanken Grotesk"
    fontSize: "76pt"
    fontWeight: 300
    letterSpacing: "-3pt"
    fontFeature: "tabular-nums"
  app-heading:
    fontFamily: "Hanken Grotesk"
    fontSize: "17pt / 15pt / 13pt"
    fontWeight: 600
  app-body:
    fontFamily: "Hanken Grotesk"
    fontSize: "15pt to 17pt"
    fontWeight: 400
  app-meta:
    fontFamily: "Hanken Grotesk"
    fontSize: "11.5pt to 13pt"
    fontWeight: 400
    fontFeature: "tabular-nums"
  app-mono:
    fontFamily: "Fragment Mono"
    fontSize: "11pt to 13pt"
    fontWeight: 400
rounded:
  panel: "24px"
  live-card: "28px"
  hero-panel: "32px"
  inner: "14px"
  pill: "999px"
  app-ink-panel: "24pt"
  app-work-panel: "20pt"
  app-row: "16pt"
  app-moment: "14pt"
  app-tile: "12pt"
spacing:
  page-pad: "clamp(20px, 4vw, 48px)"
  max-width: "1280px"
  nav-height: "68px"
  section-y: "clamp(72px, 10vw, 136px)"
  app-page-inset: "32pt"
  app-page-max: "1180pt"
  app-reading-inset: "44pt"
  app-reading-max: "820pt"
  app-side-panel: "300pt"
  app-stack: "22pt"
  app-column-gap: "24pt"
components:
  button-primary:
    backgroundColor: "{colors.ink-light}"
    textColor: "{colors.ground-light}"
    typography: "{typography.body}"
    rounded: "{rounded.pill}"
    padding: "15px 28px"
  button-primary-hover:
    backgroundColor: "transparent"
    textColor: "{colors.ink-light}"
  button-small:
    backgroundColor: "{colors.ink-light}"
    textColor: "{colors.ground-light}"
    rounded: "{rounded.pill}"
    padding: "9px 18px"
  live-card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.live-card}"
    padding: "22px 24px 18px"
  journey-stage:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.live-card}"
    height: "500px"
  privacy-panel:
    backgroundColor: "{colors.panel-light-theme}"
    textColor: "{colors.ground-light}"
    rounded: "{rounded.hero-panel}"
    padding: "clamp(28px, 5vw, 64px)"
  status-pill:
    textColor: "{colors.ground-light}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "6px 14px"
  setup-numeral:
    textColor: "{colors.soft-light}"
    typography: "{typography.numeral}"
  app-ink-panel:
    backgroundColor: "{colors.app-ink-panel-light}"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.app-ink-panel}"
    padding: "28pt"
  app-work-panel:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.app-work-panel}"
    padding: "20pt"
  app-ask-field:
    backgroundColor: "rgba(255,255,255,0.08)"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.pill}"
    padding: "0 18pt"
    height: "52pt"
  app-suggestion-pill:
    backgroundColor: "transparent"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.pill}"
    padding: "6pt 12pt"
  app-suggestion-pill-selected:
    backgroundColor: "{colors.ink-dark}"
    textColor: "{colors.app-ink-panel-light}"
  app-quiet-pill:
    backgroundColor: "{colors.app-fill-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.pill}"
    padding: "6pt 12pt"
  app-quiet-pill-pressed:
    backgroundColor: "{colors.app-line-light}"
  app-record-button:
    backgroundColor: "{colors.ink-light}"
    textColor: "{colors.surface-light}"
    rounded: "{rounded.pill}"
  app-stop-button:
    backgroundColor: "{colors.ember}"
    textColor: "{colors.surface-light}"
    rounded: "{rounded.pill}"
  app-meeting-line:
    backgroundColor: "transparent"
    rounded: "{rounded.app-row}"
    padding: "10pt"
  app-meeting-line-hover:
    backgroundColor: "{colors.app-fill-light}"
  app-wave-tile:
    backgroundColor: "{colors.app-tone-light}"
    rounded: "{rounded.app-tile}"
    width: "78pt"
    height: "48pt"
---


# Design System: Wffl

Scope note: one world, two shipped expressions. Persuade is `website/index.html`. Operate is the macOS app in `Sources/Wffl` (app v2, "Ask the library"), with tokens in `Support/Theme.swift`, shared instruments and modifiers in `Views/Instruments.swift`, and the accent in the AccentColor asset. App tokens carry the `app-` prefix and are measured in points; everything without the prefix is the website. The old `mockups/` Operate notes are retired and no longer describe anything.

## Overview

**Creative North Star: "The Quiet Instrument"**

A monochrome page with exactly one soft, grainy light and one working instrument: a dot-matrix voice field that resolves speech into words, on the Mac, offline. The page behaves like a well-made piece of audio hardware: calm, exact, a little tactile, never loud. Black, white and graphite carry everything; ember orange appears only where something is live.

Density is low and the type is light. Display type is Hanken Grotesk at regular and light weights with tight negative tracking, with the second clause of a headline stepped down to mid-grey. Surfaces are white panels with generous radii on a cool off-white ground; buttons and tags are pills. Fragment Mono is kept for small captions, timecodes and status words so that machine voice stays small and human voice stays large.

The same world runs in Operate mode in the Mac app, which inherits the type, palette and instruments but none of the website's layout. The app is native first: a `NavigationSplitView` sidebar, a toolbar carrying a segmented control and the one prominent Record button, and a native inspector. The world shows up inside that frame as one near-black ink panel carrying the only grained glow, white 20 pt work panels on cool paper, tone steps instead of borders, capsule waveforms and the dot field. Dark mode is a true counterpart (near-black ground, off-white ink), not an afterthought.

**Key Characteristics:**
- Monochrome by default; one accent (ember), one light (the glow), one instrument (the dot field).
- Light-weight display type and light large numerals; weight 400 is the heaviest display weight.
- Pills for every button and tag; 24px to 32px panels on the site; 20 pt work panels and one 24 pt ink panel in the app.
- Soft ambient shadows only; depth from white-on-grey tonal layering. In the app, tone steps replace borders.
- Motion that resolves (blur to sharp, dot to word) and reveals once; everything honors reduced motion.

## Colors

A cool monochrome with a single warm ember, and a blurred orange, peach and lavender light used as atmosphere. Every token has a light and a dark value; the dark set is the same hierarchy inverted, not a different palette.

### Primary
- **Ember** (#FF5B1F light, #FF6A33 dark): the only accent. Used for the live lamp, the recording playhead, the top scroll-progress hairline, the search-match underline, status dots in the privacy panel, and as a colour inside the glow. Never a button fill, never body text.

### Neutral
- **Cool Paper** (#F2F2F0 light, #0A0A0A dark): the page ground. Also the ink colour on inverted panels and black buttons.
- **Surface White** (#FFFFFF light, #151515 dark): live card, journey stage, Operate cards. **Surface Two** (#F7F7F5 / #1B1B1B) for segmented controls and the search pill.
- **True Ink** (#0B0B0B light, #F2F2F0 dark): headings, numerals, dots, primary button fill.
- **Graphite Text** (#2B2B29 / #D7D7D3): body copy and lede.
- **Dim** (#6B6B67 / #9B9B96): captions, descriptions, secondary lines.
- **Soft** (#8A8A86 / #7A7A76): the grey second line of a headline, setup numerals before they reveal, placeholders.
- **Hairlines**: ink at 9% opacity for dividers, 16% for stronger edges (18% in dark).
- **Inverted panel tokens**: the privacy panel uses panel-bg #0B0B0B with ink #F2F2F0 in light theme, and swaps to #F2F2F0 with #0B0B0B ink in dark theme. Dim text on it is the panel ink at 62% to 64%; its lines are the ink at 14%.
- **Glow colours**: lavender #9DA9F6 and peach #FFB27A, only ever inside the glow gradient, with ember. Glow opacity is 0.9 in light and 0.8 in dark on the site; the privacy panel and journey bed use fractions of it.

### App (Operate) palette
Every app colour is an appearance-adaptive pair; secondary, tertiary, muted and the legacy hairline also carry Increase Contrast values in `Theme.swift`.
- **App ground** (Cool Paper light, app-ground-dark #111111): every detail page and the window background. Slightly lifted from the website's #0A0A0A so the dark ink panel can sit below it.
- **Work panel white** (surface-light, app-card-dark #1A1A1A): open action items, notes, readiness, action-item groups.
- **Tone** (app-tone-light/dark): the raised step for waveform tiles, the note field, and non-Me speaker dots. Fill and Line are ink-alpha (5%/7% and 8%/9%): Fill is hover and the quiet pill's resting fill, Line is pressed state, the drop zone dash and the divider between search moments.
- **Ink panel** (app-ink-panel-light #0E0E0E, graphite #1F1F1E in dark): Ask header and the recording instrument. Its text is Cool Paper, its dim text Cool Paper at 64%, its lines white at 14%; it is forced into the dark colour scheme.
- **Text ladder**: ink, body (text-light/dark), secondary (#666662 / #AAAAA5) for gists and descriptions, tertiary (#6E6E69 / #8C8C87) for meta, timecodes at rest and hints.
- **Ember text** (#B8390C / #FF8A62): ember darkened for legible small text. It marks "today" in meeting meta, the timecode of a search moment, and the current line's timecode in a transcript. Raw ember (`Theme.live`) is for lamps, the newest dot-field columns, the search-match underline and the Stop & Save fill.
- **Graphite accent** (AccentColor #4A4A47 / #6E6E6A): system selection, focus and native controls. Never blue, never ember. Selection belongs to graphite; ember is never selection.

### Named Rules
**The Ember Means Live Rule.** Ember marks something that is live, moving or located (recording lamp, playhead, scroll progress, today, a match). If a state is not live, it is ink, grey or hollow.

**The One Light Rule.** One soft glow per section, blurred 50px to 80px and grained, always behind or beside a large element and never behind text smaller than a headline. A second glow in the same viewport is a defect.

**The Hairline Not Border Rule.** Separation is a 1px ink-alpha hairline or a tonal step from grey ground to white surface; never a heavy outline.

**The Tone Step Rule (app).** App surfaces separate by tone, not stroke: paper ground, white work panel, raised tone, ink-alpha fill on hover. Strokes appear only on the ink panel (white 14%) and the dashed drop zone.

## Typography

**Display Font:** Hanken Grotesk (with Helvetica Neue, Helvetica, Arial), self-hosted variable woff2, weight axis 100 to 900.
**Body Font:** Hanken Grotesk.
**Label/Mono Font:** Fragment Mono (with ui-monospace, SF Mono, Menlo), 400 only, self-hosted.

**Character:** A friendly neo-grotesque used light and large against a tiny technical mono. The contrast of scale, not of weight, does the hierarchy.

### Hierarchy
- **Display** (400, clamp(3rem, 6.6vw, 5.75rem), 0.98, -0.04em): hero headline and closing statement (closing up to 6rem). The first clause may be ink with the second in Soft grey.
- **Headline** (400, clamp(2.2rem, 4.6vw, 3.75rem), 1.02, -0.035em): section titles. Chapter titles in the journey are 400 at clamp(2rem, 3.4vw, 3rem).
- **Title** (500, 1.35rem to 1.5rem, 1.15, -0.03em): privacy destinations, setup step titles, topic headings.
- **Numeral** (300, clamp(2.6rem, 5vw, 4rem), 1, -0.05em, tabular): setup numerals 01 to 03. The live timer is 300 at clamp(2.6rem, 4.6vw, 3.75rem); the journey timecode is 300 at 1.5rem; The app's recording timer is 300 at 76 pt.
- **Body** (400, 17px, 1.55): paragraphs; section sub-lines 1.15rem in Dim, capped near 48ch; lede capped at 30ch.
- **Label** (Fragment Mono 400, 12px, 0.02em, sentence case): captions, timecodes, speaker tags, dates, status words. Minimum size 11px.

### App (Operate) hierarchy
`Theme.display` is Hanken Grotesk light (300); `Theme.text` is Hanken at a given weight; `Theme.mono` is Fragment Mono. Both faces are bundled and registered in `AppFonts`.
- **Page title** (300, 34 pt, tracking -1): "What do you want to find?", Action items, Audio files, the editable meeting title. 28 pt (-0.6) for the multiple-selection state, 22 pt for top-level summary headings.
- **Timer** (300, 76 pt, tracking -3, tabular): the live recording clock on the ink panel.
- **Heading** (600, 17 / 15 / 13 pt, ink): section heads (Recent, Decisions, Live transcript) at 17; panel heads (Open action items, Notes) at 15; inspector groups at 13.
- **Body** (400): summary overview 17 pt with 6 pt extra leading; transcript and moment lines 16 pt; summary bullets and decisions 15 pt; panel text 13 pt. The newest live transcript line steps up to 20 pt ink.
- **Meta** (400, 11.5 to 13.5 pt, tabular figures): day and length, owners and due dates, meeting meta line. Speaker names are 12.5 pt semibold.
- **Mono** (Fragment Mono, 11 to 13 pt): only clock-style numbers: timecodes, elapsed time, playback position and duration, playback rate, counts and percentages, the ⌘F hint.

### Named Rules
**The Mono Is Captions Rule.** Fragment Mono carries only captions, timecodes, speaker labels, dates and status words, at 11 to 12px. It never sets a sentence people are meant to read, a heading or a button. In the app it narrows further to clock-style numbers and counts; dates and lengths in prose meta stay Hanken with tabular figures.

**The Light Numeral Rule.** Large numbers (timers, setup numerals, counts) are weight 300 with tabular figures and tight tracking. Bold numerals are off-system.

## Layout

A 1280px max-width container with fluid side padding (clamp(20px, 4vw, 48px)) and sections spaced clamp(72px, 10vw, 136px). The nav is one sticky line at 68px with 82% ground blur: waveform mark and wordmark left, Features and Privacy links and a small pill Download right.

The hero is a 6/6 column split (single column under 960px): headline, lede, pill CTA and quiet text link left; the live card floating over the glow right, filling at least one viewport height. The journey is a 5/7 split on desktop: chapter text with a vertical rail left, a sticky 500px stage right (stage stacks and sticks under the nav on narrow screens, with scene height min(440px, 54dvh)). Setup is a four-column row on desktop: numeral, title, description, a right-aligned "via" note. Content measures are explicit: lede 30ch, section sub-lines 48ch, chapter copy 38ch, setup copy 54ch.

**App (Operate).** A native `NavigationSplitView`: sidebar 220 to 340 pt (ideal 252) with Ask, Action Items, Audio Files, then recent meetings grouped by day, and a privacy line pinned at its foot; a live recording row appears at the top of the list while recording. The toolbar background is hidden so the paper runs to the top; it carries the segmented Summary / Transcript / Notes control (270 pt, principal) on a meeting, and the single prominent Record button (or the live clock, mute, pause and Stop & Save while recording). Meetings open a native inspector at 240 to 340 pt (ideal 272).

Two columns govern page content. The **page column** (Ask, Action Items, Audio Files, Recording) is 32 pt side inset, 18 pt top, 32 pt bottom, max 1180 pt, left-aligned. The **reading column** (a meeting's summary, transcript and notes) is 44 pt inset with text capped at 820 pt; Action Items also caps at 820. Page stacks are spaced 22 pt; a main column beside a 300 pt side panel (open action items, recording notes) sits 24 pt away. Lines of prose are capped at 520 to 560 pt. The playback bar floats as a bottom safe-area inset, 14 pt off the edge, and content reserves 90 pt beneath it.

## Elevation & Depth

Hybrid, mostly tonal. White surfaces sit on grey ground, and a single soft ambient shadow lifts floating cards. Light: `0 1px 2px rgba(20,12,4,0.04), 0 24px 70px rgba(40,20,0,0.10)`; dark: `0 1px 2px rgba(0,0,0,0.4), 0 24px 70px rgba(0,0,0,0.5)`. There are no hard offset shadows and no colored shadows.

**App (Operate).** Work panels carry one soft lift: black 4% at radius 1, y 1, plus black 6% at radius 14, y 8. Floating ink capsules (toast, meeting-detected banner) use black 18% at radius 16, y 8. The playback bar is Liquid Glass on macOS 26 and regular material before. The ink panel has no shadow; it is depth by value. Everything else is flat tone.

Atmosphere comes from the glow with a grain overlay (SVG fractal noise at 35% opacity, soft-light blend), not from shadow. Hero and closing glows fade into the ground over a 160px gradient at the section bottom.

### Named Rules
**The Glow Plus Grain Rule.** The glow is a blurred stack of lavender, ember and peach radial gradients always paired with the grain overlay. Glow without grain looks like a generic gradient; grain without glow is dirt.

**The Soft Lift Rule.** Shadows are wide, low-opacity and ambient. If a shadow has a visible edge, it is wrong.

**The One Grained Glow Rule (app).** `GrainGlow` (lavender 55%, ember 35%, peach 40% radial gradients plus a 160 px noise tile at 9% overlay) appears at most once per window, inside the Ask ink panel at strength 0.9. The recording instrument is ink without glow.

## Shapes

Roundness scales with size and role. Hero-adjacent and privacy panels are 28px and 32px; standard panels are 24px; inner surfaces are 14px. In the app, all rounded rectangles are continuous: ink panel 24 pt, work panels and the drop zone 20 pt, meeting rows 16 pt, search moments 14 pt, waveform tiles, the note field and transcript flash 12 pt; every button, suggestion, search field, tag and floating bar is a capsule. Every button, tag, status pill, segmented control, search field and selected nav row is a full pill (999px). Dots, lamps, markers and speaker initials are circles. The brand mark is eight vertical ellipses (rx 3.4) whose heights trace a W; in the app it is eight capsules (`WMarkView`). Waveform bars are capsules with radius half their width.

### Named Rules
**The Pill Rule.** Anything clickable and any short label is a pill. Rectangles with small radii are for content surfaces only.

## Components

### Buttons
- **Shape:** full pill (999px).
- **Primary:** True Ink fill with Cool Paper text (swapped in dark), 1px border in the fill colour, 16px/600 label, padding 15px 28px. Small variant 9px 18px at 14px. The single label for the main action is "Download for macOS".
- **Hover:** fill becomes transparent and text becomes ink, leaving the outline. 200ms ease on background and colour. Active scales to 0.98.
- **Quiet link:** the secondary action ("View source") is a plain 16px/500 text link, not a second button.
- **App:** native buttons. Record is the one prominent toolbar button, tinted ink (glass prominent on macOS 26, bordered prominent before). While recording, Stop & Save is the same control tinted ember, the one ember fill in the app because it is the live control. Secondary page actions are `QuietPill` (12.5 pt medium ink, 12 by 6 pt, Fill at rest, Line pressed). Import Audio uses glass (bordered before macOS 26). The ⌘F hint is a mono 11 pt capsule outlined in panel line.

### Live card (hero instrument)
White, 28px radius, soft lift. Top row: ember lamp (9px, pulsing at 1.8s while live) with a mono caption ("Recording", then "Saved"). Below: a 300-weight timer, a 148px canvas dot field (46 columns by 9 rows, ink dots, a travelling pair of ember dots on the active column), the last two or three transcript lines (mono speaker tag, 16px text, past lines at 66% opacity), and a hairline footer with two mono captions. A caption under the card states the content is a sample.

### Journey stage with scenes
A sticky white 28px-radius stage with a lamp, a mono state caption and a light timecode in its header. Six scenes share it and cross-fade: microphone and system dot rows with an equalizer, resolving transcript, speaker pills renaming, raw to cleaned segmented control with filler strike-through, minutes with action items, and a pill search with highlighted matches. A glow bed sits behind the stage and drifts per chapter.

### Rail and chapter markers
A 1px vertical hairline with an ink fill that scales with progress; each chapter has a hollow 11px marker that fills ink and scales to 1.3 when active. Inactive chapter copy sits at 34% opacity. Each chapter leads with a mono timecode, then a headline, a Dim paragraph and a small "via" note.

### Privacy panel with status pills
One deliberate inverted panel (32px radius) inside the page, with its own glow and grain. A table lists each place audio could go with what happens instead and a mono status pill (outlined pill, 7px dot: ember dot for "Cancelled", hollow dot for "Off by default"). Rows slide in and dots scale up once on first view; under 760px the table becomes stacked blocks.

### Setup rows
Large light numerals (01 to 03) in Soft grey that darken to ink as each row reveals, a 500-weight title, Dim description and a right-aligned note, separated by 16% hairlines top and bottom.

### Closing
Oversized display statement (up to 6rem, second line Soft grey), a pill CTA and a fine-print line, over a single glow with grain.

### App: Ask ink panel
Ink panel, 28 pt padding, 24 pt corners, the one grained glow. Page title on Cool Paper, then the ask field 18 pt below: a 52 pt capsule, white 8% (11% focused), panel-line stroke (white 42% when focused, 150 ms ease-out), 15 pt magnifier, 18 pt Hanken input, dim prompt "A word, a decision, a name", ⌘F hint. Suggestion pills 14 pt below (12.5 pt, 12 by 6 pt, panel-line outline; selected fills Cool Paper with ink text), and a dim count of what is searchable on the right. With no meetings the panel invites the first recording instead, with an inverted prominent Start Recording and a bordered Import.

### App: Meeting line and search moment
A meeting row: 78 by 48 pt tone tile holding a 12-bar `WaveTile` (3 pt capsules, ink 70%), title 14.5 pt semibold, gist 13 pt secondary, speaker dots (20 pt, overlapping, Me in ink) and meta on the right; 10 pt padding, Fill on hover in a 16 pt row. A search moment: ember-text mono timecode in a 46 pt column, the 16 pt line with matches set in ink and underlined in ember, a 12 pt tertiary "who, in which meeting, when" line, a play glyph that inks on hover; 14 pt rows with Line dividers inset 76 pt. Clicking opens the transcript at that line.

### App: Recording instrument
Ink panel (28 by 22 pt padding, 24 pt corners, no glow): state lamp (8 pt `LiveDot`, pulsing at 0.9 s, still under Reduce Motion) with a 13 pt semibold state word in ember while recording, sources in dim, the 76 pt timer, and a `DotMatrix` 92 pt tall (9 rows, 56 columns of history, 6 pt dots, newest three columns ember while live, 45% opacity when paused). Below: the live transcript as the main column and a 300 pt Notes work panel with a tone note field and a Bookmark quiet pill.

### App: Playback bar and inspector
The playback bar is a floating glass capsule (18 by 10 pt): play, mono position, a 300 by 22 pt `WaveStrip` (96 capsule bars of 2 pt, played in ink, rest tertiary 60%, 1.5 pt ink playhead, drag to seek), mono duration and rate. The inspector stays native: 13 pt heading groups (Speakers with a 3 pt share bar, Recording, Summary, How it was transcribed), key-value rows at 12.5 pt.

### App: Floating notices
Toast and meeting-detected banner are ink-panel capsules (18 by 11 pt and 16 by 10 pt) with Cool Paper text and the floating shadow, anchored bottom and top of the window.

### Motion system
Website:
- **Hero entrance:** headline lines, lede, CTA and card rise 18px with a 6px blur to sharp over 900ms on a strong ease-out (cubic-bezier(0.16, 1, 0.3, 1)), staggered 60 to 520ms.
- **Dot field and words:** the field runs only while on screen and recording; each transcript word un-blurs in (420ms) as the field swells and settles, then the lamp stops, the caption becomes "Saved" and the field falls quiet. Hovering the card pauses it.
- **Journey transitions:** scenes cross-fade with a 14px rise and 6px blur over 600 to 800ms; the timecode tweens between chapter times (00:00, 00:41, 47:12, 47:20, 47:34, 47:41) over 900ms with ease-out cubic; inner scene animations (word resolve, pill rename, filler strike, minutes, search typing) restart on each entry.
- **Progress hairline:** a 2px ember bar fixed to the top, scaled by scroll via scroll-driven animation when supported; the hero glow drifts up 14% across the first viewport.
- **Once-only reveals:** privacy rows and setup rows reveal once via IntersectionObserver and stay.
- **Reduced motion:** all animation and transition is disabled; the dot field draws one static frame, the timecode jumps without tweening, reveals are not hidden, and smooth scrolling is off.

App: state transitions run 150 to 250 ms ease-out (focus ring 150 ms, transcript autoscroll 200 ms). The live dot field, at 80 ms per tick, is the one moving instrument; the ember lamp pulses only while recording and never under Reduce Motion.

## Do's and Don'ts

### Do:
- **Do** keep pages monochrome and let ember appear only for live state (The Ember Means Live Rule).
- **Do** place one glow with grain per section, beside or behind a large element (The One Light Rule).
- **Do** make every button and tag a pill, and every content panel 20px to 32px.
- **Do** set display type at weight 300 to 400 with negative tracking, and large numerals at 300 with tabular figures.
- **Do** keep Fragment Mono for captions, timecodes, speaker labels, dates and status words at 11 to 12px.
- **Do** label sample content as sample, and drive state changes (live, saved, cancelled) with words as well as colour.
- **Do** ship every animated moment with a reduced-motion fallback that shows the end state.
- **Do** in the app, keep native structure (sidebar, toolbar, segmented control, inspector) and let the world live inside it: one ink panel per page, white 20 pt work panels, tone steps instead of borders.
- **Do** in the app, use the shared page column (32 pt inset, max 1180 pt) for library pages and the reading column (44 pt, 820 pt) for a meeting.
- **Do** in the app, give each screen one prominent toolbar action (Record, ink; Stop & Save, ember while live) and make in-page secondary actions QuietPills.
- **Do** in the app, leave selection and focus to the graphite AccentColor.

### Don't:
- **Don't** put ember on buttons, headings, body text or decoration. The single exception is the app's Stop & Save toolbar button while a recording is live.
- **Don't** place a glow behind text smaller than a headline, or stack two glows in one viewport.
- **Don't** use bold display weights, system display faces, or hard offset shadows.
- **Don't** use a second accent colour; lavender and peach exist only inside the glow.
- **Don't** use the departures-poster language it replaced: yellow blocks, Archivo, square-cornered tiles.
- **Don't** add a second grained glow to an app window, or put the glow on a work panel.
- **Don't** outline app panels or rows; use Fill, tone or the work-panel lift.

### Not canonized
Defects and drift that the build carries and that future surfaces should not inherit: the hero caption row and mono state words are the only mono in the hero (do not add small uppercase labels above headings); ember is also used for the privacy "Cancelled" dots, which stretch the Ember Means Live Rule and should not be copied to new states. In the app: peach used as text for the recording audio warning (lavender and peach belong only inside the glow); system-blue `.link` buttons (Show in Finder, All action items, the What's New sidebar link) that bypass graphite; a 10.5 pt mono summary note in the inspector under the 11 pt floor; a 0.4 s transcript-flash fade outside the 150 to 250 ms grammar; and the legacy bordered `wfflCard` / `Theme.hairline` / `accentSoft` still used by Settings and the welcome film, which predate the tone-step rule.
