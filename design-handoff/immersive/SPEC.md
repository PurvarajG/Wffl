# Wffl immersive journey: developer spec

Status: **approved by the owner** (visual theme and rhythm); **Revision 2** (owner feedback on space, smoothness, pace, and a full-window update film) is incorporated and supersedes older text where they conflict. Reference implementations, built and browser-verified:

- `design-handoff/immersive/index.html` — website journey (Codex)
- `design-handoff/immersive/update-story.html` — in-app update film (Sonnet; native SwiftUI port; reference timeline, scrub slider)
- `design-handoff/immersive/icon.html` — app icon direction (Sonnet)

**Rule for both developers.** This spec and the mockup agree. Every number below is taken from the mockup source. Do not "improve" values, add effects, change copy, or reorder. If a value looks wrong, build it as written and report it. Serve the mockup with `cd design-handoff && python3 -m http.server 4175` and compare side by side.

Everything not listed here is unchanged from `DESIGN.md` (tokens, Hanken Grotesk + Fragment Mono, pills, radii, ember means live only, one glow per viewport, no new accent colours).

---

# PART 1. WEBSITE (`website/index.html`, single file, no dependencies)

## REVISION 2 (owner feedback) — these items override anything below that conflicts

The owner liked the look but said (a) the pages did not use the available space, (b) animations should be smoother, (c) the pace should change by mixing in some ordinary scrolling. Therefore:

**R2.1 Structure: three pinned journeys with two normal-scroll interludes.**
```
J1 pinned  scenes 1,2   data-base 0     L 5.5   (height = (L+1)·100dvh)
I1 interlude "Engines"  normal flow, inverted ground (continues scene 2's dark)
J2 pinned  scenes 3,4   data-base 6.0   L 5.7
I2 interlude "Library"  normal flow, light ground
J3 pinned  scenes 5,6   data-base 12.2  L 4.0
```
Per journey: `u = base + clamp(−journey.getBoundingClientRect().top / innerHeight, 0, L)`. Everything in 1.2–1.5 below still uses these absolute `u` values. Removed because interludes now do the hand-off: scene 2 exit (5.4–6.3), the scene 3 sheet rise (5.5–6.3; scene 3 is simply in place at u 6.0), the scene 4 exit/pull-back (11.8–12.9) and the scene 5 iris (11.8–12.8; scene 5 is in place at u 12.2). Scene 1→2 dive/circle (2.1–3.3) and scene 5→6 bloom (14.6–15.4) stay. Visibility windows (absolute u): S1 −1…3.2, S2 2.4…∞, S3 −1…9.5, S4 8.7…∞, S5 −1…15.5, S6 14.5…∞, each only rendered while its journey is on screen (skip rendering when the journey rect is more than 20 % of the viewport off-screen).

**R2.2 Smoothing and easing (replaces 1.2 values).** Displayed `uD` chases `uT` by **0.09** per animation frame (snap < 0.0004), per journey. Easings: `in = x^2.2`, `out = 1 − (1−x)^2.6`, `io = .5 − .5·cos(πx)` (sine), `lin = x`.

**R2.3 Interludes (normal scrolling, no pin).** Each is a block with `padding: clamp(90px,18vh,200px) var(--pad)`, content max 1280 centred. Elements marked `[rv]` reveal by scroll position only: `p = seg(innerHeight·.94 − el.top, 0, innerHeight·.3, out)`, opacity `p`, `translateY((1−p)·44px)`, blur `(1−p)·5px` (none in reduced motion).
- **I1 Engines** (inverted): h2 `[rv]` `Three engines.` / `One quiet instrument.` (clamp(2.8rem,6.4vw,6rem), 1.0). Three rows `[rv]` separated by `--line-2` hairlines, padding `clamp(24px,5vh,52px)` 0, grid columns `1.15fr 1.2fr .7fr` (single column under 760px): name (300 weight, clamp(2.2rem,5.2vw,4.8rem), −.045em) / description / mono caption right-aligned:
  1. `BAPS Whisper` — `English, including Gujarati and Sanskrit vocabulary in Latin letters.` — `Optional model · about 1.6 GB`
  2. `Parakeet` — `English.` — `Optional model · about 600 MB`
  3. `Whisper` — `99 languages, and translation to English.` — `Optional model · download in Settings`
  Lead `[rv]`: `All three run on your Mac. You download a model once, from inside the app.`
- **I2 Library** (light): h2 `[rv]` `Leave the meeting.` / `Keep what matters.`; lead `[rv]` `Your recordings, transcripts and notes stay in a local library. Search the words, export Markdown, or bring in another audio file.`; a pill search field `[rv]` (max 900px, radius 999, surface fill, `--shadow`) with mono `Search` and the query typed by scroll: visible text = `"model size".slice(0, ceil(seg(innerHeight·.78 − q.top, 0, innerHeight·.22, lin)·10))` plus a caret; two result rows `[rv]` (mono `Weekly product sync · 00:58` / `We show the size first.`; `Weekly product sync · 00:49` / `The flow works, but you can’t tell how big the model is.`) with the matched word underlined 2px ink (not ember); pills `[rv]` `Export Markdown`, `Import an audio file`; caption `[rv]` `Sample library, invented for this page.`

**R2.4 Fill the space (replaces layout values in 1.5; mobile rules in 1.8 are unchanged except where noted).**
- Scene copy blocks: width `min(44rem, 100% − 2·pad)`; h2 `clamp(2.8rem,5.6vw,5.2rem)`; paragraph `clamp(1.05rem,1.35vw,1.3rem)`, max 40ch. Scene 2 h2 `clamp(2.6rem,5vw,4.6rem)`.
- **Scene 2:** plane `bottom 15vh; height 44vh`; transcript line `bottom 5vh`, `clamp(1.6rem,3.6vw,3.3rem)`; caption row sits just above the plane (`bottom calc(15vh + 44vh + 6px)`), right-aligned.
- **Scene 3:** copy left, vertically centred (`top 50%`, `translate 0 −50%`, width `min(36rem,38vw)`, h2 `clamp(2.6rem,5vw,4.6rem)`). Lanes fill the right side: `left 40%; right 0; top 68px + 8vh; bottom 9vh`. Lane pitch `clamp(70px,17vh,150px)`; lane top `44px + row·pitch`; label at lane-left 0; stream `left 128px; right pad; overflow hidden` with an inner `.sin` row (120 bars, gap `clamp(4px,.6vw,10px)`, bar width `clamp(4px,.55vw,9px)`, bar height = `pitch × f` where f = `.14 + .7·|sin(.55i+s)·cos(.21i+2s)|`, s = 1 Me, 3.3 other voice); parallax `translateX(−(u−6.3)·k·1.6 px)`, k = 8 (Me), 14 (other voice). The Rename / Speaker 2 / Priya sequence and timings are unchanged.
- **Scene 4:** copy left, vertically centred (same as scene 3). Docs column `left 44%; right pad; top 68px + 4vh; bottom 8vh`. Cards padding `clamp(24px,2.6vw,44px)`, radius 32; transcript card width `min(100%,760px)`, line text `clamp(17px,1.6vw,26px)`; minutes card `min(100%,540px)`, h3 `clamp(1.8rem,3.2vw,3rem)`, text `clamp(1rem,1.3vw,1.25rem)`. Transcript card sideways shift in phase 2 is `−p2·cardWidth·.1` (desktop).
- **Scene 5:** h2 `clamp(2.8rem,5.8vw,5.2rem)`, centred, width `min(62rem,…)`, paragraph `clamp(1.05rem,1.35vw,1.3rem)`; diagram `width min(1240px, 100% − 2·pad); height min(40vh,400px); top 62%`; Mac `min(400px,30vw)`; chips `min(290px,24vw)`, name `clamp(16px,1.5vw,22px)`, pill mono 13px padding 6×14.
- **Nav** (all pages): fixed, background `color-mix(in srgb, (--nav-bg or --bg) 55%, transparent)` + 12px backdrop blur so interlude content never collides with it. Ink flips by the block under y = 34px: J1 when `u ≥ 2.9`, I1 always, J3 when `u < 14.9`, otherwise default.
- **Caption / rail / progress:** active space is decided by the block at the vertical middle of the viewport: J1 → 1 or 2 (u ≥ 2.8), I1 → 2, J2 → 3 or 4 (u ≥ 9.0), I2 → 4, J3 → 5 or 6 (u ≥ 15.0). Progress hairline = `scrollY / (scrollHeight − innerHeight)`.
- Rail/jump targets (settle u): `[0.3, 5.3, 8.2, 11.5, 14.4, 16.2]`, each resolved to its journey: `scrollTop = journey.top + (u − base)·innerHeight`.
- `window.__setU(u)` now scrolls to the position for absolute `u` and renders it (works across journeys).

**R2.5 Acceptance additions.** (a) Between J1 and J2 the page contains a stretch of ordinary scrolling content (I1) and between J2 and J3 another (I2); there is never an empty screen. (b) At 1440×900 no scene leaves more than ~25 % of the stage as empty background outside intentional margins; lanes (scene 3), docs (scene 4) and the Mac diagram (scene 5) each use at least 55 % of stage width. (c) No frame shows more than two overlapping text blocks; nothing collides with the nav.

## 1.1 Concept

One full-bleed pinned stage. Six "spaces" are layers inside it. Scroll position is the only driver; there is no snapping, no wheel hijack, no class-switching between states. Every visual value is a pure function of one number `u`.

## 1.2 The driver (W-1 acceptance)

- `u = (window.scrollY − journey.offsetTop) / window.innerHeight`, clamped to `[0, L]`, **L = 16.2** (viewport heights).
- Markup: `<main id="journey">` with `height = (L + 1) × innerHeight` (px, recomputed on resize). Inside, `#stage`: `position: sticky; top: 0; height: 100dvh; overflow: hidden`. Six `<section class="sc">` absolutely fill `#stage`, later sections above earlier ones.
- Smoothing: displayed value `uD` chases the target: each `requestAnimationFrame`, `uD += (uT − uD) × 0.14`; snap when `|uT − uD| < 0.0004`. Render with `uD`. (Reduced motion: no smoothing, no pin, see 1.9.)
- Each scene has a render function `r1..r6(u)` that sets inline `opacity`, `transform`, `filter`, `clip-path` from `u` **only**. Scenes render only while their visibility window contains `u`:

| Scene | Visible when u in |
|---|---|
| 1 Silence | −∞ … 3.2 |
| 2 Voice | 2.4 … 6.4 |
| 3 Voices | 5.4 … 9.5 |
| 4 Minutes | 8.7 … 13.0 |
| 5 Mac | 11.7 … 15.5 |
| 6 Begin | 14.5 … ∞ |

  Outside the window: `visibility: hidden`.
- Helpers (use exactly): `clamp(x,0,1)`; `seg(u,a,b,ease) = ease(clamp((u−a)/(b−a)))`; `mix(a,b,t)=a+(b−a)t`. Easings: `lin: t`, `in: t³`, `out: 1−(1−t)³`, `io: t<.5 ? 4t³ : 1−(−2t+2)³/2`. Default ease is `io`.
- Test hook (keep in production, harmless): `window.__setU(u)` renders the journey at `u` without scrolling (locks the scroll listener). Reviewers will use it.

### Scroll timeline (u in viewport heights)

```
u: 0      1      2      3      4      5      6      7      8      9     10     11     12     13     14     15    16.2
S1 |=======================dive=====|
S2                        |enter|======tilt/field/words======|exit|
S3                                         |rise|==split/rename/track==|exit|
S4                                                              |doc|==clean==|==minutes==|exit pull-back|
S5                                                                                    |open|==wires/pills====|
S6                                                                                                     |bloom|=steps=|
```

## 1.3 Global chrome (fixed, outside the stage)

- **Nav** (fixed, 68px, 60px under 760px): mark (8 bars, see 1.4) + "Wffl" left; `Download for macOS` small pill right. Same label on every width. Ink flips to `--panel-ink` while the visible ground is inverted: `u ∈ [2.9, 5.9)` and `u ∈ [12.5, 14.9)`; otherwise default ink.
- **Progress hairline**: 2px ember bar fixed top, `scaleX(u / L)`, origin left. (Ember = located; allowed by DESIGN.md.)
- **Space caption** (one numbering scheme, no eyebrows/kickers anywhere): centred in the nav row, mono 12px, text `0N / 06 · Name`, N = active space. Hidden under 760px. Active space: `u ≥ 2.8 → 2`, `≥ 5.9 → 3`, `≥ 9.0 → 4`, `≥ 12.3 → 5`, `≥ 15.0 → 6`.
- **Rail** (right, desktop only, hidden under 760px): six 6px hollow dots; active = filled 9px; each is a button (`aria-label="N. Name"`) that scrolls to that space's settle position `u = [0.3, 5.3, 8.2, 11.5, 14.4, 16.2]` instantly.
- Names in order: `Silence, Voice, Voices, Minutes, Mac, Begin`.
- Brand link scrolls to top.
- "Scroll to enter" hint: mono caption + 1px line, bottom centre of scene 1, opacity `1 − seg(u,0,.25)`.
- Do not ship the grey "mockup" control bar or the Mobile-390 iframe.

## 1.4 Shared objects

- **Waveform mark (eight bars)**: `display:flex; justify-content:space-between; aspect-ratio 76.8/60`; each bar `width 8.85%`, `border-radius 999px`, `background var(--ink)`, height % of container = `[100, 66.7, 33.3, 66.7, 86.7, 66.7, 33.3, 100]`. Intro: bars start at `height 5%` and grow to full with `transition: height 1.4s cubic-bezier(.16,1,.3,1)`, delay `index × 70ms`, started right after fonts load (~60ms). Nav mark uses 22px height, 3px bars, 2px gap.
- **Glow**: `.glow` = the existing blurred lavender/ember/peach radial stack + grain, `filter: blur(70px)`, opacity `var(--glow-o)`. All gradients end at transparent inside the box (no hard rectangle edge, W-2). Max one visible per viewport: scene 1 (fades out `1 − seg(u,.4,1.6)`, drifts `translateY(−14px × u)`) and scene 6 (opacity `seg(u,14.9,15.6) × .9`). None elsewhere.
- **Inverted scenes** (2 and 5): `.inv` remaps tokens: ground `--panel-bg`, ink/text `--panel-ink`, dim `--panel-dim`, lines `--panel-line`, surface = `panel-ink 8%` mixed into `panel-bg`. In dark theme these scenes are light.
- Light theme/dark theme: tokens exactly as `DESIGN.md`. Honour `prefers-color-scheme`.

## 1.5 Scenes (desktop; mobile in 1.8). All numbers are exact.

Common: copy block `position:absolute; left: var(--pad); top: calc(68px + 6vh); width: min(34rem, 100% − 2×pad)`. `h2` = Display-headline token (400, clamp(2.2rem,4.6vw,3.75rem), 1.02, −0.035em), second clause `<span>` in `--soft`. Paragraph 1.1rem `--dim`, max 44ch. **Copy is verbatim as below.**

### Scene 1: Silence
**Layout:** two columns. Left: `h1` (400, clamp(3rem,6.6vw,5.75rem), .98, −.04em), lede, CTA row, fine print. Right: the mark in a slot `width min(40vw, 540px)` over the scene-1 glow.
**Copy:**
- h1: `Meetings,` / `kept private.` (second line `--soft`)
- lede: `Wffl records and transcribes on your Mac. Keep the words, find the decisions. Summaries are local by default.`
- CTA: pill `Download for macOS` → `https://github.com/PurvarajG/Wffl/releases/latest/download/Wffl.dmg`; quiet link `View source` → `https://github.com/PurvarajG/Wffl`
- fine: `No account required. Free and open source.`

**Scroll (u):**
- Text block: `t = seg(.5, 1.3, in)`; `opacity 1−t`, `translateY(−0.08·vh·t)`, `blur(8px·t)`.
- Mark travels to screen centre: `m = seg(.6, 1.8, io)`; `translate(dx·m, dy·m)` where (dx,dy) = vector from slot centre to viewport centre (measured at load/resize); scale `1 + .5·m`.
- "Breathing" (scroll-scrubbed, not time): each bar `scaleY(1 + .12·sin(u·7 + i·.9) · seg(.3, 2.1, lin))`.
- **Dive:** `d = seg(2.1, 3.1, in)`; total scale `(1 + .5·m) · (1 + 28·d)`, transform-origin centre of the mark (the gap between bars 4 and 5). Bars opacity `1 − seg(2.8, 3.05, lin)`. Rendered as a normal transform, no `will-change` (avoids a blurry fixed raster at 29× scale).
- Intro on load (time-based, once): bars grow as in 1.4; text rises over ≤ 900ms ease `cubic-bezier(.16,1,.3,1)`.

### Scene 2: Voice (inverted)
**Enter:** scene `clip-path: circle(R at 50% 50%)`, `R = 150vmax · seg(2.5, 3.3, in)`; `none` at ≥ 1. This is the dark "inside" the dive opens into.
**Layout:** copy top-left; dot field plane `left/right 0; bottom 20vh; height 34vh`, `transform-origin 50% 100%`; transcript line `bottom 8.5vh`; caption row `bottom calc(8.5vh − 30px)`.
**Copy:**
- h2: `Hear it.` / `See it take shape.`
- p: `Words appear in silence-aligned chunks while you record. Capture your microphone and Mac audio; pause and resume any time.`
- foot (14–15px `--dim`): `Parakeet and BAPS Whisper for English. Whisper for other languages and translation.`
- Transcript line (sample): speaker tag mono `Me` then words `So the first download needs to be clearer.` (weight 300, clamp(1.3rem, 2.6vw, 2.1rem)).
- Caption: ember lamp 9px + `Transcribing on this Mac` · timecode · `Sample`. After the playhead finishes: lamp becomes hollow and text `Saved, on this Mac`.

**Scroll:**
- Camera lands: `tilt = 68° · (1 − seg(2.9, 4.1, out))`, `scale = .72 + .28 · seg(2.9, 4.1, out)`; plane `transform: perspective(900px) rotateX(tilt) scale(scale)`; plane opacity `seg(2.9, 3.5, out)`.
- Copy: `cp = seg(3.7, 4.3, out)`: opacity `cp`, `translateY((1−cp)·24px)`, `blur((1−cp)·6px)`.
- Dot field (canvas, device-pixel-ratio capped at 2): 9 rows, 64 columns (30 on mobile). Field visibility `seg(3.2, 3.8, out)`.
  - Playhead `ph = seg(4.0, 5.3, io)`. Column at x-fraction `xf`, `d = xf − ph`, noise `n = .55 + .45·|sin(c·1.7)·cos(c·.43)|`.
  - amplitude: `d ≤ 0 ? (ph > 0 ? .78·e^(d/.22) : 0) : .1·e^(−d/.15)`; if `ph ≥ .999` amplitude 0; then `amp = amp·n·visibility + .045`; vertical extent `span = amp·4.6` rows; per-dot `k = clamp(1 − |r|/(span + .55))`, radius `R·(.35 + .65k)` with `R = min(gx, gy)·.34`, alpha `.22 + .78k`. Dots are `--ink` (inverted ink).
  - The two ember dots: the centre-row dot at the playhead column while `.001 < ph < .999`, radius ×1.35, colour `--ember`. Nothing else is ember.
- Words: word i of 8 appears with `a = seg(ph, i/8·.86, i/8·.86 + .12, out)`: `opacity a`, `blur((1−a)·6px)`.
- Timecode: `00:` + `round(mix(41, 49, ph))` padded to 2.
- **Exit:** `ex = seg(5.4, 6.3, io)`: inner content `scale(1 − .1·ex)`, `translateY(−0.03·vh·ex)`; a black `#000` overlay opacity `.55·ex`.

### Scene 3: Voices (light)
**Enter:** the whole scene is a sheet rising from the bottom: `e = seg(5.5, 6.3, io)`; `translateY((1−e)·100%)`; `border-radius (32·(1−e))px (32·(1−e))px 0 0`; soft top shadow `0 −30px 80px rgba(0,0,0,.18)`.
**Copy:** h2 `Tell the` / `voices apart.`; p `Other voices are separated as Speaker 1, Speaker 2. Rename one once and Wffl recognizes that voice in later meetings. Your microphone is always Me.` Copy fades up `seg(6.1, 6.7, out)`, 20px rise.
**Stage:** full-width lanes area `bottom 9vh; height min(46vh, 380px); overflow hidden`. A `track` 200% wide, two groups (each 100vw): group A captioned `This meeting · sample`, group B `A later meeting · sample` (mono 12px). Lane pitch `clamp(64px, 10vh, 96px)`; lane top = `40px + row·pitch`. Each lane: mono pill label at left; a "stream" of 44 pill bars (`width clamp(3px,.45vw,6px)`, heights `8 + round(30·|sin(.55i + s)·cos(.21i + 2s)|)` px with s=1 for Me, s=3.3 for the other voice; `border-radius 99px`).
- Lanes: row 0 **Me** (ink bars); row 1 **Them** (mixed: bars in groups of 5 alternate between voice 1 (ink) and voice 2 (`--soft`)).
**Scroll:**
- Bars grow in: group A `t0 = 6.1`, group B `t0 = 8.1`; bar i of n: `a = seg(u, t0 + i/n·.6, t0 + .4 + i/n·.6, out)`; `scaleY(.1 + .9a)`.
- Parallax: stream `translateX(−(u − 6.3) · k px)` with k = 8 (Me), 14 (Them).
- **Split** `split = seg(6.9, 7.5, io)` (group A): voice-2 bars `translateY(split · pitch)` and opacity `mix(.55, .9, split)`; the `Them` label cross-fades out `1 − seg(split, 0, .5)`; a second label `Speaker 2` fades in `seg(split, .5, 1)` and travels with `translateY(split·pitch)`; voice-1 label becomes `Speaker 1`; a mono tag under it `Rename` appears `seg(split, .8, 1)`.
- **Rename** `rn = seg(7.7, 8.2, lin)`: while `0 < rn < 1` the Speaker-1 label border turns ink and the label types: `rn < .15` → `Speaker 1`; else `"Priya".slice(0, ceil((rn − .15)/.85 · 5))` with a 1px caret; tag text becomes `Renamed once` at `rn ≥ 1`. (Names are invented sample data, captioned "sample".)
- **Camera track sideways** `tr = seg(8.15, 8.7, io)`: track `translateX(−50% · tr)` (reveals group B). Group B shows: Me / **Priya** (tag `Recognized from an earlier meeting`, opacity `seg(8.5, 8.8)`) / **Speaker 1** (the other voice, already split, label offset by one pitch).
- **Exit** `ex = seg(8.7, 9.4, io)`: content opacity `1 − ex`, `translateY(−0.04·vh·ex)`, `scale(1 − .2·ex)`.

### Scene 4: Minutes (light)
**Layout (desktop):** copy left (`width min(34rem, 100vw − min(56vw,760px) − 3·pad)`); docs column right: `right pad; top 68px+4vh; bottom 9vh; width min(56vw, 760px); perspective 1400px`. Two white cards (28px radius, `--shadow`): transcript card (width min(100%, 560px), centred) and minutes card (width min(100%, 430px), right).
**Copy:** h2 `Less noise.` / `More meaning.`; p `Clean up a transcript into readable paragraphs, then turn it into minutes, decisions and action items. Ollama is the local default; an optional remote endpoint receives transcript text.`
**Transcript card content (sample):** header mono `Transcript · sample` + segmented control `Raw | Cleaned` (pill, ink thumb). Topic heading row (W-4): mono `00:41` + `Download size` (weight 500). Three lines, speaker label mono `Me · 00:41`, `Priya · 00:49`, `Me · 00:58`:
1. `Where are we<um,> on the first download?` → cleaned: `Where are we on the first download?`
2. `The flow works,<you know,> but you can’t tell how big the model is.` → `The flow works, but you can’t tell how big the model is.`
3. `We show the size<, um,> first.` → `We show the size first.` (`<…>` = filler span that gets struck then collapsed)
**Minutes card:** mono `DECISION`; h3 `Make the first download clearer.`; p `Show the model size before someone commits.`; action row: 20px ring checkbox + `Update the model picker.` with mono `From the sample conversation`; footer mono `Written with your configured model`.
**Scroll:**
- Transcript card rises: `d1 = seg(8.8, 9.5, out)`: opacity `d1`, `translate3d(0, (1−d1)·.38·vh, 0) rotateX((1−d1)·24°) scale(.92 + .08·d1)`. Copy opacity `seg(9.0, 9.6, out)`, 20px rise.
- Push-in: card scale × `(1 + .05·seg(9.5, 10.7, lin))`.
- Raw/Cleaned thumb: `translateX(seg(10.2, 10.5) · 100%)`.
- Strike `seg(10.0, 10.3, lin)` (1px line scaleX 0→1 across each filler); collapse `col = seg(10.3, 10.8, io)`: `max-width = naturalWidth·(1−col)`, opacity `1 − .9·col`.
- Topic heading reveals: opacity `seg(10.4, 10.8, out)`, max-height `· 44px`.
- Minutes: `p2 = seg(10.9, 11.7, io)`: transcript card `translateX(−p2·cardWidth·.26)` and scale × `(1 − .16·p2)`, opacity `d1·(1 − .45·p2)`; minutes card opacity `p2`, `translate3d((1−p2)·.3·vw, 0, 0) rotateY((1−p2)·−22°)`. Checkbox tick draws `seg(11.4, 11.7, lin)` (stroke-dash 14 → 0).
- **Exit (camera pulls back to the Mac):** `ex = seg(11.8, 12.6, io)`: inner `scale(1 − .7·ex)` about viewport centre; copy opacity `1 − seg(11.8, 12.2)`; whole scene opacity `1 − seg(12.4, 12.9, lin)`.

### Scene 5: Mac (inverted)
**Enter:** window-open iris: `e = seg(11.8, 12.8, io)`; `clip-path: inset((1−e)·30% (1−e)·34% (1−e)·30% (1−e)·34% round (28·(1−e))px)`; none at e=1.
**Layout:** centred. h2 centred at `top 68px + 5vh`; diagram `width min(980px, 100% − 2·pad); height min(36vh, 320px); top 52%`; fine print `bottom 7vh`, centred.
**Copy:**
- h2: `Your audio stays` / `on your Mac.`
- p: `Recording and transcription stay on your Mac. With a local summary model, transcripts and summaries stay here too.`
- fine: `A remote summary or clean-up endpoint receives transcript text. Once downloaded and selected, local models let Wffl process offline.`
- Four destinations (left col: Cloud transcription, Account sign-in; right col: Telemetry, Cloud summaries) with status pills respectively: `On-device`, `Not required`, `None`, `Off by default`. Pill = mono 12px, hollow 7px ink circle (NOT ember).
**Mac object:** `min(300px, 34vw)` wide, 3:2, 18px radius; contains sidebar (3 pill rows, first solid ink), traffic dots, an ember 6px lamp + mono `Recording`, a tiny 8-bar mark, two skeleton lines. (Ember here = live recording lamp.)
**Scroll:**
- Mac scale `1.7 − .7·seg(12.2, 13.2, out)`.
- h2/p opacity `seg(12.9, 13.5, out)`, 22px rise, blur `(1−cp)·6px`.
- Chip i (0..3) opacity `seg(13.2 + .2i, 13.6 + .2i, out)`; pill i opacity `seg(13.75 + .18i, 14.0 + .18i, out)`.
- Wires (SVG): a faint dotted ghost curve (`2 6` dash, `--line-2`) from the Mac edge to each chip; a solid 1.5px ink line draws along the first **50%** of the curve: dashoffset `(1 − seg(13.3 + .18i, 13.9 + .18i)) · cutLength`; then a 9px-half-length perpendicular tick (2px) at the cut point, opacity `seg(13.8 + .18i, 14.0 + .18i)`. Meaning: the line never reaches the destination. Wires hidden under 760px.
- Fine print opacity `seg(14.0, 14.5, out)`.
- Exit: `scale(1 − .08·seg(14.6, 15.4))`.

### Scene 6: Begin (light)
**Enter:** circle bloom from centre: `R = 150vmax · seg(14.6, 15.4, out)`.
**Layout:** centred column: mark (`min(15vw, 110px)`, min 70px) → h2 (400, clamp(3rem, 8vw, 6rem), .98) → CTA + fine → three setup steps in a 3-column row (single column on mobile) → footer links pinned bottom.
**Copy:**
- h2: `Ready when` / `you are.`
- CTA `Download for macOS` (same URL as scene 1); fine: `Free and open source. Requires macOS 15 or later on Apple Silicon.`
- Steps (numeral 300 weight 2rem `--soft`, title 500, mono via-note): `01 Install — drag to Applications`; `02 Download a speech model — one time, from inside the app`; `03 Add a local model — optional`.
- Footer: `MIT licensed. Based on Meetily by Zackriya Solutions.` (link `https://meetily.ai`) · `GitHub` · `Releases` (`https://github.com/PurvarajG/Wffl/releases`) · `Setup guide` (`https://github.com/PurvarajG/Wffl#first-run`).
**Scroll:** glow `seg(14.9, 15.6) · .9`; bars grow `seg(15.0, 15.6, out)` (use the intro bar transition); h2 `seg(15.2, 15.8, out)` 24px rise + blur 6px; CTA `seg(15.4, 15.9, out)` 18px rise; step i `seg(15.6 + .15i, 16.0 + .15i, out)` 16px rise; footer `seg(15.9, 16.2, out)`.

## 1.6 Pace / feel
Total scroll ≈ 16 screens. Dive and iris/bloom transitions between inverted/light grounds are the only hard "entering" moves; everything else is continuous. No snap, no auto-scroll.

## 1.7 Truthfulness
- Sample content (transcript lines, "Priya", timecodes, the minutes card) is labelled "sample" visibly where it appears (scene 2 caption, scene 3 group captions, scene 4 header and action footnote).
- "Signed and notarized" is **not** in this spec (QA W-7 unverified); keep it out unless verified.
- Do not claim speaker counts the diarizer did not find; the Speaker 1 / Speaker 2 / rename flow is exactly the real flow.

## 1.8 Mobile (< 760px) — W-3 acceptance
Same driver, same `u` timeline. Differences, all required:
- Copy is **never covered**: each scene's copy block sits at the top (`top: 60px + 3vh`) and the scene artwork occupies the lower part; nothing scrolls under an opaque layer because there is only one pinned stage and no separate copy column.
- Scene 1: single column, mark first (width `min(62vw, 260px)`) then h1 at 2.9rem, lede 1.02rem. Dive/centre maths unchanged (measured).
- Scene 2: plane `bottom 24vh; height 28vh`; 30 columns; words `bottom 10vh`, 1.3rem; caption `bottom 3.5vh`, 11px, no wrap.
- Scene 3: lanes `height 42vh; bottom 7vh`; stream left offset `pad + 82px`.
- Scene 4: copy full width; docs `left/right pad; height 46vh; bottom 6vh`; transcript card on `p2` **fades to 0** (opacity `1·(1 − p2)`, no sideways shift) and minutes card slides up from `translateY((1−p2)·.16·vh)` (no rotateY).
- Scene 5: no wires; 2×2 chip grid under the Mac (`left 0 / 52%`, `top 52% / 76%`); fine print 12.5px.
- Scene 6: steps stacked in one column (numeral left, title + via right); footer links wrap.
- Rail and space caption hidden; nav keeps `Download for macOS`.
- Minimum text size 11px.

## 1.9 Reduced motion (`prefers-reduced-motion: reduce`, plus the existing Pause-motion control if kept)
- No pin, no scroll driver, no smoothing, no transitions, no canvas animation. `#journey` height auto; scenes stack in normal flow, each `min-height: 100dvh`, `visibility: visible`, no clip-path/transform/radius/shadow.
- Each scene is rendered once at its settle position `u = [0.3, 5.3, 8.2, 11.5, 14.4, 16.2]`, and then static end states are forced: bars grown; dot field drawn at `ph = 1` ("Saved, on this Mac", all 8 words visible); scene 3 shows groups A and B stacked (Speaker 1 renamed shown as `Priya` with `Renamed once`, Speaker 2 present); scene 4 shows cleaned lines, topic heading, thumb on `Cleaned`, fillers removed, minutes card below with ticked action; scene 5 shows all pills and full wires; scene 6 full.
- Nav gets a 86% ground blur background (no ink flip). Progress hairline, rail, caption, hint hidden.

## 1.10 Accessibility
Each scene is a `<section aria-label>`; decorative canvases/SVGs `aria-hidden`; the transcript words have a single `aria-label` with the full sentence; the mark has `role="img"`. Visible focus (2px ink outline). Rail buttons keyboard-operable. No live region announces scroll-driven changes (QA W-17). One `h1` (scene 1) first in DOM; scene headings are `h2`.

## 1.11 Website acceptance tests (must pass)
1. `__setU(0)`: hero visible, bars full height, text legible; `__setU(1.4)`: text invisible, mark centred and larger; `__setU(2.7)`: mid-dive, bars wider than the viewport; `__setU(3.6)`: dark ground, tilted dot plane, no hero content visible.
2. `__setU(5.0)`: all 8 words visible, caption `Transcribing on this Mac` until `u ≥ 5.3`, then `Saved, on this Mac`.
3. `__setU(7.3)`: two voices separated into rows `Speaker 1`/`Speaker 2` labels visible; `__setU(8.1)`: label reads `Priya` with caret; `__setU(8.7)`: group B visible, `Recognized from an earlier meeting`.
4. `__setU(10.9)`: topic heading `Download size`, timecodes, `Cleaned` selected, no filler words visible.
5. `__setU(14.4)`: four destination chips with pills and four cut wires; `__setU(16.2)`: scene 6 complete.
6. Real scrolling (no hook): scroll to the middle of J2 (`J2.top + 2.2·innerHeight`); after 1.5 s the caption reads `03 / 06 · Voices` and the page converges (`uD == uT`). Scrolling through I1 and I2 shows the revealed rows and the typed query.
7. 390×844: no scene shows copy overlapped by artwork; no horizontal scroll.
8. Dark theme: scenes 2 and 5 are light grounds, nav ink flips correctly.
9. Reduced motion: page height ≈ 6 stacked scenes; nothing animates; all end states present.
10. No ember pixels outside: the live lamp/playhead dots (scene 2), the recording lamp (scene 5), the top progress bar.

---

# PART 2. UPDATE FILM (native SwiftUI; replaces the welcome sheet; Revision 2 supersedes the earlier popup design)

Owner direction: the update story is **not a popup**. It takes over the **whole app window** and plays as a **film the user watches**, a continuation of the app itself: the old app turns into the new app in front of them. No interaction is needed. The reference is `update-story.html` (scrub with the slider, or `window.__seek(t)`).

## 2.1 What stays
Campaign key `quiet-instrument-1`, first-install evidence capture before preference migration, active+idle launch presentation, nonmodal invitation when busy, replay deferred during active work, busy signals. The film never records, downloads, selects an engine or creates a summary.

## 2.2 Accuracy rule (the most important rule in this part)
**The film is not drawn; it is the real app.** The mock redraws Home approximately only because it is HTML. Production must not estimate anything:
1. **NEW plate = the live real views.** The film layer renders the actual `ContentView` shell (`SidebarView`, `HomeView`, `MeetingsPage`) with sample data from `PreviewRuntime` (sample meeting "Weekly product sync", ready states), at the actual window size, with the actual `Theme` tokens, `AppFonts`, `WMarkView`, `InstrumentPill`, `wfflCard`. No re-implementation.
2. **OLD plate = the real old app.** Build `Sources/Wffl/Welcome/Legacy/` from commit `06579e8`: copy `Theme.swift` (renamed `LegacyTheme`), `SidebarView`, `HomeView` (and only what the film shows) as `Legacy*` types, unchanged except names and static sample data. Alternative accepted by the owner only if it is pixel-identical: @2x PNG plates captured from a real old build.
3. **Every morph target is measured, not typed.** Position/size of the sidebar width, wordmark, mark, nav rows, selected row, privacy note, headline, buttons, in BOTH plates, are read with `anchorPreference`/`GeometryReader` frames in one named coordinate space, and the film interpolates between the measured rects. The numbers in this spec (and mock) are for orientation only; where the measured rect differs from a number here, the measured rect wins.
4. **Acceptance by pixel diff** (required, automated, in `scripts/`): render the film at t = 0.0 and 2.9 and compare with a real screenshot of the old app's Home at the same window size; render t = 7.4 and 31.9 and compare with a real screenshot of the new app's Home. Differences allowed: caption layer, `Skip`, progress hairline, window shadow. Everything else must match with ≤ 0.5 % differing pixels (tolerance 2/255 per channel). Fail the build/test if not.

## 2.3 Presentation
- Full window: the film fills the window content area edge to edge (hidden title bar; the real traffic lights stay on top and work). Minimum window 900×560 (the mock shows 1100×700 and 900×560).
- Starts automatically on first launch after the update (same launch policy). Plays once, **about 32 seconds**, no controls needed. Layers above the film: `Skip` (top right, 13pt medium, secondary colour, 7×12 padding pill hit area), a 2pt progress hairline along the bottom edge (ink at 80%), the caption.
- **Captions** are subtitles, not a card/dialog: lower-left, left 44, bottom 40, width 640, on a blurred plate (ground at 88% opacity, 14pt backdrop blur, radius 26, 1pt hairline, inset −26/−30/−18/−30). Title 36pt/1.04 Hanken Grotesk 400, −0.035em, ink; body 16pt/1.45 body colour, max 60ch; qualifier 13pt secondary. Colours follow the live skin (they cool with the window).
- Pause/replay is not required. `Space` toggles pause (accessibility), `Esc` stops.

## 2.4 Timeline (seconds). Every value is exact; `seg(t,a,b,e)` = clamp((t−a)/(b−a)) through easing e; io = sine in-out `.5−.5cos(πx)`, out = `1−(1−x)^2.6`, lin = x. `L(a,b,k)=a+(b−a)k`.

| Time | What happens |
|---|---|
| 0.0–3.0 | **Real old Home.** Camera scale 1 → 1.03 linear (centre of window). Nothing else moves. |
| 0.8–3.0 | Caption 1 (in 0.7 s out ease, out over the last 0.5 s): `Wffl, as you knew it.` (title only) |
| 3.2–4.6 | Camera dives to the big Home mark: scale 1.03 → 1.9, focus = measured centre of old Home mark (≈ 655,178), io. |
| 3.4–6.6 | **Skin cools** `k = seg(t,3.4,6.6,io)`: every palette colour is mixed per channel between OLD and NEW (table 2.5). |
| 3.6–5.8 | **Mark morph** `mm = seg(t,3.6,5.8,lin)` for all marks (sidebar and Home): see 2.6. |
| 4.6–6.8 | **Layout settles** `p = seg(t,4.6,6.8,io)`: sidebar 210 → 220; rows, wordmark, buttons, mark, headline interpolate old → new rects (2.7). |
| 5.0–6.2 | **Content crossfade** `x = seg(t,5.0,6.2,lin)`: old-only content (breadcrumb, centred subcopy, status chips, serif headline) fades out while new-only content (left subcopy, "Your setup" column, Hanken headline) fades in. |
| 5.6–7.2 | Camera pulls back to scale 1, focus window centre. |
| 4.2–10.8 | Caption 2: `A quieter Wffl.` / `A calmer monochrome workspace. The same recordings, notes and preferences, with more room for the words that matter.` |
| 11.4–13.0 | Selected row glides from Home to Meetings (`seg(t,11.4,13.0,io)` × 2 rows): pill passes over Dashboard; content cross-dissolves Home → Meetings view; the meetings list appears under the nav. Camera 10.6–12.2 to scale 1.25 at (330,260); hold; 13.2–14.4 back to 1. |
| 11.8–17.2 | Caption 3: `More room for your work.` / `Home, Dashboard, Meetings, Audio Files and Settings now share one consistent workspace. Everything stays where you left it.` |
| 17.4–19.2 | Camera to scale 1.32 at (640,430). Recede `rc = seg(t,18.4,19.6)·(1−seg(t,24.4,25.4))`: summary card, transcript rows 2 and 3, sidebar nav/pill/list/privacy card → opacity `1−.86·rc`, blur `rc`pt. Title, "TRANSCRIPT" heading and **row 1 stay at full strength**. |
| 17.8–19.4 | **The signal travels:** `trav = seg(t,17.8,19.4)·(1−seg(t,24.6,26.0))`; one eight-bar mark (final-state ellipses) moves from the sidebar mark position to the engine band (left 32, top 466 in detail coordinates), size 24 → 72, while the sidebar mark fades `1−seg(t,17.6,18.4)`. |
| 19.0–19.9 | Engine label fades in (out ease) left 136, top 462, height 38, pill: hollow download glyph + mono 11pt `BAPS Whisper · ≈1.6 GB · Optional model`; card fill, hairline. No progress bar, no download state. |
| 18.0–25.0 | Caption 4: `Meet BAPS Whisper.` / `BAPS Whisper transcribes English, including Gujarati and Sanskrit vocabulary in Latin letters. Optional model, about 1.6 GB; download in Settings.` / qualifier `For other languages or translation, choose Whisper.` The words `kirtan` and `satsang` in row 1 are underlined (sample, Latin letters). |
| 24.4–26.0 | Camera back to scale 1; recede and label reverse (label out 24.6–25.2); signal returns to the sidebar by 26.0. |
| 26.0–27.4 | Selected row glides back to Home; content dissolves to Home. |
| 26.2–31.4 | Caption 5: `Here on your Mac.` / `Audio, transcription and your library stay local. Model downloads use the network; remote summaries are optional.` |
| 31.2–31.8 | `Skip` fades out. |
| 32.0 | **Handoff:** the film layer is removed. The last frame IS the real new Home, so nothing changes on screen; the app is live. Acknowledge the campaign. |

Camera keyframes (t, scale, focusX, focusY in window units), interpolated with io between consecutive pairs: `(0,1,550,350) (3.0,1.03,550,350) (3.2,1.03,550,350) (4.6,1.9,655,178) (5.6,1.9,655,178) (7.2,1,550,350) (10.6,1,550,350) (12.2,1.25,330,260) (13.2,1.25,330,260) (14.4,1,550,350) (17.4,1,550,350) (19.2,1.32,640,430) (24.4,1.32,640,430) (26.0,1,550,350)`; transform = `translate(W/2 − fx·s, H/2 − fy·s) scale(s)`, origin top-left. In production the focus points are the measured rects' centres (2.2.3).

## 2.5 Palettes (from `Theme.swift`, light; OLD from 06579e8)
| token | OLD | NEW light | NEW dark |
|---|---|---|---|
| ground | `#F7F3EC` | `#F2F2F0` | `#0F0F0F` |
| raised (sidebar) | `#EFE9DE` | `#E9E9E6` | `#0A0A0A` |
| card | `#FFFEFB` | `#FFFFFF` | `#181818` |
| ink | `#2C261C` | `#0B0B0B` | `#F2F2F0` |
| body | `#4A4235` | `#2B2B29` | `#D7D7D3` |
| secondary | `#8F8676` | `#6B6B67` | `#AAAAA5` |
| hairline | `#E9E5DC` (old 8% ink) | `#D2D2CE` | `#383838` |
| primary fill | `#7A9169` (sage) | `#0B0B0B` | `#F2F2F0` |
| on-primary | `#FFFEFB` | `#FFFFFF` | `#0B0B0B` |
| selected row | sage 16% `#E4E3D6`, border `#CBD1BD`, radius 7 | solid ink capsule | solid ink capsule |
The old app was light only, so in dark mode the film starts cream and cools into the dark skin. Real asset: use the live `Theme` values, not these hex copies.

## 2.6 Mark morph (exact)
viewBox `0 0 100 78`. Old stroke W: `M12 18 L32 62 L50 34 L68 62 L88 18`, round caps/joins, width 9, colour `#2C261C`, opacity `1 − seg(mm,0,.4,lin)`. Eight ellipses, cx = 16,26,36,46,56,66,76,86, rx 3.4, final ry = `[30,20,10,20,26,20,10,30] × .72` centred at cy 39. For ellipse i: `a = seg(mm, .15+.05i, .75+.03i, io)`; `cy = L(strokeY(cx), 39, a)` (starts as a 2.2-ry dot ON the stroke, `strokeY` = y of the polyline at that x); `ry = L(2.2, ry_final, a)`; opacity `seg(mm,.1,.3,lin)`; fill = live ink. Sidebar mark size `L(16,24,p)` at x 16, vertically centred on the wordmark; Home mark `L(44,66,p)`. (Matches `WMarkView` heights `[1,.67,.33,.67,.87,.67,.33,1]`.)

## 2.7 Old → new interpolations (orientation values; production measures them)
Sidebar width `L(210,220,p)`; wordmark left `L(40,49,p)`, vertical centre `L(48,52,p)`, serif 17 fades out `1−seg(k,.15,.7)` while Hanken 500 21 fades in `seg(k,.15,.7)`; nav row 0 top `L(73,78,p)`, row step `L(29,35,p)`, row height `L(27,33,p)`; selected-row radius `L(7,999,seg(k,.2,.8))`; Settings row top `L(611,619,p)`; privacy note old (left 8, top 646, h 46, radius 8, text `On-device only · nothing leaves this Mac`) fades `1−seg(k,.2,.6)`, new (left 8, top 660, h 32, radius 13, card fill, `Local summary service`) fades in `seg(k,.4,.8)`. Home headline: old `Ready when you are.` serif 38, centred at top `L(218,132,p)`; new `Ready when / you are.` Hanken 300 52/58, −2 tracking, left 32, top 132. Start button: left `L(centre−w/2, 32, p)`, top `L(344,310,p)`, width `L(166,168,p)`, height `L(41,38,p)`, radius `L(11,999,p)`, fill/text mixed by `k`, sage shadow `.35·(1−p)`. Import: left `L(centre−60, 32+w+10, p)`, top `L(396,310,p)`, width `L(120,150,p)`, height `L(32,38,p)`, radius `L(9,999,p)`; label `Import audio` → `Import Audio` at x=.5. Real Home content (old: breadcrumb, 2-line subcopy, chips `BAPS Whisper ready`, `Local AI Connected`; new: subcopy `Record the conversation. Find the words and decisions later.`, "Your setup" column) crossfades per 2.4.

## 2.8 Reduced motion and accessibility
- Reduced Motion: no film motion. Show **five still frames**, user-paced (Back/Next, `Skip`), at t = 1.5, 7.4, 14.6, 22.0, 30.6 with their captions; no camera, no fades, no morph. Last step ends in the live app and acknowledges.
- VoiceOver: one summary element for the film (`Wffl update: <caption title>, <body>`), updated at each caption; `Skip` is a button; the underlying plates are hidden from accessibility while the film plays; announce completion.
- Sample content is labelled `Sample · illustrative` wherever a sample meeting appears.
- Minimum text size in the film is 11 pt at scale 1 (real app has a 10 pt privacy note, kept as is because it is the real UI).

## 2.9 Dismissal and acknowledgement
- Natural end (32.0 s) and `Skip`: **acknowledge**; Settings can replay.
- `Esc` and window close while playing: **do not acknowledge**; the sidebar invitation `A quieter Wffl is here` / `See what’s new` / `Later` remains for the next launch.
- Focus returns to the main window content on handoff.

## 2.10 Update-film acceptance tests
1. Pixel-diff tests in 2.2.4 pass.
2. Window-fill: the film covers the entire content area at 900×560 and larger; no sheet, no rounded card, no backdrop dimming.
3. t = 4.8 shows the camera dived on a mark that is mid-morph (stroke fading, bars growing) and a visibly cooler ground than t = 3.0.
4. t = 21.5: label text exact, no `Atlas`, no progress UI, row 1 and the heading readable, summary receded.
5. t = 31.9 equals the live Home; t = 32.0 removes the film layer with no visual change.
6. `Esc` at any time leaves the campaign unacknowledged; `Skip`/end acknowledges.
7. Reduced motion shows the five stills only.

---

# PART 3. APP ICON (see `icon.html`)

- **Recommended: A, Ink.** Tile `#1B1B1B → #0A0A0A` vertical gradient, eight capsule bars `#F2F2F0`. No ember, no baked shadow/hairline in shipped art.
- Geometry on a 1024 grid: body 824×824 at (100,100), continuous corners (≈185 radius); bars width 44, pitch 64, centred on the body, heights (full) `1, .67, .33, .67, .87, .67, .33, 1` of 384px (tallest = 384; ry 192/128/64/128/166/128/64/192).
- Deliver an Icon Composer `.icon` with appearances: **Light (default)** A as above; **Dark** tile `#0A0A0A`, bars `#F2F2F0`; **Tinted** bars as a single-colour foreground layer on the system tint; plus `.icns` fallback built with `iconutil` from 16/32/64/128/256/512/1024 (and @2x).
- Check legibility at 16, 32, 128 px. If bars blur at 16/32, ship a simplified variant (6 bars, same silhouette) for those sizes only.
- Option B (Paper: `#FAFAF8 → #E9E9E6` tile, ink bars) is the documented alternative, but **A is the decision unless the owner overrides**. Option C (ember dot) is rejected.
- Replace `Support/AppIcon.icns`, update `scripts/makeicon.swift`, make the in-app wordmark and the favicon use the same bar heights.

---

# Developer split
- **Codex:** Part 1 only (`website/index.html`; copy `design-handoff/immersive/fonts/*.woff2` over `website/fonts/` only if the existing files differ; keep fonts self-hosted).
- **Sonnet:** Part 2 (`WelcomeJourneyView.swift`, keep `Support/WelcomeJourney.swift` lifecycle) and Part 3 (icon), plus the app redesign fixes the orchestrator lists separately.

# Known mockup-only quirks (do not copy into production)
- The dark "mockup controls" bar and Mobile-390 iframe.
- Direct-loading the story at a later frame (`?f=3`) renders the wrong skin and camera; production always starts at frame 1.
- `window.__setU` and `window.__go` are test hooks.
