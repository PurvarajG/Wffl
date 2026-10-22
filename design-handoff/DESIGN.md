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
  operate-stage: "#DCDCD8"
  operate-sidebar: "#E9E9E6"
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
rounded:
  panel: "24px"
  live-card: "28px"
  hero-panel: "32px"
  inner: "14px"
  operate-card: "20px"
  pill: "999px"
spacing:
  page-pad: "clamp(20px, 4vw, 48px)"
  max-width: "1280px"
  nav-height: "68px"
  section-y: "clamp(72px, 10vw, 136px)"
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
  operate-nav-selected:
    backgroundColor: "{colors.ink-light}"
    textColor: "{colors.ground-light}"
    rounded: "{rounded.pill}"
    padding: "8px 14px"
  operate-card:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.operate-card}"
---

# Design System: Wffl

Scope note: this system is built and shipped in `website/index.html` (Persuade) and `mockups/index.html` (Operate mockups plus a clickable prototype). The real macOS app in `Sources/Wffl` has not been redesigned; nothing here describes its current look.

## Overview

**Creative North Star: "The Quiet Instrument"**

A monochrome page with exactly one soft, grainy light and one working instrument: a dot-matrix voice field that resolves speech into words, on the Mac, offline. The page behaves like a well-made piece of audio hardware: calm, exact, a little tactile, never loud. Black, white and graphite carry everything; ember orange appears only where something is live.

Density is low and the type is light. Display type is Hanken Grotesk at regular and light weights with tight negative tracking, with the second clause of a headline stepped down to mid-grey. Surfaces are white panels with generous radii on a cool off-white ground; buttons and tags are pills. Fragment Mono is kept for small captions, timecodes and status words so that machine voice stays small and human voice stays large.

The same world runs in Operate mode for the app mockups: a light grey working surface, black pill for the selected row and primary action, ember only for "recording is live". Dark mode is a true counterpart (near-black ground, off-white ink), not an afterthought.

**Key Characteristics:**
- Monochrome by default; one accent (ember), one light (the glow), one instrument (the dot field).
- Light-weight display type and light large numerals; weight 400 is the heaviest display weight.
- Pills for every button and tag; 24px to 32px panels; 14px inner surfaces.
- Soft ambient shadows only; depth from white-on-grey tonal layering.
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
- **Hairlines**: ink at 9% opacity for dividers, 16% for stronger edges (18% in dark); 8% in Operate.
- **Inverted panel tokens**: the privacy panel uses panel-bg #0B0B0B with ink #F2F2F0 in light theme, and swaps to #F2F2F0 with #0B0B0B ink in dark theme. Dim text on it is the panel ink at 62% to 64%; its lines are the ink at 14%.
- **Operate surfaces** (mockups only): stage #DCDCD8 behind the window, working surface #F2F2F0, sidebar #E9E9E6; dark equivalents #1A1A1A stage, #0F0F0F working surface, #0A0A0A sidebar, #181818 cards.
- **Glow colours**: lavender #9DA9F6 and peach #FFB27A, only ever inside the glow gradient, with ember. Glow opacity is 0.9 in light and 0.8 in dark on the site (0.85 and 0.5 in Operate); the privacy panel and journey bed use fractions of it.

### Named Rules
**The Ember Means Live Rule.** Ember marks something that is live, moving or located (recording lamp, playhead, scroll progress, today, a match). If a state is not live, it is ink, grey or hollow.

**The One Light Rule.** One soft glow per section, blurred 50px to 80px and grained, always behind or beside a large element and never behind text smaller than a headline. A second glow in the same viewport is a defect.

**The Hairline Not Border Rule.** Separation is a 1px ink-alpha hairline or a tonal step from grey ground to white surface; never a heavy outline.

## Typography

**Display Font:** Hanken Grotesk (with Helvetica Neue, Helvetica, Arial), self-hosted variable woff2, weight axis 100 to 900.
**Body Font:** Hanken Grotesk.
**Label/Mono Font:** Fragment Mono (with ui-monospace, SF Mono, Menlo), 400 only, self-hosted.

**Character:** A friendly neo-grotesque used light and large against a tiny technical mono. The contrast of scale, not of weight, does the hierarchy.

### Hierarchy
- **Display** (400, clamp(3rem, 6.6vw, 5.75rem), 0.98, -0.04em): hero headline and closing statement (closing up to 6rem). The first clause may be ink with the second in Soft grey.
- **Headline** (400, clamp(2.2rem, 4.6vw, 3.75rem), 1.02, -0.035em): section titles. Chapter titles in the journey are 400 at clamp(2rem, 3.4vw, 3rem).
- **Title** (500, 1.35rem to 1.5rem, 1.15, -0.03em): privacy destinations, setup step titles, topic headings.
- **Numeral** (300, clamp(2.6rem, 5vw, 4rem), 1, -0.05em, tabular): setup numerals 01 to 03. The live timer is 300 at clamp(2.6rem, 4.6vw, 3.75rem); the journey timecode is 300 at 1.5rem; Operate uses 300 at 92px (recording) and 128px (dashboard count).
- **Body** (400, 17px, 1.55): paragraphs; section sub-lines 1.15rem in Dim, capped near 48ch; lede capped at 30ch.
- **Label** (Fragment Mono 400, 12px, 0.02em, sentence case): captions, timecodes, speaker tags, dates, status words. Minimum size 11px (Operate list metadata).

### Named Rules
**The Mono Is Captions Rule.** Fragment Mono carries only captions, timecodes, speaker labels, dates and status words, at 11 to 12px. It never sets a sentence people are meant to read, a heading or a button.

**The Light Numeral Rule.** Large numbers (timers, setup numerals, counts) are weight 300 with tabular figures and tight tracking. Bold numerals are off-system.

## Layout

A 1280px max-width container with fluid side padding (clamp(20px, 4vw, 48px)) and sections spaced clamp(72px, 10vw, 136px). The nav is one sticky line at 68px with 82% ground blur: waveform mark and wordmark left, Features and Privacy links and a small pill Download right.

The hero is a 6/6 column split (single column under 960px): headline, lede, pill CTA and quiet text link left; the live card floating over the glow right, filling at least one viewport height. The journey is a 5/7 split on desktop: chapter text with a vertical rail left, a sticky 500px stage right (stage stacks and sticks under the nav on narrow screens, with scene height min(440px, 54dvh)). Setup is a four-column row on desktop: numeral, title, description, a right-aligned "via" note. Content measures are explicit: lede 30ch, section sub-lines 48ch, chapter copy 38ch, setup copy 54ch.

Operate mockups use a fixed 1240 by 780 window, a 232px sidebar and a content area with 32px to 64px inner padding, scaled to fit the gallery.

## Elevation & Depth

Hybrid, mostly tonal. White surfaces sit on grey ground, and a single soft ambient shadow lifts floating cards. Light: `0 1px 2px rgba(20,12,4,0.04), 0 24px 70px rgba(40,20,0,0.10)`; dark: `0 1px 2px rgba(0,0,0,0.4), 0 24px 70px rgba(0,0,0,0.5)`. Operate cards use a smaller `0 1px 2px … , 0 10px 30px …` pair, and the window carries a deeper `0 36px 80px rgba(0,0,0,0.22)`. There are no hard offset shadows and no colored shadows.

Atmosphere comes from the glow with a grain overlay (SVG fractal noise at 35% opacity, soft-light blend), not from shadow. Hero and closing glows fade into the ground over a 160px gradient at the section bottom.

### Named Rules
**The Glow Plus Grain Rule.** The glow is a blurred stack of lavender, ember and peach radial gradients always paired with the grain overlay. Glow without grain looks like a generic gradient; grain without glow is dirt.

**The Soft Lift Rule.** Shadows are wide, low-opacity and ambient. If a shadow has a visible edge, it is wrong.

## Shapes

Roundness scales with size and role. Hero-adjacent and privacy panels are 28px and 32px; standard panels are 24px; inner surfaces (Operate sidebar privacy note, window, stage) are 14px; Operate cards are 20px. Every button, tag, status pill, segmented control, search field and selected nav row is a full pill (999px). Dots, lamps and markers are circles. The brand mark is eight vertical ellipses (rx 3.4) whose heights trace a W.

### Named Rules
**The Pill Rule.** Anything clickable and any short label is a pill. Rectangles with small radii are for content surfaces only.

## Components

### Buttons
- **Shape:** full pill (999px).
- **Primary:** True Ink fill with Cool Paper text (swapped in dark), 1px border in the fill colour, 16px/600 label, padding 15px 28px. Small variant 9px 18px at 14px. The single label for the main action is "Download for macOS".
- **Hover:** fill becomes transparent and text becomes ink, leaving the outline. 200ms ease on background and colour. Active scales to 0.98.
- **Quiet link:** the secondary action ("View source") is a plain 16px/500 text link, not a second button.
- **Operate:** primary is black pill; secondary is a transparent pill with a 16% hairline; a keyboard hint is a small mono outline pill.

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

### Operate mockup patterns
Sidebar #E9E9E6 with pill nav rows; the selected row is a black pill with ink-on-paper text. Primary actions are black pills. The selected list item is a white 12px-radius card. The recording screen uses a 92px light timer, a bar waveform in ink with an ember playhead and a soft ember tail, and a collapsed bar that is a black pill with an ember lamp. The dashboard uses a 128px light count, a dot calendar (ember only for today) and a hairline table. Settings and empty/error states are white 20px cards, with a faint glow allowed on the privacy banner and state cards.

### Motion system
- **Hero entrance:** headline lines, lede, CTA and card rise 18px with a 6px blur to sharp over 900ms on a strong ease-out (cubic-bezier(0.16, 1, 0.3, 1)), staggered 60 to 520ms.
- **Dot field and words:** the field runs only while on screen and recording; each transcript word un-blurs in (420ms) as the field swells and settles, then the lamp stops, the caption becomes "Saved" and the field falls quiet. Hovering the card pauses it.
- **Journey transitions:** scenes cross-fade with a 14px rise and 6px blur over 600 to 800ms; the timecode tweens between chapter times (00:00, 00:41, 47:12, 47:20, 47:34, 47:41) over 900ms with ease-out cubic; inner scene animations (word resolve, pill rename, filler strike, minutes, search typing) restart on each entry.
- **Progress hairline:** a 2px ember bar fixed to the top, scaled by scroll via scroll-driven animation when supported; the hero glow drifts up 14% across the first viewport.
- **Once-only reveals:** privacy rows and setup rows reveal once via IntersectionObserver and stay.
- **Reduced motion:** all animation and transition is disabled; the dot field draws one static frame, the timecode jumps without tweening, reveals are not hidden, and smooth scrolling is off.

## Do's and Don'ts

### Do:
- **Do** keep pages monochrome and let ember appear only for live state (The Ember Means Live Rule).
- **Do** place one glow with grain per section, beside or behind a large element (The One Light Rule).
- **Do** make every button and tag a pill, and every content panel 20px to 32px.
- **Do** set display type at weight 300 to 400 with negative tracking, and large numerals at 300 with tabular figures.
- **Do** keep Fragment Mono for captions, timecodes, speaker labels, dates and status words at 11 to 12px.
- **Do** label sample content as sample, and drive state changes (live, saved, cancelled) with words as well as colour.
- **Do** ship every animated moment with a reduced-motion fallback that shows the end state.
- **Do** in Operate surfaces, use #F2F2F0 working surface, #E9E9E6 sidebar, black pill for the selected row and primary action.

### Don't:
- **Don't** put ember on buttons, headings, body text or decoration.
- **Don't** place a glow behind text smaller than a headline, or stack two glows in one viewport.
- **Don't** use bold display weights, system display faces, or hard offset shadows.
- **Don't** use a second accent colour; lavender and peach exist only inside the glow.
- **Don't** use the departures-poster language it replaced: yellow blocks, Archivo, square-cornered tiles.
- **Don't** describe the app in `Sources/Wffl` as having this look until it is actually built.

### Not canonized
Defects and drift that the build carries and that future surfaces should not inherit: the hero caption row and mono state words are the only mono in the hero (do not add small uppercase labels above headings); ember is also used for the search-match underline and the privacy "Cancelled" dots, which stretch the Ember Means Live Rule and should not be copied to new states.
