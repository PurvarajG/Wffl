# Opening redesign animation — proposed storyboard

Date: 2026-10-23
Status: direction approved; native motion studies must be reviewed individually before app integration.

## Outcome

Replace the current automatic 26-second old-to-new camera morph with one continuous opening sequence, followed by a short user-controlled website-style tour, ending in the real native Home. The existing website and final app design are the visual references and remain unchanged.

“One animation video” is interpreted as an uninterrupted cinematic experience rendered in the app. A responsive, code-rendered sequence permits window-specific composition and a seamless transition into interactive scrolling. A prerecorded video is an alternative only if a literal video file is required; it would require separate aspect-ratio treatment and an interactive continuation.

## Storyboard

Revision 12 timing below is a proposed starting point, not an approved duration. The owner's latest feedback calls for much smaller, quieter type using the app's own fonts, superseding the earlier screen-filling serif typography request. The design-taste pass preserves the revised text continuity.

1. **Old Home, 0–3.35 seconds.** Display the actual legacy SwiftUI view at the current window size. Hold for one second, then fade to black over 2.35 seconds. Do not enlarge a screenshot.
2. **Type and correct, 3.65–8.95 seconds.** Use restrained white Hanken Grotesk Light text, matching the app UI, capped at 88pt with generous black space. Type `boring...`, hold, visibly backspace it, then type `I agree!!!`. Both phrases share a fixed writing origin and baseline, with a quiet caret and natural pauses around punctuation. Hold the final phrase, then fade it away as the old design returns. The old Home returns beneath the final response over 2.2 seconds (8.35–10.55). Hold the fully visible, unobstructed old Home for 0.75 seconds (10.55–11.30) before the first TNT is placed. The owner explicitly confirmed the slower four-second TNT placement should be kept. This restoration and placement are the only changes requested after the owner accepted the text treatment. The exact case and punctuation follow the owner's latest request.
3. **Demolition, 11.30–19.75 seconds.** Minecraft-style red TNT blocks fill every part of the old interface, including the sidebar and screen edges. Place blocks at fixed positions on the restored old design across the entire window over roughly four seconds, retaining the accepted slower speed. Do not fly or drop them onto an empty black stage. Remove each old-interface region at the instant its block detonates, revealing black while its matching fragments travel away. At 16.05 seconds the middle block sets off its neighbours, producing a centre-out domino detonation over roughly two seconds. Each local blast carries old-interface fragments and chunky voxel debris. Resolve to black. This is the one deliberately playful beat.
4. **Introduction, 19.30–22.65 seconds.** After the debris clears, resume the same typing language: the caret arrives gently, then `Introducing....` types onto black with deliberate punctuation pauses. The completed line is centred in the same app font, capped at 72pt. No simultaneous caption card. Use deliberate keynote pacing and a withheld reveal.
5. **Teaser, after the introduction.** Brief light sweeps catch the top-left edge and two other small regions of the new design. Mask the rest to black. Do not expose a readable full layout yet. Timing will be reviewed in the next motion study.
6. **Reveal, following the teaser.** Reveal the new Wffl visual identity with the website's typography, waveform, easing, and controlled motion. Resolve into the first tour composition, then hold. Show a quiet scroll cue only after automatic playback completes.
7. **User-led tour, no timer.** Scroll advances a compact sequence derived from the website's existing narrative and animations: capture/transcription, voices/summary, and privacy/setup. Reuse existing wording and its qualifications. Compose text and graphics for the actual app content width and height; do not shrink a desktop website into a smaller rectangle. Scroll can reverse within the tour; it never rewinds the opening film.
8. **Radial handoff.** At the end of the tour, further deliberate forward scroll expands a soft circular opening through the tour layer to expose the actual Home beneath. A Gaussian-style blur ripple is the recommended motion study; the owner also permits small squares folding into one another in a Tetris-like treatment. Prototype and approve the chosen effect before integration. Do not change Home's scale, position, window size, or layout. Completion is one-way and removes the tour overlay after the mask clears the entire window. The first exposed Home frame and subsequent live frames use the same underlying view.

## Architecture and scope

- Explicit phases: automatic opening, interactive tour, handoff, complete. The automatic timer stops at the tour boundary; elapsed time cannot dismiss the tour.
- Existing implementation entry points: `WelcomeJourneyView.swift`, `Welcome/FilmTimeline.swift`, `Welcome/FilmStage.swift`, and the overlay in `ContentView.swift`. Reuse usable legacy rendering and the coordinator's replay, Skip, interruption, and acknowledgement rules.
- Reuse website motion from local `website/index.html`; no remote page loading is required. Choose native SwiftUI/Canvas rendering for the bounded tour, unless a short feasibility check establishes that packaging existing HTML gives materially better fidelity at lower complexity.
- The handoff targets the actual Home, including real readiness and library state. Establish Home underneath before starting the radial transition; any navigation change is covered by the opaque tour. A sample Home screenshot cannot stand in for the final handoff.
- Keep controls above the film; Skip remains available. Escape interrupts under the existing campaign policy. Restore usable keyboard focus after completion. Reduced Motion uses user-paced stills and a direct Home transition, with no TNT fragments or light sweeps. Provide keyboard progression as well as scrolling for the tour.
- Bound particle work, preload necessary assets, derive animation values deterministically, and avoid rebuilding the full application every frame. Window resizing recomposes the active scene without restarting the opening or discarding tour progress. Release temporary rendering resources after dismissal.
- Preserve all existing uncommitted changes. Scope implementation to opening-related code and appropriate tests; do not redesign unrelated app or website screens.

## Credit-conscious execution

The orchestrator first builds reusable native motion studies for demolition, the edge-light teaser, and the radial handoff. Show the actual moving studies to the owner, and obtain approval of each before stitching the app sequence. Then give one GPT-6 Luna High worker the approved components, complete integration task, relevant file list, state contract, and acceptance criteria in one dispatch. Let that worker own the final integration because the phase boundaries are tightly coupled. Avoid passing the entire conversation to the worker. Return changed files, verification output, representative frame captures, and remaining issues in one report. The orchestrator performs the final visual and technical review. No model pricing or credit total is assumed here.

## Acceptance evidence

- Capture the old Home, typed word, TNT detonation, introducing text, edge teaser, full reveal, each tour chapter, and several radial-mask positions.
- Review an actual playback recording: still images alone cannot establish pacing, smoothness, or the absence of a handoff jump.
- Check native windows at 900×560 and 1100×700, both appearances, and resizing mid-sequence. Text remains readable and controls reachable.
- Verify the automatic opening holds at the tour, reverse/forward scroll works within its bounds, and momentum does not accidentally skip the tour or finish immediately.
- Verify the radial transition exposes the real Home in fixed coordinates, without an intermediate blank frame or a sample-to-live content swap.
- Verify Skip, Escape, replay, acknowledgement, Reduced Motion, keyboard progression, and focus restoration. Run the relevant Swift build and welcome/film tests, updating obsolete morph-specific expectations to test the new requirements.

## Review points

The main interpretation to confirm is that “video” describes the continuous playback experience rather than requiring an encoded movie file. The brief also proposes briefly resurfacing the legacy Home behind the TNT to make the demolition legible, and a compact three-chapter website tour rather than embedding the entire marketing page.
