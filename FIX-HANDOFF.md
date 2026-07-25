# Wffl — Precise Fix List (LLM handoff)

Audited 2026-07-24 against real meeting data. Each item is self-contained: symptom,
root cause, exact location, fix spec, acceptance check. You do NOT need to read the
whole codebase — only the files named per item.

**Project:** Swift/SwiftUI macOS app, SwiftPM, repo root `MeetilyMac/`, sources in
`Sources/Wffl/`. Build: `swift build`; bundle: `scripts/bundle.sh`. Tests:
`swift test` (target `Tests/WfflTests/`).

**Hard evidence backing this list** (from `~/Library/Application Support/Wffl/`):
meeting `83D1AEDB…` (Jul 24, 11:56, 1827 s): mic channel (ch0) of the stereo WAV is
RMS 0 for the entire recording; `channels.json` has 0/8421 intervals `mic:true`;
all 160 transcript segments are `source='system'`; speaker assignment: 119 segments
→ one global "Speaker 6", 40 segments → NULL speaker, 1 → "Speaker 7". The two other
Jul 24 meetings also have 0 mic-active intervals.

---

## P0-1 · Build signing silently degrades to ad-hoc → macOS revokes mic permission → mic records pure silence

- **File:** `scripts/bundle.sh:26-33`
- **Root cause:** Script signs with identity "Wffl Dev" but falls back to
  `codesign -s -` (ad-hoc) with only a stderr warning when the identity is missing.
  This machine has **zero** codesigning identities (`security find-identity -v -p
  codesigning` → "0 valid identities found"), so every rebuild gets a new random
  cdhash. macOS TCC binds the microphone grant to the code signature; after a rebuild
  the grant no longer matches and CoreAudio delivers all-zero buffers with **no
  error** — the engine runs normally. The 11:52 rebuild immediately preceded the
  first dead-mic meeting at 11:53.
- **Fix:** Make bundle.sh `exit 1` with a clear message ("create a self-signed
  'Wffl Dev' code-signing certificate in Keychain Access first") instead of falling
  back to ad-hoc. Do not auto-create the cert.
- **Accept:** Running bundle.sh without the cert aborts; with the cert,
  `codesign -dv dist/Wffl.app` shows Authority=Wffl Dev, not `Signature=adhoc`.

## P0-2 · Silence watchdog is structurally blind to a dead mic

- **File:** `Sources/Wffl/Audio/RecorderController.swift:260-271` (`checkSilence`)
- **Root cause:** `if micRMS > silenceThreshold || sysRMS > silenceThreshold {
  silentSeconds = 0 }` — one aggregate counter. Any remote-participant audio keeps
  resetting it, so a dead mic during a real meeting never triggers `audioWarning`.
  Proven: 30 min of RMS-0 mic with zero warnings.
- **Fix:** Split into independent `micSilentSeconds` and `sysSilentSeconds`. After
  ~60 s of mic-only silence set `audioWarning = "Your microphone has produced no
  audio for a minute — check System Settings → Privacy & Security → Microphone."`
  System-channel analog optional (longer window, ~5 min, since silence there is
  normal). Extract the decision logic as a pure `static func` (inputs: per-channel
  RMS, accumulated seconds, threshold → optional warning) so it's unit-testable,
  and add a test in `Tests/WfflTests/` (see existing style in
  `Tests/WfflTests/MeetingReadinessTests.swift`).
- **Accept:** Unit test: mic RMS 0 + sys RMS high for >60 ticks ⇒ warning fires;
  both channels active ⇒ never fires.

## P0-3 · MicrophoneCapture swallows every failure; no error path exists

- **File:** `Sources/Wffl/Audio/MicrophoneCapture.swift` (150 lines, read all)
  - `:53-58` — `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice …)`
    return OSStatus is discarded: a failed pin to `Prefs.micDeviceID` silently
    records the wrong/dead device.
  - `:122-128` — `reconfigure()`'s `catch` block is intentionally empty.
  - `:147` — converter callback: `if error != nil { return nil }` drops buffers
    silently.
  - Interface (`:18-20`) exposes only `onSamples`/`onLevel` — no error callback.
- **Fix:** Add `var onError: ((String) -> Void)?`. Check the OSStatus at :55; on
  failure, fall back to the default input device and report via onError. Report
  failed reconfigure/rebind. In `Sources/Wffl/Audio/RecorderController.swift`, wire
  `mic.onError` into the existing `audioWarning` published property.
- **Accept:** Setting a bogus `Prefs.micDeviceID` produces a visible warning and
  falls back to the default mic instead of silence.

## P0-4 · Post-start "mic is delivering silence" probe (permission-revoked case)

- **Files:** `Sources/Wffl/Audio/RecorderController.swift` (start path ~`:100-160`
  where captures start and the level timer already exists)
- **Root cause:** When TCC invalidates the grant (P0-1) the API surface reports
  `.authorized` and no error — only the sample values reveal the problem.
- **Fix:** 10 s after recording starts, if every mic buffer so far has RMS exactly 0
  while `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`, set
  `audioWarning` to an actionable message ("macOS may have invalidated the mic
  permission after an app update — toggle Wffl off/on in System Settings → Privacy →
  Microphone, then restart recording."). Distinct from P0-2: this fires fast at
  start, P0-2 covers mid-meeting death.
- **Accept:** Simulate by feeding zero buffers: warning appears within ~10 s of start.

## P0-5 · Closing the window quits the app, killing in-flight cleanup/summary; stale "generating" rows spin forever

- **Files:**
  - `Sources/Wffl/WfflApp.swift:15` — `applicationShouldTerminateAfterLastWindowClosed
    → true`. Closing the window kills the detached LLM tasks mid-run.
  - `Sources/Wffl/AppState.swift:58-85` (`init`) — no reconciliation: rows left
    `status='generating'` in tables `summaries`/`cleaned_transcripts` after a
    quit/crash show an eternal spinner; the summary queue
    (`pendingSummaryMeetingIds`, `AppState.swift:42`) is memory-only and evaporates.
  - NOTE: tab switching is NOT the cause — summary/cleanup tasks are app-owned
    `Task.detached` stored in `summaryTasks`/`cleanupTasks`
    (`AppState.swift:324`, `:374`) and survive navigation. Do not move them into
    views.
- **Fix:** (a) Return `false` from applicationShouldTerminateAfterLastWindowClosed
  (or block termination while `summaryTasks`/`cleanupTasks`/recording are active,
  via `applicationShouldTerminate` returning `.terminateCancel` + a toast).
  (b) In `AppState.init`, sweep both tables: any row with `status='generating'`
  and no live task ⇒ set `status='failed'`, `error='Interrupted — regenerate.'`
  (DB helpers live in `Sources/Wffl/Database/Database.swift`; status enum is
  `SummaryStatus` in `Sources/Wffl/Models/Models.swift`).
- **Accept:** Kill the app mid-summary, relaunch: the summary shows a failed state
  with a Regenerate button, not a spinner. Closing the window while a summary runs
  does not lose the run.

## P1-6 · Speaker recognition collapses multiple speakers into one, leaves segments unlabeled

- **Files:** `Sources/Wffl/Diarization/SpeakerAttributor.swift` (86 lines) and
  `Sources/Wffl/Diarization/VoiceLibrary.swift` (55 lines) — read both fully.
- **Evidence:** In the 11:56 multi-speaker meeting, 119/160 segments → one speaker,
  40 → NULL, 1 → another.
- **Root causes (three distinct):**
  1. **Cluster collapse:** `SpeakerAttributor.swift:51-54` maps each FluidAudio
     cluster to `VoiceLibrary.matchOrCreate(...)` independently. Two different
     clusters in the SAME meeting can both match the same stored speaker (score ≥
     `Prefs.diarizationThreshold` in `VoiceLibrary.swift:23-36`), merging two real
     people. Nothing enforces uniqueness within a meeting.
  2. **Global-library drift:** `matchOrCreate` compares against every speaker ever
     stored (cross-meeting table `speakers`). A too-low threshold makes tonight's
     participants inherit old identities/embeddings; embeddings are never updated
     after creation, so early low-quality embeddings pollute all future matches.
  3. **NULL speakers:** `SpeakerAttributor.swift:61-63` — a transcript segment with
     no temporal overlap against any diarizer segment (or a `continue` on missing
     cluster) keeps speaker_id NULL and the UI shows it unattributed.
- **Fix spec:**
  1. In `attribute(...)`, make cluster→speaker assignment greedy and unique per
     meeting: compute all cluster-vs-library scores first, assign best pairs in
     descending score order, never assign one library speaker to two clusters;
     leftover clusters create new "Speaker N".
  2. For NULL segments, fall back to nearest diarizer segment by midpoint distance
     (cap, e.g., ≤ 3 s) instead of requiring positive overlap; otherwise assign the
     meeting's dominant cluster.
  3. Keep the cross-meeting matching but raise/verify `Prefs.diarizationThreshold`
     (see `Sources/Wffl/Support/Prefs.swift`) and only match against speakers with
     a user-assigned name (renamed ≠ auto "Speaker N"); auto-named ones should not
     magnetize new meetings.
- **Accept:** Re-run "Re-transcribe" on meeting `83D1AEDB…`: ≥2 distinct system-side
  speakers, 0 NULL-speaker segments.

## P1-7 · WAV writes are unordered and errors are discarded

- **File:** `Sources/Wffl/Audio/RecorderController.swift:290-303` (`writeWav`)
- **Root cause:** Called from MixBus's background queue but wraps `file.write` in
  unstructured `Task { @MainActor in try? file.write(...) }`: (a) no FIFO guarantee
  — buffers can interleave out of order under main-thread load; (b) writes stall
  when the UI stalls; (c) `try?` makes disk-full silent data loss.
- **Fix:** Own a dedicated serial DispatchQueue (or actor) for the AVAudioFile;
  write synchronously on it in call order; on throw, set `audioWarning`
  ("Recording write failed — check disk space") once.
- **Accept:** Audio bytes land in order (no main-actor hop); a thrown write surfaces
  a warning.

## P2-8 · LLM API keys in plaintext UserDefaults

- **File:** `Sources/Wffl/Support/Prefs.swift:99-101` (`llmKey.<provider>`), read at
  `:144-152`.
- **Fix:** Move to Keychain (`kSecClassGenericPassword`, service "Wffl", account =
  provider id); migrate existing values once, then delete from UserDefaults.

## P2-9 · Custom LLM endpoint allows plain HTTP with Bearer key

- **File:** `Sources/Wffl/LLM/LLMProvider.swift:302-307` (+ `Prefs.swift:89`
  free-form `customBaseURL`).
- **Fix:** Reject non-`https` base URLs unless host is localhost/127.0.0.1.

## P2-10 · `stop()` vs `fail()` teardown divergence

- **File:** `Sources/Wffl/Audio/RecorderController.swift:223-258` vs `:279-288`.
- **Root cause:** `fail()` doesn't stop mic/bus/system captures or invalidate the
  timer (safe today only because it's called pre-start). Becomes a leak once P0-3/4
  introduce mid-recording failure paths.
- **Fix:** Single `teardown()` used by both; `fail()` = teardown + error message.

---

### Constraints for the fixing LLM
- Uncommitted work already on branch `wffl-rebrand-cleanup` (AppState.swift,
  AudioFileDecoder.swift, ContentView.swift, scripts/bundle.sh,
  Tests/WfflTests/MeetingReadinessTests.swift) — do not revert it; build on it.
- `AppState` is `@MainActor`; LLM tasks must remain `Task.detached` app-owned.
- After each fix: `swift build && swift test`.
- Priority order is P0-1 … P0-5 first (tonight-blocking), then P1, then P2.
