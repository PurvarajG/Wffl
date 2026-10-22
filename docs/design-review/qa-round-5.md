# QA round 5: website, app, icon, update film

Date: 2026-10-22. Tester: QA pass (round 5), read-only on source. The only file written is this report.
Inputs: `design-handoff/immersive/SPEC.md` (Revision 2), `design-handoff/immersive/PLAN.md` (Orchestrator fixes), `docs/design-review/qa-round-4.md`, `design-handoff/immersive/codex/DEVELOPER-A-REPORT.md`.
IDs: W5 = website, A5 = app, I5 = icon, F5 = update film. Round-4 IDs (W-, A-, I-, P-) are tracked in the status table. Severity: blocker, major, minor, nit.

Totals: 0 blocker, 8 major, 18 minor, 4 nit (30 findings).

Verdict in one line: the website structure is right (three pinned journeys, scroll-driven, copy verbatim, honest sample labels), but it misses several SPEC acceptance values, and the reference itself produces the same misses. The update film is not ready: its acceptance tests are circular, its readiness data is live, and it rebuilds the whole window every frame. The app redesign closes most round-4 items. The icon is missing its tinted appearance. Settings consolidation has no regression.

---

## How this was checked

- Website: served `website/` on 127.0.0.1:4176 with `python3 -m http.server`. Served the mockup on 4175. Made a scratch copy in the scratchpad with the reduced-motion query forced on (served on 4177). The project file was not edited.
- Browser: built-in browser at 1440x900 and 390x844 (custom size), light and dark (colour scheme emulated), reduced motion (scratch copy). Acceptance tests ran through `window.__setU(u)` and through a real scroll (scrollTo, then a 2 s wait). Frame sweep: `__setU` every 0.25 from 0 to 16.2 at 1440x900 with JS metrics (text blocks, overlaps, nav hits). Sweep at 0.5 steps at 390x844. Visual inspection at 0.5 to 1.0 unit steps, zoom on the lane tag, and the mockup compared at the flagged values.
- Harness limits, which affect how frames were read: the Browser pane runs no animation frames unless it is the fronted, visible tab. I fronted the tab and waited for two frames before each screenshot. Several early screenshots were one frame stale and were retaken. CSS transitions in the pane settle slowly, so computed colours were read after a settle of 4 s. A u value that falls in the gap between two journeys (12.0 is between J2's end at 11.7 and J3's start at 12.2) is not a valid `__setU` target; the hook falls back to J1 (W5-13). That was my test error and is recorded as a nit.
- Console: no errors or warnings on the primary URL. Links: all five external URLs return 200 (`curl -L`). Favicon, apple-touch-icon and meta tags checked in the DOM.
- App: `swift build` exit 0 (incremental, 0.34 s, so the linker warning was not replayed). `swift test`: 223 run, 3 skipped (all environment-gated: `WFFL_ACCEPTANCE`, `WFFL_FIDELITY_AUDIO`, `WFFL_HARNESS_WAV`), 0 failures. UpdateFilmTests 10/10 pass. WelcomeJourneyTests 7/7 pass.
- Read in full: `Welcome/FilmTimeline.swift`, `Welcome/FilmStage.swift`, `Welcome/FilmAnchors.swift`, `Views/WelcomeJourneyView.swift`, `Support/WelcomeJourney.swift`, `Tests/WfflTests/UpdateFilmTests.swift`, `Support/Theme.swift`, the settings sources, `Support/AppIcon.icon/icon.json`, `Support/AppIcon.icon/Assets/bars.svg`, `scripts/makeicon.swift`, `scripts/bundle.sh`. Rendered film frames and icon renders from the scratchpad were inspected. `xcrun actool` compiled the `.icon` document into a scratch directory (exit 0).
- Not done: native app launch (not required by the brief), VoiceOver run, and the real v1.9.0 screenshots that SPEC 2.2.4 asks for (see F5-4).

---

## Round-4 status

Status values: FIXED, PARTIAL, OPEN, SUPERSEDED (replaced by a SPEC decision or by a redesign), OVERRULED (kept on purpose), UNVERIFIED.

### Website (W-)

| ID | R4 sev | R5 status | Evidence |
|---|---|---|---|
| W-1 | blocker | FIXED | Three pinned journeys with two interludes, scroll-driven `u`, `index.html` lines 280-364 and 683-688. Real-scroll test 6 passes. |
| W-2 | major | FIXED | `.instrument-light` removed. `.glow` gradients end at 0 alpha. Soft edges at u 0 and 16.2. |
| W-3 | major | FIXED | No opaque sticky stage on phones. 390x844 sweep at 0.5 steps: no copy under artwork except transitional cross-fades (W5-1 is a separate clip). |
| W-4 | major | FIXED | Raw/Cleaned control, timecodes and strikethrough render (u 10.5). Minutes card at u 11.7. |
| W-5 | major | FIXED | One scheme `0N / 06 · Name` (`#wh`). No story-kicker in the markup. |
| W-6 | major | PARTIAL | No dead `.hero`, `.js` or `.step.in` selectors (grep: 0). `DESIGN.md` and the handoff docs were not re-checked. |
| W-7 | major | FIXED | No "notari" text in `website/index.html`. The DMG itself was not checked (UNVERIFIED). |
| W-8 | minor | SUPERSEDED | No motion toggle in SPEC 1.3. Reduced motion is by media query only. |
| W-9 | minor | SUPERSEDED | SPEC 1.3: brand and download only at every width. |
| W-10 | minor | SUPERSEDED | No toggle. |
| W-11 | minor | FIXED | `↓ ↳ ⌕` absent. The one `→` is in a JS comment (`index.html:688`), not rendered. |
| W-12 | minor | FIXED | No `.sound-trace` element. |
| W-13 | minor | FIXED | No CSS font-size below 11px (grep). Mobile computed check: 0 text nodes under 11px. |
| W-14 | minor | PARTIAL | `apple-touch-icon` (180x180 opaque PNG, 200), `og:title`, `og:description`, `og:type`, `og:site_name`, `twitter:card` present. `canonical` and `og:url` absent (owner input). `og:image` absent by design. `/favicon.ico` returns 404 (W5-14). |
| W-15 | minor | FIXED | No kicker element. |
| W-16 | minor | PARTIAL | Desktop: "Speaker 2" shows (u 7.5). Phone: the label is clipped out of the lanes box (W5-1). |
| W-17 | minor | FIXED | `aria-live` count 0. |
| W-18 | nit | FIXED | One `h1`, first in DOM order (heading list from JS). |

### App redesign (A-)

| ID | R4 sev | R5 status | Evidence |
|---|---|---|---|
| A-1 | major | PARTIAL | 195 `Theme.text/mono/display` calls. Still `.system(size: 12.5)` on sidebar nav labels, `Views/ContentView.swift:252` (A5-1). Other `.system(size:)` uses are SF Symbols. |
| A-2 | major | FIXED | `Views/SettingsView.swift` deleted. `WfflApp.swift:160-161` Settings scene hosts `SettingsPane`. Keys, defaults and controls compared with HEAD (see S5 below). |
| A-3 | major | FIXED | RECORDING label uses `Theme.clayText` (`Views/RecordingBar.swift:43-44`). `Theme.secondary` light is now #666662 (`Support/Theme.swift:22`), about 4.7:1 on `raisedBG`. |
| A-4 | major | PARTIAL | `navRow` `.accessibilityAddTraits(.isSelected)` (`ContentView.swift:273`). Count labels (`ContentView.swift:258`). Speaker chip label and hint (`TranscriptView.swift:265-266`). `SummaryView`, `MeetingDetailView`, `MeetingListView` and `SettingsSections` have no accessibility modifiers (A5-2). |
| A-5 | minor | OVERRULED | "Ready when you are." kept, per PLAN. |
| A-6 | minor | FIXED | No text below 11pt except the sidebar privacy footer (`ContentView.swift:217`, 10pt), which SPEC 2.8 keeps. Other sub-11pt sites are SF Symbols. |
| A-7 | minor | FIXED | `LevelMeter`, `InstrumentGlow`, `darkBG`, `accentMid`, `teal`, `heroGradient`, `selectedEngine`: 0 references. HomeView `profile` key gone. |
| A-8 | minor | FIXED | `floatingBackground` = 0x0F0F0F (`Support/Theme.swift:34`). The `danger` token's documentation was not reviewed. |
| A-9 | minor | FIXED | `Views/SummaryView.swift:154-158` renders action items as "Open" and "Done" text. |
| A-10 | minor | UNVERIFIED | Incremental build; the linker warning was not replayed. Needs a clean build. |
| A-11 | nit | FIXED | Sentence case, `Views/HomeView.swift:76`. |
| A-12 | minor | OPEN | `docs/design-review/app-ui-review.md:7` still says "Source is still the cream/sage/serif app" (A5-4). |

### Icon (I-)

| ID | R4 sev | R5 status | Evidence |
|---|---|---|---|
| I-1 | blocker | FIXED | `Support/AppIcon.icns` regenerated (10 entries, `iconutil -c iconset` check). `Support/AppIcon.icon` added. `scripts/makeicon.swift` header corrected. |
| I-2 | major | FIXED | Body 824 (`makeicon.swift:22-27`). Measured alpha bounds 824x824 on the 1024 render. |
| I-3 | major | PARTIAL | Light and Dark appearances present. Tinted missing (I5-1). |
| I-4 | minor | FIXED | No shadow or hairline in `makeicon.swift`. Alpha outside the body edge: 0. |
| I-5 | minor | FIXED | Same tile and capsules in the icon, the favicon and `WMarkView` (`Support/Theme.swift:50-64`). |
| I-6 | minor | FIXED | 5-bar 16 px and 6-bar 32 px variants, judged from the renders (`scratchpad/icon/sheet_s.png`). See I5-2. |

### Welcome and update film (P-)

| ID | R4 sev | R5 status | Evidence |
|---|---|---|---|
| P-1 | major | FIXED | `Welcome/Legacy/LegacyApp.swift` copies the v1.9.0 sidebar and Home. Labels (Home, Dashboard, Meetings, Audio Files, Settings), 210 pt sidebar and palette match `git show 06579e8`. Pixel match not verified (UNVERIFIED). |
| P-2 | major | FIXED (copy) | No "Atlas" in Views, Welcome or test strings. `Transcription/BapsWhisper.swift:35-45` still adopts `Atlas/Models` (owner decision, outside design scope). |
| P-3 | major | SUPERSEDED | Part 2 film replaces the card. The SPEC film is a plate morph, not depth planes. |
| P-4 | minor | SUPERSEDED | Scaled canvas removed. Film type is 11 pt or larger. |
| P-5 | minor | PARTIAL | One summary element added (`WelcomeJourneyView.swift:80-86`). Captions are still exposed to VoiceOver (F5-6). |
| P-6 | minor | FIXED | `WelcomeJourney.swift:81-95` (`interrupt` vs `dismiss`). Wiring at `ContentView.swift:53` and `:62`. |
| P-7 | minor | OPEN | Menu while busy only raises the sidebar card. No message (A5-3). |
| P-8 | minor | SUPERSEDED | No sheet. |
| P-9 | nit | SUPERSEDED | No chapter counter. |
| P-10 | minor | FIXED | `Database.swift:325-327` COUNT query. `WelcomeJourney.swift:123`. |

Round-4 totals: W 12 FIXED, 3 PARTIAL, 3 SUPERSEDED. A 7 FIXED, 2 PARTIAL, 1 OVERRULED, 1 UNVERIFIED, 1 OPEN. I 5 FIXED, 1 PARTIAL. P 4 FIXED, 1 PARTIAL, 1 OPEN, 4 SUPERSEDED.

---

## SPEC acceptance: website (Part 1)

Desktop 1440x900 unless stated. "Mockup" means the same check on `design-handoff/immersive/index.html`.

| Test | Result | Evidence |
|---|---|---|
| 1a `__setU(0)`: hero, full bars, legible text | PASS | Bar heights 422/281/140/281/366/281/140/422 (full scale). Text opacity 1. |
| 1b `__setU(1.4)`: text gone, mark larger and centred | FAIL (W5-2) | Text opacity 0. Mark width 743 px. Centre offset (85, 9) px. Mockup identical. |
| 1c `__setU(2.7)`: mid-dive, bars wider than viewport | PASS | Bar group 8182 px wide, scale 15.15. |
| 1d `__setU(3.6)`: dark ground, tilted plane, no hero | PASS | Ground rgb(11,11,11). Plane rotateX 6.98 deg. `#s1` hidden. |
| 2a `__setU(5.0)`: 8 words, "Transcribing on this Mac" | PASS | 8/8 words opacity 1. Caption correct. |
| 2b Caption stays Transcribing until 5.3 | FAIL (W5-3) | 5.25 reads Transcribing. 5.29 reads "Saved, on this Mac". Mockup identical. |
| 3a `__setU(7.3)`: Speaker 1 and Speaker 2 labels | PASS | "Speaker 1" opacity 1, "Speaker 2" opacity 0.5. |
| 3b `__setU(8.1)`: label reads "Priya" with caret | FAIL (W5-4) | Label reads "Priy" with caret. Mockup identical. |
| 3c `__setU(8.7)`: group B and "Recognized from an earlier meeting" | PASS | Track translateX(-50%). Tag opacity 0.75. |
| 4 `__setU(10.9)`: heading, timecodes, Cleaned, no fillers | PASS | "Download size" at 44 px. 00:41 / 00:49 / 00:58. Thumb translateX(100%). Fillers max-width 0, opacity 0.1 (visually hidden; still in DOM, W5-11). |
| 5a `__setU(14.4)`: 4 chips, pills, 4 cut wires | PASS | Chips opacity 1. Pills 1, 1, 1, 0.78. Four solid wires, fourth 0.6 px from complete. |
| 5b `__setU(16.2)`: scene 6 complete | PASS with note (W5-5) | Heading, CTA, footer opacity 1. Step 3 at 0.973. |
| 6 Real scroll to J2 + 2.2 vh: caption, convergence, I1/I2 reveal and query | PASS | scrollY 9035. Caption "03 / 06 · Voices". uD = uT = 8.2. I1 rows reveal by position. Nav ink flips in I1. I2 query "model size". |
| 7 390x844: copy never covered, no horizontal scroll | PASS with note (W5-1) | scrollWidth 390 = innerWidth. No copy under artwork at u 0, 4.5, 7.5, 10.5, 13, 16.2 (screenshots). Speaker 2 clipped (W5-1). |
| 8 Dark theme: scenes 2 and 5 light, nav ink flips | PASS | Scenes 2 and 5 background rgb(242,242,240). Nav ink flips at u 2.95 and 14.4. |
| 9 Reduced motion: stacked, nothing animates, all end states | FAIL (W5-6) | Scratch copy: no pin, rail/progress/hint hidden, interludes present. Page height 8584 px (includes two interludes). Four end states incomplete. |
| 10 Ember only on lamps, playhead, recording lamp, progress | CONFLICT | Glow gradients use #FF5B1F (`index.html:55`). SPEC 1.4 allows this, 1.11.10 does not. Mockup identical. Owner to decide. |

R2.5 (acceptance additions):

| Test | Result | Evidence |
|---|---|---|
| (a) Ordinary scroll between journeys; never an empty screen | PASS | DOM order J1, I1, J2, I2, J3. Sweep shows no empty stage. |
| (b) Lanes, docs and Mac each at least 55% of stage width | FAIL (W5-7 note) | Lanes 60%. Docs 52.1% (`#docs`, mockup identical). Mac diagram 86%. |
| (c) No more than two overlapping text blocks; nothing under the nav | PASS | Sweep: max 2 overlapping text blocks (transcript and minutes card cross-fade, 11.25-12.0). No nav hits. |

SPEC 1.8 (390x844): PASS for scene order (mark above h1 in scene 1, copy at top of scenes 2 to 4, 2x2 chips under the Mac in scene 5, stacked steps in scene 6, rail and caption hidden), with the Speaker 2 exception (W5-1). Minimum text size 11px (computed check).

SPEC 1.10 (accessibility): PASS for labelled sections, decorative canvas and SVG hidden, role=img marks, one h1, no live region, visible focus style. Partial for transcript labelling (W5-11). Keyboard activation not exercised (UNVERIFIED).

---

## SPEC acceptance: update film (Part 2) and app icon (Part 3)

| Test | Result | Evidence |
|---|---|---|
| 2.2.1 New plate = live views with PreviewRuntime sample data | FAIL (F5-5) | Engine and summary rows read live model managers (`FilmStage.swift:95-97`, `HomeView.swift:33-34`, `:148-151`). Only mic and system audio use the sample flag (`HomeView.swift:154`, `:159`). |
| 2.2.2 Old plate = real v1.9.0 copy | PARTIAL | Palette and sidebar match HEAD (labels, 210 pt, colours). Pixel match not run (UNVERIFIED). |
| 2.2.3 Morph targets measured, not typed | PASS | `FilmAnchors.swift` anchors, `filmMeasured` in one coordinate space. |
| 2.2.4 Pixel diff against real screenshots, 0.5% at 2/255 | FAIL (F5-4) | Test passes, but references are in-process renders of the same views. |
| 2.3 Full window, captions, Skip, hairline, Space and Esc | PASS | `WelcomeJourneyView.swift:24-40`, `:63-70`, `:88-111`. |
| 2.4 Timeline values and camera keys | PASS | `FilmTimeline.swift` matches the SPEC table and keyframes. Caption windows verbatim. |
| 2.4 Frame at 21.5: heading readable | FAIL (F5-3) | See `scratchpad/film/film-21.5.png`. "TRANSCRIPT" heading and title cropped off the top at camera scale 1.32. |
| 2.5 Palettes | PASS | Old values match HEAD `Theme.swift` lines 7-15. New from live `Theme`. |
| 2.6 Mark morph | DIVERGENCE (F5-7) | Points are HEAD's W (`FilmStage.swift:249`), not SPEC's. Final state is capsules (`WMarkView`), not ellipses. |
| 2.8 Reduced motion: five stills | PASS | `stillTimes` 1.5, 7.4, 14.6, 22.0, 30.6. Back, Next, Skip, Done (`WelcomeJourneyView.swift:21-23`, `:113-127`). |
| 2.8 VoiceOver: one summary element | FAIL (F5-6, static) | Captions are not hidden (`WelcomeJourneyView.swift:56-59`). |
| 2.9 Acknowledgement rules | PASS | Skip and natural end call `dismiss()`. Esc and window close call `interrupt()` (`WelcomeJourney.swift:81-95`, `ContentView.swift:53`, `:62`). Tests pass. |
| 2.10.1 Pixel diff tests | PARTIAL | Pass (10/10), but circular (F5-4). |
| 2.10.2 Window fill at 900x560 and larger | PASS | `testFilmCoversTheWholeWindowAtEveryTime` passes. |
| 2.10.3 t 4.8 mid-morph, cooler than 3.0 | PASS | `testDiveShowsAMarkMidMorphOnACoolerGround` passes. |
| 2.10.4 t 21.5: exact labels, no Atlas, row 1 and heading readable, summary receded | FAIL (F5-3) | Labels exact. No "Atlas" in copy. Heading cropped. |
| 2.10.5 t 31.9 equals live Home; 32.0 no visual change | PASS | `film-31.9-1100.png` and `live-1100.png` are both 94,913 bytes. `film-32.0-1100.png` is the same frame. |
| 2.10.6 Esc unacknowledged; Skip and end acknowledge | PASS | `testSkipAndNaturalEndAcknowledgeButEscAndWindowCloseDoNot` passes. |
| 2.10.7 Reduced motion: five stills only | PASS | `testReducedMotionStillsAreTheFiveCaptionFrames` passes. |
| Part 3: body 824, continuous corners, bars 44 wide, pitch 64, heights | PASS | `makeicon.swift:22-27`. `bars.svg` x positions 266 to 714 step 64, centred on 512. |
| Part 3: Light tile #1B1B1B to #0A0A0A, no ember | PASS | `icon.json` fill gradient. |
| Part 3: Dark appearance #0A0A0A tile | PASS | `icon.json` `fill-specializations`. |
| Part 3: Tinted appearance | FAIL (I5-1) | No tinted specialization. |
| Part 3: `.icns` fallback, all sizes | PASS | 16, 32, 128, 256, 512 at 1x and 2x. |
| Part 3: 16 and 32 px legibility | PASS with note (I5-2) | Judged from renders. |
| Part 3: 180x180 touch icon, opaque | PASS | `website/apple-touch-icon.png`: 180x180, no alpha. |

---

## Findings

Severity: blocker = prevents shipping; major = SPEC acceptance miss or visible defect that a reviewer will see; minor = fix in the next pass; nit = polish or hygiene.

### Website

**W5-1 (major): Speaker 2 is clipped out of the lanes on phones.**
- Location: `website/index.html` mobile rules `.lanes { left:0; top:auto; height:42vh; bottom:7vh }` (line 237) and `--pitch: clamp(70px,17vh,150px)` (line 125).
- What is wrong: on 390x844 the lanes box is 430 to 785 (355 px). "Speaker 2" sits at 819 to 846, below the box, so `overflow:hidden` removes it. The voice-2 bars move down by the same offset and are also clipped. Copy says "Speaker 1, Speaker 2" (SPEC 1.11.3 requires both labels visible).
- Evidence: JS at 390x844, `__setU(7.5)`. Screenshot at 7.5 shows only Me and Speaker 1 rows.
- Fix direction: size the mobile lanes for three rows (or cap pitch at phone height), then reconcile with SPEC 1.8. The lanes height in 1.8 and the pitch in 1.5 do not fit together at 844 px. Owner to decide the source of truth.

**W5-2 (minor): At u 1.4 the mark is 85 px off centre (SPEC 1.11.1 says centred).**
- Location: `r1` (`index.html:547-557`). `m = seg(u,.6,1.8)` gives 0.75 at 1.4.
- Evidence: centre offset (85, 9) px. Mockup identical.
- Fix direction: decide between changing the easing window or amending 1.11.1. Do not change silently.

**W5-3 (minor): Caption reads "Saved" from about u 5.28, not 5.3.**
- Location: `r2` (`index.html:565-569`). `done = ph >= .999`, with `ph = seg(u,4.0,5.3)`.
- Evidence: 5.25 Transcribing, 5.29 Saved (mockup identical).
- Fix direction: make the caption switch at `u >= 5.3` (or amend 1.11.2).

**W5-4 (minor): At u 8.1 the name reads "Priy", not "Priya".**
- Location: `r3` (`index.html:597`). `Math.ceil((rn-.15)/.85*5)` gives 4 letters at u 8.1. Full name from about 8.12.
- Evidence: label innerHTML `Priy<span class="caret">`. Mockup identical.
- Fix direction: adjust the typing threshold or amend 1.11.3.

**W5-5 (minor): Step 3 never reaches full opacity inside the timeline.**
- Location: `r6` (`index.html:647`). Steps use `seg(u,15.6+.15i,16.0+.15i)`, so step 3 ends at 16.3, past L = 16.2. At 16.2 its opacity is 0.973 (also in reduced motion; mockup 0.9728).
- Fix direction: clamp the stagger so every step ends at or before 16.2 (for example, step start 15.5 + 0.15i).

**W5-6 (minor): Reduced-motion end states are incomplete.**
- Location: `applyRM` (`index.html:690-713`). Transcript card opacity is left at 0.616 (set by `r4` at 11.5, not reset). Fourth destination pill at 0.78 (`r5` at 14.4). "Recognized from an earlier meeting" at 0 (`r3` at 8.2). Step 3 at 0.97 (W5-5).
- Evidence: scratch copy at 1440x900, forced reduced motion. The transcript card reads visibly washed out in the stacked screenshot.
- Fix direction: in `applyRM`, set the end state explicitly for the transcript card (opacity 1), pill 4 (1), the recognition tag (1) and step 3 (1).

**W5-7 (minor): The rail sits on top of the Minutes card at the end of scene 4.**
- Location: `#rail` (`index.html:69`, fixed right at `pad - 6px`). Minutes card `.doc.mi` (`:152`).
- Evidence: at u 11.7 (1440x900) the rail spans x 1357-1383 and the card spans x 837-1377. Mockup identical. Visible at the card's right edge in the 11.5 to 12.0 screenshots.
- Fix direction: keep the docs column clear of the rail (right inset at least the rail width plus gap), or hide the rail while scene 4 is active. Also relevant to the 55% docs width in R2.5(b): the docs container is 52.1%.

**W5-8 (minor): The selected "Cleaned" segment label is 3.7:1 on the ink thumb.**
- Location: `.seg b` (`index.html:145`). It uses `--dim` (#6B6B67) on the `.seg u` thumb (#0B0B0B).
- Evidence: computed rgb(107,107,103) on rgb(11,11,11). Contrast 3.7:1 for 12 px text (WCAG AA needs 4.5:1).
- Fix direction: give the selected label the light surface colour when its thumb is under it (for example, a `.on` class toggled with the thumb).

**W5-9 (minor): "Me" speaker tag shows before any words.**
- Location: `.words .who` (`index.html:112`, `:430`). The words row is visible while the plane builds, and the first word appears only at 4.0+.
- Evidence: screenshots at 3.0, 3.5 and 4.0 show "Me" at the bottom left with no words.
- Fix direction: fade `.who` in with the first word (use the same `seg(ph, 0, 0.12)` as the words).

**W5-10 (minor): "Recognized from an earlier meeting" runs through the lane bars at u 8.7.**
- Location: `.tag` (`index.html:135`), positioned `top: calc(50% + 22px)` of the lane.
- Evidence: zoom at 8.7 (region 300-560 by 200-290 in the 800-pixel frame) shows the tag text crossing the bars.
- Fix direction: place the tag under the label column with a background, or shorten the stream's left offset for group B.

**W5-11 (minor): Transcript labelling and hidden fillers in the accessibility tree.**
- Location: `#dtr` (`index.html:337-342`) has no accessible name. `#words` has `aria-label` on a `<p>` with no role, which is not reliably announced. Collapsed filler spans stay in the DOM at opacity 0.1, so screen readers still read "um" and "you know".
- Fix direction: give `#dtr` a label ("Transcript, sample"); give `#words` role="group" (or a visually-hidden text copy); set `aria-hidden` on filler spans once collapsed (or remove them after `col >= 1`).

**W5-14 (minor, carried from W-14): metadata and icon gaps.**
- Location: `website/index.html` head. Missing: `canonical`, `og:url` (owner input), `og:image` (deliberate). `/favicon.ico` returns 404 (checked with curl).
- Fix direction: owner to supply the canonical URL. Add a `favicon.ico` (or a redirect to the SVG) to stop the 404.

**W5-12 (nit): Transitional overlap during the Voices to Minutes cross-fade (8.9 to 9.4).** The transcript card (about 50% opacity) overlaps the lanes. Transitional; no action unless the owner wants a cleaner hand-off.

**W5-13 (nit): `__setU` falls back to J1 for u values in the interlude gaps.** `jOf()` returns `J[0]` for u between 11.7 and 12.2 (or any gap), so `__setU(12.0)` scrolls to 10800 and paints J1's scenes. Test hook only, but reviewers use it. Fix: have `jOf` return the nearest journey, or document the valid u ranges.

### App

**A5-1 (minor): Sidebar nav labels still use the SF system font.**
- Location: `Views/ContentView.swift:252` (`.font(.system(size: 12.5, weight:...))`). This is the same label round 4 cited (A-1, then at line 225).
- Fix direction: `Theme.text(12.5, weight:)` (the 12.5 pt token already exists in other views).

**A5-2 (minor): Accessibility coverage is still thin in four views.**
- Location: `Views/SummaryView.swift`, `Views/MeetingDetailView.swift`, `Views/MeetingListView.swift`, `Views/SettingsSections.swift`: zero `accessibilityLabel` or `accessibilityAddTraits` (grep).
- Fix direction: label the summary actions, meeting rows and settings controls. The VoiceOver pass is UNVERIFIED.

**A5-3 (minor): The busy-state "What's New" menu gives no feedback (P-7 still open).**
- Location: `WfflApp.swift:152-156` (menu action), `WelcomeJourney.swift` `requestReplay(busy:)` (sets `invitation` only), `ContentView.swift:193-196` (card "A quieter Wffl is here").
- Fix direction: show a message in the menu flow ("Wffl is busy. What's New will open when it is idle.") or defer until idle.

**A5-4 (minor): Stale status line in the app review doc (A-12).**
- Location: `docs/design-review/app-ui-review.md:7`.
- Fix direction: update the status line after this round.

**A5-5 (minor): Privacy captions removed from Settings.**
- Location: HEAD `Views/SettingsView.swift` carried "Cloud providers are optional — transcripts are sent to the provider you configure. For a fully local setup use Ollama or a self-hosted endpoint." and "Recommended: free, open-source models running locally via Ollama. Nothing leaves your Mac." Neither appears in `SettingsPane.swift` or `SettingsSections.swift` (grep). Controls are all present (see S5).
- Fix direction: owner to decide whether the privacy caption moves to the Provider section. These are copy changes, not control losses, so the finding is minor, not major.

**A5-6 (nit): Build warning about an unhandled test fixture.**
- Location: `Tests/WfflTests/Fixtures/jiva-khachar-excerpts.md`, reported by `swift build` as unhandled for target `wffl`. Add it to `exclude:` (or `resources:`) in `Package.swift`. Also confirm the fixture is meant to be committed, since the name suggests real transcript excerpts.

### Icon

**I5-1 (major): The Tinted appearance is missing.**
- Location: `Support/AppIcon.icon/icon.json` (Light default, Dark fill specialization only; no tinted or monochrome specialization). `Support/AppIcon.icon/Assets/bars.svg` hard-codes `#F2F2F0`.
- Evidence: `grep -c -i "tinted\|monochrome" icon.json` = 0. `xcrun actool` compiles the document (exit 0), so the layered icon ships without a tinted variant.
- SPEC: Part 3 requires Light, Dark and Tinted (bars as a single-colour foreground layer on the system tint).
- Fix direction: add the tinted appearance (monochrome foreground layer), and make the bars layer adaptable (not a fixed hex) so the system tint applies.

**I5-2 (nit): The 16 px icon uses five bars, not six.**
- Location: `scripts/makeicon.swift:11-12`. The generator uses 6 bars at 32 px and 5 at 16 px. SPEC Part 3 allows 6 bars for the small sizes.
- Fix direction: keep 5 if the 16 px render reads better on screen (verify in a native run), or switch to the SPEC's 6-bar variant. Either way, record the choice in the SPEC.

### Update film

**F5-1 (major): The film rebuilds the whole window every frame.**
- Location: `WelcomeJourneyView.swift:24` (`TimelineView(.animation)`), `WelcomeJourneyView.swift:52` and `FilmStage.swift:69`, `:107` (`FilmPalette(...)` per call, each converting 7 colours through `NSAppearance` and `NSColor`), `FilmStage.swift:59-60` (both full plates built every frame, even when hidden), `FilmStage.swift:114-138` (`clearOld` and `clearNew` each used about 10 times in the morph frame, so the old and new shells are instantiated roughly 15 times per frame), `WelcomeJourneyView.swift:105` (`.ultraThinMaterial` re-blurred each frame).
- Evidence: static reading. Frame times are UNVERIFIED (no native run).
- Fix direction: render the old and new plates once to cached layers (or images) and animate transforms and opacity on them; build the palette once per frame; instantiate each plate once per frame and reuse it; keep the caption material off the animating layer.

**F5-2 (major): Sidebar labels double-print mid-morph.**
- Location: `FilmStage.swift:127-128` and `:167` (`warp()` cross-fades the whole old and new nav stacks inside one rectangle). The rows' labels land at different offsets, so both sets print at once.
- Evidence: `scratchpad/film/morph-5.2.png`: "Dashboard", "Audio Files" and "Settings" show a second, offset copy of their labels.
- Fix direction: move each nav row's label along its own measured rect (per-row slide), and cross-fade only the row's content, not the stack.

**F5-3 (major): At 21.5 the "TRANSCRIPT" heading is cropped out of frame (SPEC 2.10.4 requires it readable).**
- Location: `FilmTimeline.swift:105-107` (camera key `(19.2, 1.32, 640, 430)` and the hold to 24.4). At scale 1.32 focused on (640, 430) the heading sits above the top edge.
- Evidence: `scratchpad/film/film-21.5.png` starts at "00:41 · Me". The title and heading are not visible.
- Fix direction: owner decision. Either change the focus of the 19.2 to 24.4 key (for example, y 380), or adjust the test to say the heading is on screen. This is a SPEC-vs-mockup conflict; the mockup has the same keys.

**F5-4 (major): The pixel-diff acceptance test is circular, so SPEC 2.2.4 is not met.**
- Location: `Tests/WfflTests/UpdateFilmTests.swift:72-103`. "Legacy" references render `LegacyShell` in-process; "live" references render `AppShell` in-process. The film's old and new plates are those same views, so the test checks the composition, not the fidelity of the copied old app or the live Home.
- SPEC: 2.2.4 requires comparison with real screenshots of the old and new app.
- Fix direction: capture real screenshots of the v1.9.0 build and the new build at 900x560 and 1100x700 (checked in as fixtures), and compare the film to those. Add a test that fails if `LegacyShell` changes.

**F5-5 (major): The film's readiness rows show the machine's live state, not sample data.**
- Location: `FilmStage.swift:95-97` injects `ModelManager.shared`, `ParakeetModelManager.shared`, `BapsModelManager.shared`. `HomeView.swift:33-34` and `:148-151` derive "Transcription" and "Summary service" from them. Only mic and system audio use the sample flag (`HomeView.swift:154`, `:159`).
- Evidence: the film frames show "BAPS Whisper Ready" on this machine. On a machine without the model, the frame would show "Model needed · open Settings". Pixel tests would then differ by machine.
- SPEC: 2.2.1 requires `PreviewRuntime` sample data (ready states).
- Fix direction: inject sample readiness for the film (for example, a `filmSample` branch in `HomeView` that returns the sample engine and summary states), so the film is deterministic.

**F5-6 (major): VoiceOver reads each caption twice.**
- Location: `WelcomeJourneyView.swift:56-59` (captions have no `accessibilityHidden`), `:75` and `:80-86` (summary overlay added on top).
- SPEC: 2.8 requires one summary element for the film, updated per caption.
- Evidence: static. VoiceOver run is UNVERIFIED.
- Fix direction: `.accessibilityHidden(true)` on the caption views (and on the Skip and hairline if they duplicate), leaving the summary element as the only spoken element.

**F5-7 (minor): The morph mark follows HEAD's W, not SPEC 2.6's numbers, and ends as capsules.**
- Location: `FilmStage.swift:140-141` (`lineScale` 0.14 and 0.11 against SPEC's 9/100), `FilmStage.swift:249` (HEAD W points, which match HEAD's `WMark`), `FilmStage.swift:248` (capsule heights, the final state of `WMarkView`, not SPEC's ellipses).
- Note: following HEAD and `WMarkView` is the right call for the app. The SPEC numbers are the mockup's. Owner to approve the divergence.
- Fix direction: approve or amend SPEC 2.6. Pixel-check the stroke weight against the real old mark (UNVERIFIED).

**F5-8 (minor): "Start Recording" and "Import Audio" pills overlap mid-morph.**
- Location: `FilmStage.swift:124-138` (old and new button warps). The mockup has the same geometry.
- Evidence: `scratchpad/film/morph-6.2.png`. The two pills overlap for about half a second.
- Fix direction: stagger the import pill's move (start after the start pill has moved), or accept as transitional and say so in the SPEC.

### Settings (regression check)

No findings. Details in the section below.

---

## Settings regression check (SettingsView to SettingsSections and SettingsPane)

- AppStorage keys: all 24 keys from HEAD `Views/SettingsView.swift` exist in the new sources (`whisperModel`, `vocabMode`, `translate`, `transcriptionProfile`, `transcriptionEngine`, `systemAudioEnabled`, `sysGain`, `summaryTemplate`, `summaryPrompt`, `ollamaURL`, `micGain`, `micDeviceID`, `llmProvider`, `llmModel.{openrouter,ollama,groq,custom,anthropic}`, `language`, `diarizationEnabled`, `customBaseURL`, `autoRecordMode`, `autoPolish`, `arbiterModel`).
- Defaults: identical for all keys (compared line by line: e.g. `autoRecordMode = "nudge"`, `transcriptionEngine = "baps"`, `whisperModel = "large-v3-turbo"`, `sysGain = 0.8`).
- Prefs helpers: `effectiveEngine`, `effectiveWhisperModel`, `apiKey`, `setAPIKey`, `markProfileExplicit` all present.
- Controls: every HEAD control has a counterpart. Engine picker is now a row set in `SettingsPane.swift:33-37`. Meeting detection (Off, Nudge, Auto-start) at `SettingsPane.swift:52-56`. "What's New in Wffl…" at `SettingsPane.swift:76`. Download and Retry buttons for the three models. Vocabulary, Ollama, provider keys and models, custom endpoint, minutes template reset, Storage "Show in Finder", diarization, known speakers, About links.
- Copy-only changes: shortened labels (for example "Re-transcribe and clean after recording"), and removed captions (A5-5).
- Film inertness: `PreviewRuntime` flags are DEBUG-gated (`PreviewRuntime.swift:4-35`). Film environment values default to false or nil (`PreviewRuntime.swift:57`, `FilmAnchors.swift:19-21`). Anchor modifiers run in normal use but have no effect (negligible cost; nit, not counted).

---

## Patterns and systemic issues

1. **The reference and the SPEC disagree on several acceptance values.** The mockup produces the same results as the production page for 1.4 centring (85 px), 5.29 caption switch, 8.1 name ("Priy"), 16.2 step 3 (0.973), R2.5(b) docs width (52.1%), the rail over the Minutes card, and the 1.11.10 ember rule. The owner should decide, per item, whether to change the reference or amend the SPEC. The implementation should not silently diverge.
2. **The film's acceptance is circular.** Both pixel-diff references come from the same code as the film (F5-4). The test passes, but it cannot fail on a fidelity regression of the old app.
3. **The film recomputes too much per frame** (F5-1). The same root cause makes the morph ghosting (F5-2) and the pill overlap (F5-8) harder to tune.
4. **Sample data and live state are mixed in the film** (F5-5). Anything the film shows about readiness should be sample data, per SPEC 2.2.1.

---

## Verified positives

- Website: scene copy is verbatim against SPEC (spot-checked every scene, interludes I1 and I2, the chips, the steps and the footer). Sample labels are visible where sample data appears (scene 2 caption, scene 3 group captions, scene 4 header and footnote). Single h1, skip link, labelled sections, no live region. Reduced motion works without a pin. Zero console errors on the primary URL. All five external links return 200. No notarization claim. No horizontal scroll at 390x844. Dark theme flips scenes 2 and 5 and the nav ink correctly.
- Website copy truthfulness: the clean-up stage now shows the real feature (Raw/Cleaned, timecodes, filler strike-through), matching `CleanupPipeline`.
- Film timeline: every caption window, camera keyframe and easing matches SPEC 2.4. The sample copy (kirtan and satsang underlines, "Sample · illustrative", BAPS band text) is verbatim.
- Film lifecycle: capture before migrations (`WfflApp.swift:35-41`), COUNT-based returning check (`Database.swift:325-327`), acknowledgement rules (`WelcomeJourney.swift:81-95`), preview flags gated to DEBUG.
- Icon: geometry, bar positions and heights, tile gradient and dark appearance all match SPEC Part 3. The layered icon compiles. The `.icns` has all sizes. The generator, bundle script and document agree.
- Settings: full parity on keys, defaults and controls (see above).

---

## Audit health score (impeccable lens, 0 to 4 per dimension)

Website:

| Dimension | Score | Key finding |
|---|---|---|
| Accessibility | 3 | Good structure. Selected segment label 3.7:1 (W5-8). Transcript unlabelled (W5-11). |
| Performance | 3 | Static reading is fine (one canvas, bounded DOM writes). Runtime frame timing UNVERIFIED. |
| Theming | 3 | Tokens consistent; dark mode works. Selected-segment colour (W5-8). |
| Responsive | 3 | No overflow, copy never covered at 390. Speaker 2 clipped on phones (W5-1). |
| Implementation integrity | 3 | Copy verbatim, labels honest. Reference-inherited conflicts (Patterns 1). |
| Total | 15/20 | Good (14 to 17). Address the weak dimensions. |

App and film (native; responsive not scored because native composition is UNVERIFIED):

| Dimension | Score | Key finding |
|---|---|---|
| Accessibility | 2 | Nav trait fixed. Coverage thin in four views (A5-2). Film double-reads captions (F5-6). |
| Performance | 1 | Film rebuilds the window per frame (F5-1). App views fine. |
| Theming | 3 | Tokens used widely. One SF nav label (A5-1). |
| Implementation integrity | 2 | Film tests circular (F5-4), readiness live (F5-5), tinted icon missing (I5-1). |

---

## UNVERIFIED (needs native launch or a runtime the harness does not have)

Website:
- Reduced motion at 390x844 (only the 1440 scratch copy was run).
- Dark mode at 390x844.
- Mobile hero intro timing (bars grow on load).
- Favicon rendering in a browser tab.
- Keyboard activation: skip link focus, Tab order, rail click-to-jump (the rail buttons are labelled and reachable in the DOM, but were not exercised).
- Frame timing and jank in a real browser (the pane runs no frames when hidden; scroll checks were done by reading state after waits).
- The DMG notarization claim (round 4 W-7).
- Mockup mobile lanes: inferred from identical CSS, not measured separately.

App and film:
- Film pixel fidelity against real v1.9.0 and live screenshots (SPEC 2.2.4). Not run.
- Film frame times on a real Mac (F5-1).
- Film in dark mode.
- VoiceOver traversal (F5-6, A5-2).
- Escape, Space and Skip with real key events.
- Composition at 900x560, the minimum window, in the real app.
- Settings window rendering.
- Layered icon in the Dock and in the tinted appearance (I5-1). 16 and 32 px legibility on screen (I5-2).
- A-10 linker warning: needs a clean build.
- `DESIGN.md` documentation of the danger token (A-8 part 2) and the handoff docs (W-6 part 2).

---

## Verdict per surface

1. **Website: structure approved; not yet approved to ship.** Three pinned journeys with scroll-driven state, verbatim copy, honest sample labels, working reduced motion. Blocking for ship: W5-1 (Speaker 2 on phones). Needs an owner decision on the reference-inherited acceptance values (W5-2, W5-3, W5-4, W5-5, W5-7, R2.5(b), 1.11.10). Fix W5-6 (reduced-motion end states) and W5-8 (segment contrast).
2. **App redesign: most round-4 items closed; not final.** Open: A-1 (one nav label), A-4 (coverage), P-7 (busy feedback), A-12 (doc line). Native composition, dark mode and VoiceOver still need a run.
3. **App icon: near ready.** Light and Dark, geometry and sizes match SPEC. Add the tinted appearance (I5-1) before shipping.
4. **Update film: not approved.** Six major findings (F5-1 to F5-6). The acceptance tests pass but do not test what SPEC 2.2.4 asks. The film needs sample readiness, per-frame work cut, a fix for the label ghosting, and a readable heading at 21.5 (or an owner decision on the camera key).
5. **Settings consolidation: approved.** No key, default or control lost. Copy changes are listed (A5-5).

---

## Paths

- This report: `/Users/purvarajsinhgohil/Developer/Wffl/docs/design-review/qa-round-5.md`
- Film frames: `/private/tmp/claude-501/-Users-purvarajsinhgohil-Developer-Wffl/41cd86ff-24f1-4786-b517-05a2ce4a9623/scratchpad/film/` (for example `morph-5.2.png`, `film-21.5.png`, `film-31.9-1100.png`, `live-1100.png`, `legacy-1100.png`)
- Icon renders: `/private/tmp/claude-501/-Users-purvarajsinhgohil-Developer-Wffl/41cd86ff-24f1-4786-b517-05a2ce4a9623/scratchpad/icon/` (`sheet_s.png`, `icon_16.png` to `icon_1024.png`, `touch180.png`)
- Build and test logs: `/private/tmp/claude-501/-Users-purvarajsinhgohil-Developer-Wffl/41cd86ff-24f1-4786-b517-05a2ce4a9623/scratchpad/r5-swift-build.log` and `r5-swift-test.log`
- Scratch reduced-motion copy (not in project): `/private/tmp/claude-501/-Users-purvarajsinhgohil-Developer-Wffl/41cd86ff-24f1-4786-b517-05a2ce4a9623/scratchpad/rm/index.html`
