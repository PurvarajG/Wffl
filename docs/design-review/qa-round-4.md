# QA round 4: website, app redesign, app icon, welcome-back journey

Date: 2026-10-22. Tester: QA pass, read-only on source. The only file written is this report.
Scope: four surfaces. IDs: W = website, A = app redesign (SwiftUI), I = app icon, P = welcome-back / what's new popup.

Totals: 2 blocker, 15 major, 26 minor, 3 nit (46 findings). Items marked UNVERIFIED were not observed at runtime or were not checked with the required tooling.

## How this was checked

- Website: served `website/` with `python3 -m http.server` on 127.0.0.1 (stopped afterwards). Inspected with the built-in browser at 1440 desktop and 375 mobile (emulated), light and dark, and with reduced motion. Reduced motion was forced with a scratch copy in the scratchpad that rewrote only the media query strings; `website/index.html` was not edited. Measured geometry, overflow, computed contrast (every rendered text node, with ancestor opacity and backgrounds), focus order, ARIA and meta with JavaScript. Glyph coverage checked with fontTools (in a scratchpad venv) against `website/fonts/*.woff2`. External URLs checked with `curl -I`.
- App: `swift build` exited 0 (incremental, 5.9 s; one linker warning, see A-10). `swift test --filter 'WelcomeJourneyTests|ProcessingDisclosureTests'`: 8 tests, 0 failures. Source read in full for Theme, AppFonts, WelcomeJourney, WelcomeJourneyView, ContentView, HomeView, RecordingBar, InstrumentComponents, PreviewRuntime, ProcessingDisclosure, and grepped across all Views. Token math computed with the sRGB relative-luminance formula.
- Icon: `Support/AppIcon.icns` unpacked with `iconutil -c iconset` into the scratchpad. Dimensions checked with `sips`. Alpha bounds measured with ImageMagick. Bundled copy compared by md5 with `dist/Wffl.app/Contents/Resources/AppIcon.icns` (identical).
- Not done, and why: I did not launch the native app. Preview mode can isolate data, but capturing a window needs Screen Recording access and would capture the owner's screen. Every app-level visual below is therefore UNVERIFIED and based on code. I did not download the v1.9.0 DMG. VoiceOver was not run.
- Existing reviews checked: `docs/design-review/website-ui-review.md`, `app-ui-review.md`, `native-implementation-checks.md`, `welcome-journey-design.md`. Status is in the "Existing reviews" note at the end.
- Tool limitation: browser screenshots are cropped or scaled differently from the CSS viewport, so measurements come from JavaScript geometry and the screenshots were used only for judgement.

---

## Surface 1: Website (`website/index.html`, committed at ffd0aab)

Note on source: two divergent builds exist. The committed `website/index.html` (39,231 bytes) is audited here. `design-handoff/website/index.html` (56,651 bytes) is a different build with a live dot-field hero and an older journey. The handoff README says the tracked file "currently holds the new design uncommitted". That is stale, since the file is committed.

### W-1 (blocker): the journey is a pinned card with six states, not an entered space

- Location: `website/index.html` lines 334-364 (`.cinema`, `#instrument`, six `.story-beat` articles), CSS 144-187, script 450-474. Measured at 1440x900.
- What is wrong: the owner asked for an Apple-style journey where you enter spaces through scroll-driven camera and transform. What shipped is a two-column split. A fixed 643x832 stage card sits on the right, and each `.story-beat` (832px tall) sets `data-ch` on the nearest beat. Scene changes are threshold class switches with CSS transitions, not scrubbed transforms. The only scroll-linked motion is the 2px progress bar and a plus or minus 24px `--drift` on a glow. After the six beats (about 5,000 of 7,878px of page height) the page drops into the conventional stacked sections: privacy panel, setup rows, closing.
- Evidence: measured beat tops 68, 900, 1732, 2564, 3396, 4228 (1440 viewport); privacy begins at 5,060. JS `direct()` picks the beat closest to 52% viewport and sets `stage.dataset.ch`. No `transform` is interpolated against scroll progress anywhere in the file. Visual check: the stage is a framed composition in one column, not a space that the page moves through.
- Fix direction: pin one full-bleed environment for the whole journey. Drive a single scroll-progress variable (0 to 1) and interpolate keyframes per scene (scale, translate, opacity, blur) so the camera moves continuously. Let the chapter copy sit in a stable anchored column over that environment. Keep the reduced-motion end states (already correct, see verified list). Use fewer, taller beats.

### W-2 (major): a hard-edged rectangular tint sits behind the stage

- Location: `website/index.html` line 148 (`.instrument-light`, `inset: 9% -18% 5% -14%`, two radial gradients).
- What is wrong: the tint box has a visible boundary. The gradients do not reach transparent before the box edge, so the box reads as a panel. The box is also clipped by `body { overflow-x: clip }` on the right.
- Evidence: bounding box at a 1024x768 viewport is left 394, right 1059, top 130, bottom 732. A zoomed dark-mode screenshot of chapter 4 shows a sharp vertical edge at the box's left side. A light-mode screenshot shows the same edge. The cause is inferred from the gradient stops; the visible edge itself is observed.
- Fix direction: make the radial fade to 0 alpha inside the box (stops at 100% of the box, or an ellipse sized to the box), or apply the glow with a blur filter on an element that is not clipped. Check both themes.

### W-3 (major): on phones, copy scrolls under the sticky stage and is cut mid-line

- Location: `website/index.html` lines 199-201 (mobile `.instrument`: sticky, `z-index: 3`, `background: var(--bg)`), 229 (`.story-beat` min-height).
- What is wrong: at 375px the stage occupies y 68 to 409 and is opaque. Chapter copy scrolls beneath it and is clipped by a hard edge with no fade. In chapter 4 the line "paragraphs with topic headings. Keep" is cut in half.
- Evidence: mobile screenshots at beats 3 and 4 (chapter 04 "The clarity", chapter 05 "The takeaway").
- Fix direction: add a mask or gradient at the stage's bottom edge so text fades out, or shrink the stage so copy scrolls below it and never passes under it.

### W-4 (major): the clean-up chapter shows a summary, not the clean-up the copy describes

- Location: `website/index.html` line 359 (copy for "03 / THE CLARITY") versus line 349 (`.document-summary`, shown at `data-ch="3"` per CSS line 183) and the `.meeting-words` hidden at line 182.
- What is wrong: the copy says "Clean up a transcript into readable paragraphs with topic headings. Keep timecodes and return to the raw version whenever you need it." The stage shows two summary lines ("Show the model size before download. Update the picker. Ship the new flow.") under the title "Design review". No headings, no timecodes, no Raw/Cleaned control. The feature exists in the app: the Raw/Cleaned control is at `Sources/Wffl/Views/TranscriptView.swift:28-29` and timecodes are kept in `Sources/Wffl/LLM/CleanupPipeline.swift:7`. The stage misrepresents the feature.
- Fix direction: show a cleaned transcript with topic headings and timecodes, and a Raw/Cleaned segmented control with the filler strike-through. The handoff build did this in its scene 3 (`design-handoff/website/index.html` line 452).

### W-5 (major): chapter numbers disagree between the stage and the copy

- Location: `website/index.html` line 432 (stage captions `01 / Recording` to `06 / Your library`) versus lines 356-361 (kickers `01 / THE WORDS` to `05 / THE RETURN`).
- What is wrong: two numbering schemes run side by side and are offset by one. In chapter 2 the stage says "02 / Transcribing" while the copy says "01 / THE WORDS". Chapter 1 has no number at all in the copy.
- Evidence: JS readout per beat: caption "02 / Transcribing" at beat index 1, kicker "01 / THE WORDS".
- Fix direction: one numbering scheme, the same index on the stage and in the copy.

### W-6 (major): DESIGN.md and the handoff docs describe components the shipped page does not have; some CSS is dead

- Location: `design-handoff/DESIGN.md` (sections "Journey stage", "Rail and chapter markers", "Live card", "Setup rows", "Privacy panel"), `design-handoff/README.md` (status line), `design-handoff/TODO.md` item 4 (hero script and dot field); shipping CSS: `website/index.html` 133 and 295 (`.hero::after`, `.hero` does not exist in the markup), 260-263 (`.js .out` reveal rules, `.js` class is never added), 281 (`.step.in .n`, `.in` is never added).
- What is wrong: DESIGN.md says the rail and chapter markers, the live dot-field hero card, the once-only IntersectionObserver reveals for privacy rows and setup numerals, and the timecode tween exist. The shipped page has none of them (grep: 0 hits for rail, marker, canvas, IntersectionObserver, `class="live`, `class="tc"`). Because `.js` and `.in` are never set, the setup numerals never darken (they stay `#8A8A86`, confirmed in the mobile screenshot) and privacy rows are never hidden or animated. The handoff copy with the dot-field hero still contains "Priya" and "Marcus" names that TODO item 1 asked to remove.
- Fix direction: pick one source of truth. Either restore the promised components or update DESIGN.md to the shipped reality. Delete dead rules. Make the handoff README's status line accurate.

### W-7 (major, UNVERIFIED): "Signed and notarized" is stated as fact and not checked

- Location: `website/index.html` line 394 ("Signed and notarized, so it opens normally.").
- What is wrong: the claim may be true for the published release, but nothing here confirms it. `scripts/bundle.sh` lines 11-14 and 47 sign with a self-signed "Wffl Dev" identity for local builds. `docs/RELEASING.md` describes a notarizing release workflow. The v1.9.0 release asset `Wffl.dmg` exists (created 2026-10-21 13:03 UTC, 5,271,648 bytes). The DMG was not downloaded, so notarization and stapling were not verified.
- Fix direction: before shipping, run `spctl -a -vv -t install` and `xcrun stapler validate` on the published DMG and record the result. Soften the copy if it cannot be verified.

### W-8 (minor): the motion toggle's ARIA is wrong

- Location: `website/index.html` line 328 (`#motion-toggle`), lines 440-441 (label and `aria-pressed` set together), 441 (`aria-pressed` = `paused || preference.matches`).
- What is wrong: the button label changes between "Pause motion" and "Resume motion" and `aria-pressed` also flips. A screen reader announces both, which is redundant and contradictory. Under reduced motion the button is disabled, its label reads "Motion reduced", and `aria-pressed` is "true", which claims a state the user did not set.
- Evidence: in normal motion, clicking gives label "Resume motion" with `aria-pressed="true"` and `html.motion-paused`; under reduced motion, disabled with `aria-pressed="true"`.
- Fix direction: keep one constant label ("Pause motion") with `aria-pressed` alone, or use a plain button whose label changes and no `aria-pressed`. Under reduced motion, use `aria-disabled` with an explanation, not a pressed state.

### W-9 (minor): phone nav removes the section links

- Location: `website/index.html` line 238 (`.nav-link { display: none }` below 640px).
- What is wrong: Features and Privacy are hidden on phones. The nav keeps only the brand, Pause motion and Download.
- Fix direction: keep at least one section link or add a compact menu.

### W-10 (minor): the Pause motion control is small to hit

- Location: `website/index.html` line 197 (`.motion-toggle { padding: 8px; font: 12px }`).
- Evidence: measured 66x25px at 375px (WCAG 2.2 2.5.8 passes at 24px; Apple HIG asks 44pt).
- Fix direction: enlarge the hit area to at least 44px high without changing the visual.

### W-11 (minor): the font subsets lack four glyphs the page uses

- Location: arrows and search glyph in `website/index.html` lines 348 (`→`), 350 (`↳`), 352 (`⌕`), 356 and 361 (`↓`).
- Evidence: fontTools. Hanken Grotesk subset lacks U+2192, U+2193, U+21B3, U+2315. Fragment Mono subset lacks U+2192, U+21B3, U+2315. The glyphs fall back to a system font, so they will not match.
- Fix direction: add the glyphs to the subsets or draw the arrows as inline SVG.

### W-12 (minor): on phones the collapsed sound trace draws a dashed rule across the document titles

- Location: `website/index.html` lines 204 and 214 (`.sound-trace` at top 25%, `translateY(-76px) scaleY(.035)` for chapters 1 to 5).
- Evidence: mobile screenshots of chapters 2 to 6 show a dashed line running from the document title ("Design review" and "YOUR LIBRARY" captions).
- Fix direction: hide the collapsed trace in chapters 1 to 5 on narrow screens or move it clear of the title.

### W-13 (minor): text below the 11px floor on the phone stage

- Location: `website/index.html` 207 (`.document-meta` 10px), 213 (`.instrument-sample` 10px), 220 (`.minute-action small` 10px), 221 (`.minutes-disclosure` 10px), 228 (`.library-plane > .cap` 10px), 230 (`.story-kicker` 10px).
- What is wrong: DESIGN.md sets an 11px floor for mono labels. The sample disclosure ("Sample meeting · illustrative content") is also the only place the sample label appears on phones.
- Fix direction: raise to 11px minimum.

### W-14 (minor): metadata and icon gaps

- Location: `website/index.html` lines 6-14 (head).
- Missing: `og:image`, `og:url`, `og:site_name`, `<link rel="canonical">`, `twitter:card`, `apple-touch-icon`. `/favicon.ico` returns 404 (curl). There is no skip link. The favicon is an SVG data URI only.
- Fix direction: add canonical and social tags with a 1200x630 og:image, add a 180px PNG apple-touch-icon, and provide a `favicon.ico` fallback.

### W-15 (minor): the eyebrow kicker is still above every chapter heading

- Location: `website/index.html` lines 356-361 (`.story-kicker`, mono, uppercase, above each h2).
- What is wrong: TODO item 5 asked to remove the eyebrow pattern. The shipping page still uses one above every chapter title, and the chapter 5 kicker "THE RETURN" is copy, not data.
- Fix direction: drop the kicker, or move the number into the rail gutter.

### W-16 (minor): the speaker scene never shows "Speaker 2"

- Location: `website/index.html` line 345 (`#speaker-one`), line 358 (copy "Other voices start as Speaker 1, Speaker 2."), line 466 (name logic), 479 (rename sets "Priya").
- What is wrong: the copy says two numbered speakers. The scene has one other voice, so "Speaker 2" never appears. The rename produces "Priya", which is fine as sample data (labelled) but not the numbered model the copy describes.
- Fix direction: show a second voice ("Speaker 2") so the copy matches, or change the copy to "Other voices start as Speaker 1."

### W-17 (minor): a live region announces the speaker change on scroll

- Location: `website/index.html` line 345 (`aria-live="polite"` on `#speaker-one`), updated at line 466 on every chapter change.
- What is wrong: a screen reader user scrolling past chapter 3 hears "Speaker 1" announced, though nothing was asked for. Decorative state changes should not be live.
- Fix direction: remove `aria-live` from the stage, or announce only after a user action.

### W-18 (nit): a heading precedes the h1 in DOM order

- Location: `website/index.html` line 350 (`h3` in `.minutes-plane`) precedes line 356 (`h1`).
- What is wrong: the h3 is `visibility: hidden` until chapter 5, so assistive tech skips it now. The order would break if the visibility rule changed.
- Fix direction: give the stage its own heading-free markup or move the h3 out of the flow.

### Website: verified OK

- No horizontal overflow at 1440 or 375 (`docW` 1425 and 375).
- Computed contrast of all rendered text, light and dark, with ancestor opacity and backgrounds: 0 failures against 4.5:1 (3:1 for large text). The TODO's 0.34 opacity on inactive chapters is already fixed: inactive beats are at opacity 1.
- Reduced motion: with the forced-media scratch copy, every chapter shows its complete state (chapter 2 names, chapter 3 summary, chapter 4 minutes, chapter 5 library). The toggle reads "Motion reduced" and is disabled.
- Pause motion: sets `html.motion-paused`, and the CSS loops (`listen` bars) move to `animation-play-state: paused` (checked).
- Sticky stage holds at top 68 mid-journey (checked at chapters 2, 3 and 5).
- Focus outline and tab order: focusable elements are in order. The rename button is `tabindex=-1` and hidden until chapter 3.
- Claims checked against source: silence-aligned chunks (`Sources/Wffl/Transcription/AudioChunker.swift`), Markdown export, Raw/Cleaned toggle, timecodes, Pause/Resume, "no telemetry" (`SettingsView.swift:735`, no analytics SDK in `Sources/Wffl`), network calls are model downloads and user-configured endpoints.
- Links: `github.com/PurvarajG/Wffl/releases/latest/download/Wffl.dmg` returns 302 to `releases/download/v1.9.0/Wffl.dmg`. Repo, Ollama and Meetily URLs return 200.
- Console: no errors captured on the primary URL.
- Speaker, privacy and engine copy fixes from the earlier review are present (BAPS 1.6 GB, Whisper for other languages, privacy pills "On-device / Not required / None / Off by default").

---

## Surface 2: App redesign (SwiftUI, `Sources/Wffl`)

### A-1 (major): typography is not on the tokens; two type systems are mixed on the same screens

- Location: `Sources/Wffl/Views` has 66 `.system(size:)` calls against 112 `Theme.text/mono/display` calls. Examples: `ContentView.swift:225` (sidebar nav labels at 12.5pt, SF), `ContentView.swift:198,202` (sidebar footer), `AudioFilesView.swift` (12 system calls), `SummaryView.swift` (9), `DashboardView.swift` (8), `MeetingListView.swift` (6), `TranscriptView.swift` (4), `SettingsView.swift` (4), `WelcomeJourneyView.swift` (8, intentional canvas).
- What is wrong: the Hanken Grotesk tokens are applied in some places and bypassed in others. In the sidebar the brand "Wffl" uses Hanken (`Theme.text(21)`, line 149) and the nav rows use SF (line 225). A single screen can show both families.
- Evidence: grep counts above. `AppFonts.sans` falls back to `.system` when the font is missing, so the fallback is also silent.
- Fix direction: route every size through `Theme.text`, `Theme.mono` or `Theme.display`. Add a token for the 12.5pt and 10.5pt sizes if needed. Remove direct `.system(size:)` from views except icons.

### A-2 (major): the Settings window (Cmd+,) still shows the old Form UI; two settings UIs bind the same keys

- Location: `Sources/Wffl/Views/SettingsView.swift` (struct at line 3, `Form` at lines 62 and 314, `Section("Engine")` at line 87, Picker "Transcription engine" at line 92). Used by the Settings scene at `Sources/Wffl/WfflApp.swift:161`. The redesigned `Sources/Wffl/Views/SettingsPane.swift` is the sidebar section, used at `ContentView.swift:121`.
- What is wrong: `SettingsView` changed by 26 lines in this redesign. It has 2 `Theme` references, 4 system fonts, 7 fixed widths and 4 raw colours. It writes the same AppStorage keys as `SettingsPane` (`transcriptionEngine`, `whisperModel`, `llmProvider`, `ollamaURL`, `customBaseURL`) through a different layout. Pressing Cmd+, shows a different product from the sidebar. This is a leftover old-design view and a mismatched component between screens.
- Fix direction: make the Settings scene host `SettingsPane` (or delete `SettingsView` after moving its unique controls). One source for each setting.

### A-3 (major): contrast fails for the recording label and for secondary sidebar text

- Location: `Sources/Wffl/Views/RecordingBar.swift:43-44` (stateLabel set to `Theme.live` while recording, mono 11pt). `Sources/Wffl/Views/ContentView.swift:199,202` (`Theme.secondary` on `Theme.raisedBG`, 10pt).
- Evidence (computed): `Theme.live` = #FF5B1F on the app background #F2F2F0 is 2.77:1 and on the card #FFFFFF is 3.10:1; both fail 4.5:1 for 11pt text. `Theme.secondary` #6B6B67 on `raisedBG` #E9E9E6 is 4.40:1, which fails 4.5:1 for 10pt text. Dark mode passes (ember-dark on #0F0F0F is 6.72:1).
- Fix direction: use `Theme.ink` or the existing `Theme.clayText` (#B8390C, 5.16:1 on the app background) for the RECORDING text. Keep ember only on the lamp dot, which is non-text. Darken `secondary` on the raised surface or use `muted` (4.77 on the app background) for 10pt text.

### A-4 (major): accessibility coverage is thin and the selected section is not exposed

- Location: zero `accessibilityLabel` or `accessibilityAddTraits` in `ContentView.swift`, `TranscriptView.swift`, `SummaryView.swift`, `MeetingDetailView.swift`, `MeetingListView.swift`, and `SettingsView.swift`. `ContentView.swift:215-244` (`navRow`) has no `.isSelected` trait, so VoiceOver cannot tell which section is current. Count badges read without a noun. `TranscriptView.swift:243-264` (speaker chip) has `.help` but no accessibility label or hint, so the rename action is not announced as an action.
- Fix direction: add `.accessibilityAddTraits(selected ? .isSelected : [])` to `navRow`. Label count badges ("12 meetings"). Give speaker chips "Rename speaker X" as label and "Double-click to rename" as hint. Run a VoiceOver pass (UNVERIFIED at runtime).

### A-5 (minor): the Home headline asserts readiness that the rows below can contradict

- Location: `Sources/Wffl/Views/HomeView.swift:104` ("Ready when you are.") and the readiness rows at lines 131-146 ("Model needed · open Settings", "Permission needed", "Check provider in Settings").
- What is wrong: the headline says the app is ready while the same screen can show a missing model or missing permission.
- Fix direction: make the headline state-aware, or use neutral copy ("Record the conversation. Find the words and decisions later.") and let the rows carry the status.

### A-6 (minor): text under the 11px floor in the app

- Location: `AudioFilesView.swift:67,113` (9pt), `:133` (9pt medium), `:149` (9.5pt semibold); `MeetingListView.swift:33` (9.5pt), `:133` (9.5pt); `TranscriptView.swift:257` (9pt icon); `ContentView.swift:188` (10pt Later), `:198,202` (10pt footer), `:229` (10.5pt count).
- What is wrong: DESIGN.md sets an 11px minimum for mono labels, and these are below it. Some of these are labels a user needs to read (counts, status, footer privacy line).
- Fix direction: raise to 11pt minimum. Use the Theme text helpers.

### A-7 (minor): dead code and unused state

- Location: `Sources/Wffl/Views/RecordingBar.swift:227` (`LevelMeter`, no callers). `Sources/Wffl/Views/InstrumentComponents.swift:16-26` (`InstrumentGlow`, no callers; its `reduceMotion` at line 17 is unused). `Sources/Wffl/Support/Theme.swift:20` (`darkBG`), `:28` (`accentMid`), `:34` (`teal`), `:38` (`heroGradient`), no callers. `Sources/Wffl/Views/HomeView.swift:11-12` (`@AppStorage selectedEngine` and `profile`, never read; they still trigger re-renders on change).
- Fix direction: delete these.

### A-8 (minor): token drift and an undocumented colour

- Location: `Sources/Wffl/Support/Theme.swift:37` (`floatingBackground` 0x101010) versus the DESIGN token `#0F0F0F` in `design-handoff/README.md` (adaptive `appBG` at line 17 uses 0x0F0F0F). `Theme.swift:33` (`danger = clayText`, #B8390C light / #FF8A62 dark) is a second warm colour for warnings. `design-handoff/DESIGN.md` does not list an error or danger token. It is used in `RecordingBar.swift:103` (device warnings).
- Fix direction: align the floating background with the token or document it. Add a named danger token to DESIGN.md with its contrast values.

### A-9 (minor, UNVERIFIED visually): summary checkboxes look tickable

- Location: `Sources/Wffl/Views/SummaryView.swift:154-156` (`- [ ]` and `- [x]` rendered as `square` and `checkmark.square` SF symbols).
- What is wrong: the review asked to keep action items as document notation because the app does not persist their state. Square and checkmark glyphs read as interactive checkboxes. Nothing here persists the state.
- Fix direction: render as text notation (for example "Open" or "Done" labels) or a plain bullet, with no toggle affordance.

### A-10 (minor): build warning for the vendored whisper library

- Location: `Package.swift:5` (`platforms: [.macOS(.v15)]`) and the `-L vendor/lib` link flag. `swift build` reports `libwhisper.a(whisper.cpp.o)` built for macOS 26.0 linking to 15.0.
- Fix direction: rebuild the vendored library with a macOS 15 deployment target, or document the mismatch.

### A-11 (nit): mono uppercase kicker on Home

- Location: `Sources/Wffl/Views/HomeView.swift:64` ("CONTINUE WHERE YOU LEFT OFF", mono 11pt uppercase).
- What is wrong: a small uppercase label above a card. DESIGN.md's "Not canonized" section says not to add these.
- Fix direction: sentence-case label, or drop it.

### A-12 (minor): the existing review doc describes the source as still old

- Location: `docs/design-review/app-ui-review.md`, opening paragraph ("Source is still the cream/sage/serif app").
- What is wrong: the source is now redesigned (17 modified Swift files). The doc is stale, and it is the doc the team would read first.
- Fix direction: update the status line after this round.

### App: verified OK

- Appearance pin removed: the only `NSApp.appearance` assignment is in the DEBUG preview branch (`WfflApp.swift:10-11`). `Theme` colours are adaptive (`Theme.swift:5-15`), with a high-contrast branch.
- Token values match the README list: `appBG` #F2F2F0 / #0F0F0F, `raisedBG` #E9E9E6 / #0A0A0A, `cardBG` #FFFFFF / #181818, `ink`, `body`, `muted` (#6B6B67 / #9B9B96), `clay` #FF5B1F / #FF6A33.
- Font packaging is fixed: `Package.swift` has `resources: [.copy("Resources")]`, `scripts/bundle.sh` copies `Wffl_Wffl.bundle` into the app, and `AppFonts.register()` runs at launch (`WfflApp.swift:34`). The OFL licence files are included.
- Pause, Resume, Mute and Stop state words are present (`RecordingBar.swift:9-17`, `:117-122`). The "System audio continues" wording while muted is correct.
- Keyboard model: ⌘⇧P, ⌘⇧M, ⌘⇧S menu commands (`WfflApp.swift:140-150`) match the `.help` hints.
- Window minimum 900x560 (`WfflApp.swift:123`).
- Privacy footer is now computed from the effective endpoint (`ContentView.swift:201`, `ProcessingDisclosure.swift`). The old "nothing leaves this Mac" line is gone. "Network: model downloads only" is gone.
- Speaker chips: "Me" for mic, rename popover on Speaker N (`TranscriptView.swift:243-285`).
- Build: `swift build` exit 0. Tests: 8 pass.

### App: UNVERIFIED (needs a native run)

- Composition at the 900x560 minimum (`HomeView.swift:50` ViewThatFits with a fixed 275pt readiness column; `ContentView.swift:106` fixed 220pt sidebar).
- Dark mode in practice (popovers, menus, progress states), Increase Contrast, Reduce Motion on live recording.
- VoiceOver and full keyboard traversal.
- Whether the old `WfflApp` Settings scene and sidebar pane render the same values.

---

## Surface 3: App icon (`Support/AppIcon.icns`, `scripts/makeicon.swift`)

Facts established: the icon has every macOS size (16, 32, 128, 256, 512, each at 1x and 2x, all with alpha). `Support/AppIcon.icns` (451,559 bytes, dated 2026-07-24) is byte-identical in content with `dist/Wffl.app/Contents/Resources/AppIcon.icns` (md5 9f5d28e8876e254f48f39210d9b7665f). It is the old design.

### I-1 (blocker): the shipped icon is the old design; the new mark is not in it

- Location: `Support/AppIcon.icns`, generated by `scripts/makeicon.swift` (header line 2 says "Per the design handoff README"; the W path at line 41 is `(22,32) (36,70) (50,46) (64,70) (78,32)`, a single stroke).
- What is wrong: the icon is a cream tile with a single-stroke dark-brown W, which is the former mark. `PRODUCT.md` (Brand Commitments) and `design-handoff/README.md` specify the eight-ellipse waveform that traces a W. The generator's header claims it follows the handoff README, which it does not. Three different marks are now in circulation: this icon (cream tile, single stroke W), the website favicon (black tile, eight white ellipses, `website/index.html` line 14), and the in-app `WMarkView` (eight capsules, no tile, `Sources/Wffl/Support/Theme.swift:54-70`).
- Evidence: rendered the 1024px iconset PNG and inspected it. Diff of the generator against the handoff README.
- Fix direction: replace the icon with the eight-bar mark (see recommendation below). Correct the generator's header or retire it.

### I-2 (major): the icon body is about 4% too large for the macOS grid

- Location: `scripts/makeicon.swift:11` (`let inset: CGFloat = size * 0.08`).
- What is wrong: inset 0.08 of 1024 gives a body of 860px. The macOS icon template uses an 824px body (100px margin on each side). The icon therefore sits visibly larger than neighbouring Dock icons.
- Evidence: ImageMagick alpha bounds at 40% threshold: `860x860+82+82` on the 1024px PNG.
- Fix direction: inset 100/1024 (body 824) and use continuous (superellipse) corners.

### I-3 (major, UNVERIFIED how macOS 27 renders it): no appearance variants

- Location: `Support/AppIcon.icns` (single opaque raster, no appearance variants). `Support/Info.plist` sets `CFBundleIconFile` = `AppIcon` (lines 23-24).
- What is wrong: the icon has no dark or tinted variant. The cream plate will render as a light tile in dark contexts. Current macOS supports layered `.icon` documents from Icon Composer with default, dark and tinted appearances.
- Fix direction: author the new icon as a layered Icon Composer document with light, dark and monochrome-tinted appearances, and keep the `.icns` as the fallback for older systems.

### I-4 (minor): a drop shadow and inner hairline are baked into the PNG

- Location: `scripts/makeicon.swift:17` (`ctx.setShadow`, blur 0.03 of size, alpha 0.18) and `:36` (inner hairline stroke at alpha 0.08).
- Evidence: alpha of 0.0118 at the pixel outside the body (x 60, y 512) is the shadow, which is baked into the PNG.
- What is wrong: macOS applies its own shading and shadow to icons. A baked shadow doubles up and leaves a grey halo on dark wallpapers.
- Fix direction: no shadow and no hairline in the artwork. Let the system draw the edge.

### I-5 (minor): website, app icon and in-app mark do not agree

- Location: `website/index.html:14` (favicon, black tile #0B0B0B with `rx 22`, eight white ellipses); `Sources/Wffl/Support/Theme.swift:54-70` (`WMarkView`, eight capsules with the same height ratios [1, .67, .33, .67, .87, .67, .33, 1], no tile); `Support/AppIcon.icns` (cream tile, single stroke).
- What is wrong: the height ratios match, but the form (ellipse versus capsule), the tile colour and the stroke differ. The owner will see the mismatch in the Dock, the browser tab and the sidebar.
- Fix direction: one mark, one form (use capsules, matching the pill rule and `WMarkView`), one tile treatment.

### I-6 (minor, UNVERIFIED): legibility at small sizes

- Location: `Support/AppIcon.icns` 16 and 32px renditions.
- What is wrong: not rendered for judgement. At WMarkView proportions, eight bars at 16pt are about 1.4px wide. The bars will blur.
- Fix direction: render the new mark at 16, 32 and 64px before choosing it. If it blurs, supply a simplified small-size variant (for example five bars) for the 16 and 32px slots.

### Recommendation: what the new icon must be

- Mark: the eight-bar waveform with heights [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1] (the proportions in `WMarkView`, `Theme.swift:58`, and the website favicon). Use capsules, not ellipses, so the icon matches the app and the pill rule.
- Tile: monochrome. Light default: tile #F2F2F0 with ink #0B0B0B bars. Dark variant: tile #0A0A0A with #F2F2F0 bars. Tinted: single-colour bars. Do not use ember. The ember-means-live rule applies to state, not to the brand.
- Grid: 824px body inside a 1024px canvas, continuous corners, no baked shadow or hairline.
- Small sizes: test 16 and 32px. Use a simplified variant below 32px if the bars blur.
- Deliver: an Icon Composer `.icon` with light, dark and tinted appearances, plus a regenerated `.icns` fallback. Update `scripts/makeicon.swift` or replace it, and correct its header.

---

## Surface 4: Welcome-back / what's new (`WelcomeJourneyView.swift`, `WelcomeJourney.swift`, tests, docs)

What is sound: the state machine (`WelcomeJourney.swift:28-86`) and its policy functions are covered by 8 passing tests. First-install exclusion holds: `captureReturningEvidence` (`WfflApp.swift:35`) runs before the migrations (lines 37-41), and it sets `notApplicable` on a fresh install (`WelcomeJourney.swift:116-117`). Acknowledgment is per campaign (`quiet-instrument-1`). Reduced motion gates the animation (`WelcomeJourneyView.swift:59`, `:162`, `:164`). Keyboard: Return continues (`:153`), Escape closes (`:61`), arrow keys move chapters (`:62-65`). Auto-presentation requires an active, idle first launch (`WelcomeJourney.swift:41-43`); a busy launch shows an invitation instead of a modal.

### P-1 (major): the "before" in chapter 1 is not the real old app

- Location: `Sources/Wffl/Views/WelcomeJourneyView.swift:257-282` (`LegacyWorkspace`: sidebar "Today", "Recordings", "Preferences"; title "Your meeting"; subline "Recording · Transcript · Notes").
- What is wrong: the story's "familiar Wffl" is invented. The HEAD sidebar was Home, Dashboard, Meetings, Audio Files, Settings (`git show HEAD:Sources/Wffl/Views/ContentView.swift`, lines 5-9), the same labels as today, and none of "Today", "Recordings" or "Preferences" appear in HEAD. The HEAD palette (cream #F7F3EC, sage, serif display, `git show HEAD:Sources/Wffl/Support/Theme.swift`) is approximated, but the layout is made up. The owner asked for a visual transition from the old design to the new one. A reader who knows the app will see a different old app.
- Fix direction: capture real HEAD screens (build the old commit, snapshot Home and Meetings with a preview fixture) and use those as the before plate. Or label the canvas explicitly as a sketch of the earlier look.

### P-2 (major): internal project name in user-facing copy

- Location: `Sources/Wffl/Views/WelcomeJourneyView.swift:23` ("Atlas’s BAPS Whisper transcribes English…").
- What is wrong: "Atlas" is an internal sibling project (`Sources/Wffl/Transcription/BapsWhisper.swift:5`, which says "Atlas's BAPS Whisper"). The website and `PRODUCT.md` say "BAPS Whisper". Users have no reason to know "Atlas", and the possessive attributes the model to another product.
- Related, outside design scope: `BapsWhisper.swift:35-45` reads and adopts model files from `~/Library/Application Support/Atlas/Models` when present. The owner should decide whether that is intended. UNVERIFIED for user impact.
- Fix direction: "BAPS Whisper transcribes English…". Confirm the Atlas directory behaviour separately.

### P-3 (major): the cinematic direction is only partly built: no depth planes and no destination

- Location: `WelcomeJourneyView.swift:199-202` (`WelcomeWorkspace` with `scaleEffect` and `position`), `:227-235` (`cameraTarget`: chapter 0 scale 0.72, chapter 2 scale 1.52, chapter 3 scale 1.47, chapters 1, 4 identity), `:204-208` (morphing mark).
- What is wrong: the approved direction asked for foreground and background at different depths, one persistent object that becomes transcript, minutes and a library, and a spatial ending (the library becomes the app). The build has one card that scales and moves inside a canvas, a separate mark, and a legacy card that fades. Chapter 5 resets the camera to identity (`default` case), so the ending is a static card, not a destination. The workspace is also a card inside a canvas (nested frames, `clipShape` plus shadow, `:348-350`).
- Fix direction: give the background and foreground separate depth layers with different parallax factors. Make the final chapter move the workspace into the app context (the real Home or Meetings layout) rather than resetting it.

### P-4 (minor): some in-canvas text is too small to read, especially at the scaled chapters

- Location: `WelcomeJourneyView.swift:429` ("Rename" at 7pt), `:397` and `:404` (8pt), `:363` ("LOCAL LIBRARY" 8pt), `:412` and `:425` (8pt), `:217` (9pt "ILLUSTRATIVE SAMPLE").
- Evidence: the workspace is scaled by the camera before display. At chapter 0 the scale is 0.72, so 8pt renders about 6pt. At chapter 2 it is 1.52, so 7pt "Rename" renders about 10.6pt. The text is still illegible at the first chapter.
- Fix direction: set in-canvas text to 10pt minimum before scaling, or scale geometry without scaling type.

### P-5 (minor): the canvas is one combined accessibility element

- Location: `WelcomeJourneyView.swift:223-224` (`.accessibilityElement(children: .combine)` with one fixed label).
- What is wrong: transcript rows, minutes and the library are not individually reachable. The per-chapter content that matters for the story is only in the copy column, and the canvas label does not change per chapter.
- Fix direction: give the canvas a label that changes with the chapter, or hide the canvas from VoiceOver and rely on the copy.

### P-6 (minor): closing the window or pressing Escape marks the journey as seen for good

- Location: `Sources/Wffl/Views/ContentView.swift:18` (`.onDisappear { welcome.mainWindowDisappeared(windowID) }`), `WelcomeJourney.swift:142-146` (calls `dismiss()` if this window was presenting), `:166-171` (`dismiss()` sets `acknowledged = true` and persists it). Escape: `WelcomeJourneyView.swift:61`. The sheet's `set` closure also dismisses: `ContentView.swift:57`.
- What is wrong: closing the main window mid-tour, or pressing Escape on chapter 1, permanently consumes the campaign. The user never sees chapters 2 to 5. Recovery is only through the Help menu or Settings. The spec says acknowledgment should apply to a journey actually presented. A journey that was cut short arguably was not seen.
- UNVERIFIED: whether `onDisappear` fires on app quit. If it does not, the same loss happens only on window close.
- Fix direction: on window close or Escape, keep the campaign pending and offer "Continue the tour" next launch. Acknowledge only on "Explore Wffl" or the final Continue.

### P-7 (minor): a manual "What's New" request while busy turns into a sidebar card with no feedback

- Location: `WelcomeJourney.swift:71-75` (`requestReplay(busy:)` sets `invitation` and returns), `:157-162` (coordinator wrapper). Entry points: Help menu `WfflApp.swift:12-18`; Settings `SettingsPane.swift:88`, `SettingsView.swift:723-724`. Sidebar card `ContentView.swift:179-189`.
- What is wrong: a user who chooses "What's New in Wffl…" while work is running gets no journey and no message, only a card in the sidebar that says "A quieter Wffl is here". The menu action looks like it did nothing.
- Fix direction: say so in the menu flow ("Wffl is busy. What's New will open when it is idle."), or present when the work finishes.

### P-8 (minor): design doc and code disagree on the sheet size

- Location: `docs/design-review/native-implementation-checks.md:14` ("explicit 760×500 layout in the 900×560 host"). Code: `Sources/Wffl/Views/ContentView.swift:9-11` sizes the sheet to `min(980, max(520, width-16))` by `min(650, max(460, height-16))`, which is 884×544 at 900×560.
- Fix direction: correct the doc, or set the sheet to the size the doc says (and check the copy still fits).

### P-9 (nit): duplicated chapter counter

- Location: `WelcomeJourneyView.swift:88` (header) and `:141` (footer), both "%02d / 05".
- Fix direction: keep one.

### P-10 (minor, UNVERIFIED): a synchronous database read at launch

- Location: `WelcomeJourney.swift:113` (`Database.shared.allMeetings()` inside `captureReturningEvidence`), called from `WfflApp.swift:35` during `App.init`, before the first window.
- What is wrong: a full meetings query runs on the main thread before the first window draws. The cost on a large library is not measured.
- Fix direction: use a count query, or defer the history check to after the first window appears.

### Welcome: UNVERIFIED (needs a native foreground launch)

- The first-active automatic presentation. `docs/design-review/native-implementation-checks.md:18` says the same: a manual foreground launch is still required.
- Reduced-motion end states and the transcript rename beat in chapter 3, at 900x560 and in dark mode.
- VoiceOver and keyboard traversal through the five chapters.

---

## Existing reviews: verified or superseded

- `website-ui-review.md`: its required fixes are present in the shipping file (BAPS setup copy at line 395, privacy pill labels at lines 377-380, setup opacity). It missed W-1 through W-5, W-6 and W-12 to W-14. Its "no console errors" holds for the primary URL.
- `app-ui-review.md`: its six requirements are mostly implemented in code (font packaging, adaptive appearance, privacy wording, pause and mute states, menu shortcuts, 900x560 composition, dashboard). It is stale on the state of the source (A-12), and it missed A-1, A-2, A-3 and A-4.
- `native-implementation-checks.md`: the welcome visual approvals were given from screenshots in `/tmp`, which no longer exist here. Those approvals are not re-verified (UNVERIFIED). Its sheet-size claim is wrong (P-8).
- `welcome-journey-design.md`: the spec items are implemented in code except the depth planes and destination (P-3) and the window-close acknowledgment (P-6).

---

## Verdict per surface

1. **Website: not approved.** The copy is largely honest and most of the earlier fixes landed, and reduced motion and contrast are solid. But the owner's core goal is not met: this is roughly a third of the way to an entered-space journey (W-1). The stage misrepresents the clean-up feature (W-4) and the chapter numbering is inconsistent (W-5). The notarization claim is unverified (W-7). Next round: W-1, W-2, W-3, W-4, W-5, W-6, W-7.
2. **App redesign: not ready.** The build and the 8 policy tests pass, and the token values, font packaging and appearance pin are correct. But typography bypasses the tokens (A-1), the Settings scene still shows the old Form (A-2), the recording label and secondary text fail contrast (A-3), and accessibility coverage is thin (A-4). Native composition and dark mode are unverified.
3. **App icon: blocker.** It is the old design and the wrong mark, and it is oversized for the grid. Replace it per the recommendation (I-1, I-2, I-3).
4. **Welcome-back popup: not approved for the story.** The state logic and its tests are sound and the first-install exclusion holds. But the "before" is fabricated (P-1), the copy names "Atlas" (P-2), and the cinematic direction (depth, destination) is only partly built (P-3). The window-close loss (P-6) needs a decision.

## Top 10 things the owner would notice first

1. The app icon is still the old cream tile with a single-stroke W (I-1). It does not match the website or the app's own mark.
2. The website journey is a framed card that changes state, not a space you move through (W-1).
3. A hard-edged rectangular tint sits behind the journey stage (W-2).
4. The welcome's "familiar Wffl" is not the real old app. The sidebar labels are invented (P-1).
5. The welcome copy says "Atlas's BAPS Whisper" (P-2).
6. The clean-up chapter shows a summary, not the clean-up the copy describes (W-4).
7. Chapter numbers disagree between the stage and the copy (W-5).
8. Cmd+, opens the old Form-based Settings, not the sidebar Settings (A-2).
9. Two typefaces on the same screens: SF in the sidebar nav, Hanken elsewhere (A-1).
10. The RECORDING label is ember text at 2.8:1 contrast on the light background (A-3).

## Paths

- This report: `/Users/purvarajsinhgohil/Developer/Wffl/docs/design-review/qa-round-4.md`
- Icon extraction and measurements: `/private/tmp/claude-501/-Users-purvarajsinhgohil-Developer-Wffl/41cd86ff-24f1-4786-b517-05a2ce4a9623/scratchpad/icon/`
- Build and test logs: `/private/tmp/claude-501/-Users-purvarajsinhgohil-Developer-Wffl/41cd86ff-24f1-4786-b517-05a2ce4a9623/scratchpad/swift-build.log` and `.../scratchpad/swift-test.log`
