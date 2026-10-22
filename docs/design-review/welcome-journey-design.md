# Welcome journey: one listening instrument

## Design intent

The current welcome reads as five separate slides: copy beside a small inset scene, an inset panel, and a row of chapter pills. That repeats the hierarchy of an ordinary tour and makes each illustration disposable. Replace it with one immersive stage that keeps the same waveform and the same workspace in view while the user moves through five moments.

The visual argument is made through one persistent object: Wffl’s old sage W mark draws itself into the new waveform; the waveform travels into the redesigned workspace; the same signal stretches into timecoded words; those words meet the BAPS Whisper label; the camera finally pulls back to the actual meeting workspace and local library. The user drives each move. Composition and geometry change substantially; explanatory copy stays anchored and still long enough to read.

The prototype is a design artifact for the upcoming app redesign. The existing app uses warm paper, sage, and serif display type; the redesigned app remains a mockup and must be shown as proposed until that app ships. There is no invented release date or version.

## Persistent composition

- Use one edge-reaching canvas/window, approximately 980×650 points on desktop, adapting down to a 900×560 Mac window, with no card inside a card. The canvas is the app stage itself, with one soft tonal ground and a single grain treatment. The story is not framed as five stacked mini-scenes.
- Keep a real 8-bar Wffl waveform visible in every chapter. It begins large as the old W mark, moves into the new app sidebar, enlarges into the recording/transcript signal, travels alongside BAPS Whisper, then settles as the app’s sidebar mark in the final workspace.
- Keep one meeting workspace present from chapter 2 onward. In chapter 2, the whole window resolves from the old warm shell into the monochrome shell. In chapter 3, the camera pushes into the transcript region and places the waveform in the margin above the rows, never over words. In chapter 4, it tracks from the transcript into an open lower-right workspace margin for the engine label; the summary column yields focus while the engine is in view. In chapter 5, it pulls back to show the same meeting, transcript, summary and local library within the redesigned shell.
- Place chapter title and paragraph in a persistent 30–36% copy column anchored to the left. Keep them large and readable (Hanken Grotesk headline 40–58pt; body 15–17pt, measure around 34ch). Keep the concise English-only qualifier reachable in the scrollable copy column at 900×560. The remaining area carries the workspace and the moving waveform. Do not animate complete paragraphs or hide copy on a timer.
- Use Hanken Grotesk for titles/body and Fragment Mono only for chapter count, timecodes and status labels. Keep the cool monochrome palette. Sage appears only in the opening legacy state; ember indicates live audio. Do not add floating particles, confetti, orbiting decorations or extra glows.

## Five user-driven moments and exact copy

Chapter copy is shown immediately on selection and remains unchanged until the user selects another chapter. The progress rail is a quiet five-part hairline with the current number (01/05), not five prominent pill buttons. “Continue” advances one chapter. Selecting a progress mark jumps directly to that chapter. “Back” appears after the first chapter.

1. **Space to listen.**
   - Copy: “A calmer monochrome workspace. The same recordings, notes and preferences, with more room for the words that matter.”
   - Stage: begin close on the old sage W stroke, set against warm paper. On the first forward action, the stroke traces once, then its same five bends lengthen and settle into the new eight-ellipse waveform as the camera eases back to reveal the desktop.
   - Motif: paper changes from warm cream to cool off-white while the mark holds its position. This is the only brand identity transition.
2. **More room for your work.**
   - Copy: “Home, Dashboard, Meetings, Audio Files and Settings now share one consistent workspace. Everything stays where you left it.”
   - Stage: the waveform glides into the top of the sidebar and becomes the app mark. The camera tracks right as the old warm shell moves out of frame and the new sidebar and meeting canvas resolve in the same window. Existing sample bars become the transcript and summary surfaces; no fake meeting totals or people appear.
3. **Voice. Words. Decisions.**
   - Copy: “Live voices appear as Me and Them. After recording, known voices keep their names; rename new speakers once.”
   - Stage: push in toward one timecoded row. The waveform widens into a live signal line above two sample transcript rows labeled “Me” and “Them”. As the user continues, the live row travels down and settles into a post-recording row labeled “Speaker 1” with a visible Rename action. A second beat reveals the minutes/decisions/actions structure within that same document. Mark the transcript sample as illustrative.
4. **Meet BAPS Whisper.**
   - Copy: “Atlas’s BAPS Whisper transcribes English, including Gujarati and Sanskrit vocabulary in Latin letters. Optional model, about 1.6 GB; download in Settings.”
   - Qualification: “For other languages or translation, choose Whisper.”
   - Stage: track laterally along the same transcript row until the words and the waveform arrive beside a plain model label: “BAPS Whisper · ≈1.6 GB · Optional model”. The waveform settles immediately left of the label, below the transcript rows. The summary and post-recording transcript rows recede during this close view, leaving the signal and label in a reserved lower band; the recording title, transcript heading and first row remain visible. Use a hollow download symbol only; no progress bar, download state or install claim.
5. **Here on your Mac.**
   - Copy: “Audio, transcription and your library stay local. Model downloads use the network; remote summaries are optional.”
   - Stage: pull back from the same transcript into the full redesigned meeting window. The persistent waveform returns to its original sidebar location; the meeting summary, transcript and searchable library are visible in one composed working surface. End over the actual workspace context, not a final thank-you card. The CTA reads **Explore Wffl** and dismisses the journey.

There is no playback duration, forced wait, or auto-advancing copy. The BAPS model is about 1.6 GB and optional to download from Settings. BAPS Whisper transcribes English; Gujarati/Sanskrit vocabulary is written in Latin letters. For other languages or translation, Whisper must be selected in Settings. Nothing in the journey downloads a model, selects an engine, records audio, or creates a summary.

## Motion choreography

Every chapter transition is one deliberate camera move initiated by Continue, Back, a progress-rail action or a keyboard command. Use a 700–1000 ms spring-like ease-out with slight depth separation; the user should see a distance change or a clear object relocation, not a sequence of unrelated opacity fades.

- Chapter 1 shows the legacy W mark. On the user’s first forward action, the mark traces and reshapes into the eight-bar waveform as the camera pulls back to reveal the desktop.
- Chapter 2 tracks the waveform into the sidebar and resolves the workspace around it.
- Chapter 3 pushes into the document; the signal extends into the transcript. Speaker rows enter from that same point and settle vertically; the minutes section unrolls below them.
- Chapter 4 tracks across the shared transcript/engine line. The model name arrives on the end of the moving signal, then holds still.
- Chapter 5 pulls back to the window overview and lands on the library. The waveform returns to the same sidebar coordinates established in chapter 2.

Only the visual stage moves. Copy and controls remain anchored, with no blur transition. A short opacity change is acceptable when revealing words, but it cannot carry the chapter transition by itself. No loop or idle motion.

## Controls and access

- Keep only the close control, “Skip intro”, Back/Continue, and the low-profile progress line. Keyboard: Left/Right moves one chapter when focus is in the journey; Return activates the focused control; Escape closes. Tab order follows close, skip, progress, back, continue. VoiceOver announces the chapter count/title and progress.
- Keep focus visible. On dismissal return focus to the window that opened the journey. On chapter change, leave focus on the activating control and announce the new chapter title/body once through an accessibility live region.
- Reduced Motion presents the completed composition for each selected chapter immediately: final logo, resolved window, the completed post-recording transcript row, rename hint and minutes; the accompanying copy explains the live Me/Them labels, BAPS label and qualifier, then full workspace. Text and controls stay identical. No movement, fade, blur, scale or spatial change is required for understanding.
- On compact windows, keep controls and progress anchored at the bottom; allow the stage/copy region above to scroll as a single reading surface. At a compact 900×560 Mac window, prioritize the title, concise body, qualifier and fixed navigation; the workspace illustration may crop, and the copy column scrolls without moving the controls.

## Native integration notes

The app now has `WelcomeJourneyView.swift`, `WelcomeJourneyCoordinator`, and the launch/defer policy in `Support/WelcomeJourney.swift`. Preserve that lifecycle, acknowledgment, first-install evidence, busy-state deferral, replay path and safe-dismiss behavior. The design change is within the view’s visual architecture, not a new campaign or presentation rule.

Specifically, keep the `quiet-instrument-1` campaign key; keep first-install evidence capture before preference migration; keep one-time acknowledgment only after the sheet is presented and then dismissed, skipped or completed; keep initial active+idle launch presentation and the nonmodal invitation when launch is busy; keep replay deferred during active work. Preserve the current busy signals for recorder preparation/recording/stopping, post-recording transcription, import/re-transcription, cleanup and summaries. The cinematic canvas must not touch model state, recording, engine selection, or audio.

Replace the current `copy` + `stage` HStack/`ViewThatFits`, nested rounded stage, chapter pill row and `.id(chapter)` replacement transition with one `WelcomeJourneyCanvas` shared by all five steps. Keep copy and controls outside that canvas and anchored. Represent each chapter as target geometry/state for the persistent objects: mark transform, workspace camera scale/offset, active document region, transcript phase, and engine label position. Use SwiftUI `matchedGeometryEffect` or an equivalent stable view identity for the waveform, transcript row and app window. Animate those targets inside a single `withAnimation` for user-driven movement. Do not key the main stage by chapter, because replacing it destroys the object continuity.

Use the existing `MorphingWMark` as the first identity transformation and carry the same mark view into the app sidebar state. Keep the sample transcript and BAPS model data exactly truthful as described above. Mark the meeting content as sample in the stage; never imply that the displayed sample was created or imported for this user. Keep `accessibilityReduceMotion`; render target geometry immediately and show the useful final state for each chapter. Preserve the current `onDismiss` contract so closing/skip still acknowledges only once the sheet has actually appeared. Continue using the current deferred campaign policy in `WelcomeJourneyCoordinator`.

Likely implementation targets are `Sources/Wffl/Views/WelcomeJourneyView.swift` and a small extracted stage subview in the same file. `WfflApp.swift`, `ContentView.swift`, `Support/WelcomeJourney.swift`, install detection and recording/import lifecycle do not need to change for the cinematic redesign.

## Acceptance criteria

1. The first frame is one continuous, edge-reaching stage with a large copy block and a recognizable Wffl mark; it does not look like five cards inside a dialog.
2. The same waveform remains visible through all five chapters and is seen in multiple locations as it moves between mark, sidebar, transcript and final workspace.
3. Each user-driven chapter change visibly changes spatial composition via a decisive camera move or object travel that lasts about 700–1000 ms. Replacing the illustration with a fade is insufficient.
4. Copy remains anchored, readable and user-controlled; no chapter advances without input.
5. The final scene resolves into the redesigned app workspace, with the waveform back in the sidebar and meeting content visible.
6. Chapter 3 distinguishes live Me/Them from post-recording Speaker 1/2; unknown voices have Rename affordance. No unsupported named-speaker claim appears.
7. BAPS Whisper is described as English-only, with Gujarati/Sanskrit vocabulary in Latin letters; size is approximate and download remains optional. Other language/translation qualification is visible.
8. Skip, Back, close, progress navigation, Escape and final Explore Wffl remain available. Motion does not gate information or action.
9. Reduced Motion shows complete useful states immediately, including the full final workspace.
10. No particles, confetti, excess glows, fake download progress, recording, download, engine selection or other side effects are introduced.
11. Existing install eligibility, once-per-campaign acknowledgment, active-work deferral and replay behavior remain unchanged.
