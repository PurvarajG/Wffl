# Developer A report: immersive website

Status: implementation complete; browser verification BLOCKED. No commit was made. Only `website/` was edited, and `website/apple-touch-icon.png` was never written by Developer A. `website/vercel.json` and both self-hosted font files are unchanged.

## What was built

Replaced `website/index.html` with the approved immersive reference: three pinned journeys, six scenes, two ordinary-scroll interludes, the original timeline/easings/layout/copy, rail, nav, progress bar, canvas, and `window.__setU`. All six scene render functions remain byte-for-byte identical to the reference.

Removed the mockup bar, Mobile-390 iframe, their CSS, query overrides, buttons and event handlers. No Pause-motion control was added. Kept OS light/dark and reduced-motion detection.

Added the skip link and focusable main, production title/description, `og:title`, `og:description`, `og:type`, `og:site_name`, `twitter:card=summary`, font preloads, the apple-touch-icon link, and an SVG data favicon with the option-A near-black tile and eight off-white capsule bars at the exact requested relative heights. Raised the miniature Recording label from 10px to 11px and hid the decorative check SVG from accessibility. There is one h1, first in heading order, no aria-live, no unsupported visible arrow/search glyphs, and no signed/notarized claim.

Added `qa/check.py`, a read-only static self-check, and `qa/source-probes.json`, the recorded timeline-arithmetic evidence. These are developer verification artifacts, not runtime dependencies.

## Executed verification

`python3 website/qa/check.py`: PASS. Validates approved visible copy, no leftover mockup controls/drivers, JavaScript syntax through `node --check`, literal ID lookups, heading order, section/decorative labels, skip link, metadata, favicon geometry, text declarations >=11px, and exact renderer/font parity. The font hashes are:

- Hanken Grotesk: `e9201eddf1d41d0b62253295d869ce3cf65768f7102b797f02c7f8c876b4a9d5`
- Fragment Mono: `44c4e39bff5e76652a24a872cbebabccbcfb20f62c4633b27c1f2745cba86b56`

`git diff --check -- website`: PASS. `git diff -- website/vercel.json`: empty.

Developer B's touch-icon file is present and its PNG header reports 180x180; only the header was read. Its visual appearance is not certified here.

## Browser blocker and required matrix

Attempted the exact requested commands:

- `cd website && python3 -m http.server 4176`
- `cd design-handoff && python3 -m http.server 4175`

Both exited 1 with `PermissionError: [Errno 1] Operation not permitted` during socket binding. The installed gstack browse binary also exited 1:

> Cannot bind localhost ports after 5 attempts in range 10000-49151. Last error: 23291 (EPERM: Failed to listen at 127.0.0.1).

`command -v aside` returned no executable. Approval policy is `never`, so no permission escalation was attempted. The browser workflow could not start. No screenshots, side-by-side visual comparison, interaction tests, browser-console results, or pixel evidence were obtained. Zero console errors is **UNVERIFIED**, not a pass.

All eight required configurations remain unexecuted: 1440x900 and 390x844, each in light/dark, each with normal/reduced motion. The source checks below are explicitly not a replacement for that browser matrix.

## SPEC 1.11: every acceptance test

Status convention: **FAIL / UNVERIFIED** means the required browser acceptance was not executed, not a demonstrated visual defect. **FAIL / SOURCE** identifies a concrete inherited contradiction established by source/arithmetic; browser confirmation is still outstanding. No browser acceptance is marked PASS.

| Test | Pass/fail | Evidence |
| --- | --- | --- |
| 1. Hero at 0; centred/larger mark at 1.4; dive at 2.7; tilted dot plane at 3.6 | FAIL / SOURCE + UNVERIFIED | `r1`, lines 546-556: at 1.4, `seg(1.4,.6,1.8)=0.75`; the mark has travelled only 75% to centre. Text opacity is 0 and scale is 1.375. At 2.7 the computed scale is about 15x. No rendering evidence for the remaining visual assertions. |
| 2. Eight words at 5.0; live caption until 5.3, then saved | FAIL / SOURCE + UNVERIFIED | `r2`, lines 557-571; source probe: at 5.0, playhead=.8742553741 and final-word opacity=1. At 5.29, playhead=.9998540070 and `ph>=.999` already makes the caption Saved, slightly before the specified 5.3 boundary. Browser text visibility unverified. |
| 3. Split labels at 7.3; Priya/caret at 8.1; group B/recognition at 8.7 | FAIL / SOURCE + UNVERIFIED | `r3` implements the requested split/typing. However `RANGES` turns S4 on at 8.7. S4 has an opaque ground and scene opacity=1 while its copy, transcript and minutes opacities are all 0. It covers group B at the requested 8.7 checkpoint. Source probes record all five values. |
| 4. Cleaned transcript at 10.9, heading/timecodes, no fillers | FAIL / UNVERIFIED | `r4`, lines 608-626: collapse finishes at 10.8; heading at 10.8; Cleaned thumb at 10.5. Exact heading/timecode copy and filler markup are present. Rendering and selected-state appearance unverified. |
| 5. Four chips/pills/cut wires at 14.4; completed scene 6 at 16.2 | FAIL / UNVERIFIED | `r5`/`r6`, lines 627-648, retain all four chips and wire/tick functions and the closing sequence. Mobile intentionally hides wires. No browser geometry/completion evidence. |
| 6. Real scroll to J2+2.2vh, caption/convergence after 1.5s; interlude reveal/query | FAIL / UNVERIFIED | `frame`, `chrome`, `onScroll` retain .09 smoothing, .0004 snap, block-based captions, reveal and typing functions. No real scrolling or timing run. |
| 7. 390x844 copy never covered; no horizontal scrolling | FAIL / UNVERIFIED | Original <=760px rules retained. No browser measurements; source checks cannot certify collision or overflow. |
| 8. Dark theme inversion and correct nav flips | FAIL / UNVERIFIED | Dark media tokens, `.inv`, and block-at-y=34 nav logic retained. Mockup theme controls removed. No browser media-emulation run. |
| 9. Reduced motion: ~six stacked scenes, no motion, all end states | FAIL / SOURCE + UNVERIFIED | `.rm` stacks scenes, but also retains both interludes. `applyRM` renders S3 at 8.2, where the later-meeting recognition tag opacity is 0; the 300px group height cannot contain the desktop third label at roughly y=419px. The inherited bar/button/rail transition rules are not disabled by `.rm`. Page height, clipping, layout and actual animation remain browser-unverified. |
| 10. Ember restricted to permitted live indicators and top progress | FAIL / UNVERIFIED | Source uses ember on the progress bar, lamps, live canvas dots, and the expressly approved S1/S6 glow gradients. No pixel inspection. The glow allowance and this test's literal wording conflict; see pushback. |

## R2.5: every acceptance addition

| Test | Pass/fail | Evidence |
| --- | --- | --- |
| (a) Ordinary-scroll I1/I2 between pinned journeys; never an empty screen | FAIL / SOURCE + UNVERIFIED | I1 and I2 are sibling sections outside sticky stages and use normal-flow padding. But the opaque S4 activation at 8.7 covers Voices before any Minutes content is visible, producing an empty content stage. No continuous-scroll browser sweep. |
| (b) <=~25% unused stage; lanes/docs/diagram each >=55% width at 1440x900 | FAIL / SOURCE + UNVERIFIED | Layout arithmetic: lanes=60%; `.docs {left:44%; right:48px}` gives 758.4px/1440=52.6667%; diagram=1240px/1440=86.1111%. The docs container misses 55%; transformed card bounds and perceived empty-area coverage need browser measurement. |
| (c) No more than two overlapping text blocks; no nav collisions | FAIL / UNVERIFIED | Original visibility windows and 55%-ground/12px-blur nav retained. No frame sweep or collision measurements. Reduced-motion copy/lanes retain some positional properties from the animated layout and need particular scrutiny. |

## QA additions

| Item | Result | Evidence |
| --- | --- | --- |
| W-7 | PASS, static | No signed/notarized claim in visible copy. |
| W-11 | PASS, static | None of the four unsupported glyphs in visible text. |
| W-13 / 1.8 | PASS, declarations | The sole 10px Recording label is now 11px; static font declarations meet the floor. Effective transformed sizes unverified. |
| W-14 | PASS, except deliberately deferred URL fields | Social fields and touch-icon link added. No canonical URL was present in either allowed source. `canonical`/`og:url` intentionally omitted; no og:image. |
| Favicon | PASS, source geometry | SVG data URI, gradient near-black tile, eight off-white 44-unit capsule bars, exact requested heights. Browser appearance unverified. |
| W-8 | PASS, not applicable | The mockup has no production Pause-motion control; none added. |
| W-17 / 1.10 | PASS, static | No aria-live; one h1 first among headings; labelled sections, decorative SVG/canvas hidden, existing focus/keyboard rail retained. Keyboard/browser behavior unverified. |
| Skip link | PASS, markup | First body link targets `main#page[tabindex=-1]`; focus-visible styles present. Keyboard interaction unverified. |

## Skipped / deferred

Canonical and `og:url`: **what is the production canonical URL?** Neither the original `website/index.html` nor `website/vercel.json` provided one. No URL was guessed.

No og:image, new Pause-motion control, favicon.ico, new effects/copy, or unrelated QA redesign was added. No native app/build tests were run; those belong to Developer B. No commits, branch switches, checkout/restore/stash, or edits in Sources/Support/Tests/scripts were performed. Browser validation and the zero-console-error requirement remain blocked, not waived.

The gstack skill's global onboarding/telemetry/learning-file writes were omitted to respect the website-only edit boundary. Durable finding recorded here instead: reference renderer parity does not imply acceptance parity; the opaque S4 start at 8.7 and reduced-motion settle at 8.2 contradict the stated checkpoints.

## Pushback, kept out of the implementation

The reference has specific acceptance contradictions. The plan says the mockup source wins, so changing scene timing, the split/recognition settle, reduced-motion layout/transitions, or docs width here would violate the approved port instruction. Those should be resolved in the source of truth before claiming acceptance.

Additional SPEC/reference differences preserved literally: mobile streams use `pad+100px` rather than Part 1's `pad+82px`; mobile words are 1.4rem rather than 1.3rem; mobile fine print is .78rem (12.48px) rather than 12.5px. The S2 exit transform/dimmer also remains in the source despite R2.1 describing its removal; J1 reaches 5.5 so a small amount of that exit is reachable. Reduced-motion ~six-scenes wording predates the two interludes. SPEC 1.4 expressly permits ember in glow gradients while 1.11.10's literal whitelist omits them.

## Risks

The port is not browser-certified. Inherited source conflicts can cause a blank transition, early saved status, incomplete reduced-motion content, and a narrower document region than requested. Mobile overlap/overflow, dark canvas/nav behavior, focus, visual parity, and runtime console output still require the full browser matrix in an environment that allows localhost binding. The canonical URL remains an owner input. Developer B owns the PNG; its presence/dimensions were checked but not its artwork.
