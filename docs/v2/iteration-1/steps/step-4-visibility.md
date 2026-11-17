# Step 4: show the user when a transcript has gaps

**Rules served:** 3 (the totals are stored and shown).
**Checked in advance:** yes.
**Owner approval needed:** no.

## What is wrong today

After steps 1 to 3 the app counts what happened to every second and writes it in the meeting's
note. The note sits in a collapsed section called "How it was transcribed", so a user would
not see a problem. Two related gaps remain:

- If the system-audio stream dies mid-recording, nothing says so. `SystemAudioCapture` has an
  `onStopped` callback that no code assigns.
- The Parakeet check, BAPS Whisper's safety net, is only present if the user happened to
  download Parakeet. Setup downloads only the engine the user picked.

## What this step changes

1. **`MeetingView.swift`:** when the note begins with "Incomplete", a visible line appears
   above the collapsed section: "Parts of this recording were not transcribed."
   (`TranscriptionStats.note` adds that word when a chunk failed, or when the model returned
   nothing for more than a third of the audio.)
2. **`RecorderController.swift`:** `onStopped` is assigned. If system audio stops during a
   recording, the mixer stops waiting for it, and the user sees: "System audio stopped, so
   other participants are no longer being recorded. Your microphone is still recording."
3. **`SetupSession.swift`:** choosing BAPS Whisper in setup also downloads Parakeet.
4. **`WfflApp.swift`:** the headless `--transcribe <file> baps` mode prints the accounting line
   after the transcript, on standard error. Step 5 reads it.

## Before you start

- [ ] Steps 1 to 3 are committed.
- [ ] `swift test` passes.

## Do it

### With the patch (preferred)

```bash
git apply --check docs/v2/iteration-1/reference/step-4.patch
```

```bash
git apply docs/v2/iteration-1/reference/step-4.patch
```

### By hand

1. `Sources/Wffl/Views/MeetingView.swift`: find
   `if let note = meeting.transcriptionNote, !note.isEmpty {`. As the first thing inside that
   block, before `DisclosureGroup`, add:
   ```swift
   // TranscriptionStats.note starts with "Incomplete" when chunks failed or came back empty.
   if note.hasPrefix("Incomplete") {
       Label("Parts of this recording were not transcribed.", systemImage: "exclamationmark.triangle")
           .font(.system(size: 12, weight: .medium))
   }
   ```
2. `Sources/Wffl/Audio/RecorderController.swift`: in `start`, in the block that creates
   `SystemAudioCapture()`, after the `s.onLevel = ...` line, add:
   ```swift
   s.onStopped = { [weak self] _ in
       Task { @MainActor [weak self] in
           guard let self, self.state == .recording || self.state == .paused else { return }
           self.bus.systemEnabled = false
           self.systemAudioActive = false
           self.captureWarning = "System audio stopped, so other participants are no longer being recorded. Your microphone is still recording."
           self.refreshAudioWarning()
       }
   }
   ```
3. `Sources/Wffl/Welcome/Setup/SetupSession.swift`: in `startDownload`, change the `.baps` case
   so it calls both `BapsModelManager.shared.download()` and
   `ParakeetModelManager.shared.download()`.
4. `Sources/Wffl/WfflApp.swift`: in `transcribeWithBaps`, keep the whole result of
   `ChunkedFileTranscriber.transcribe` in `let result`, print `result.segments` as before, then
   add `say(result.stats.note(engine: "baps-whisper", model: BapsModelManager.variant))`.

## Verify

```bash
swift build 2>&1 | grep -E " error|Build complete"
```

Expect: `Build complete!`

```bash
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3
```

Expect: `Executed 332 tests, with 3 tests skipped and 0 failures`.

```bash
grep -n "onStopped" Sources/Wffl/Audio/RecorderController.swift
```

Expect: one line.

## Done when

- [ ] Build completes and all tests pass.
- [ ] STATUS.md is updated.

## Do not

- Do not add a new database column for the warning. The note's first word is enough.
- Do not use yellow or orange for the warning line. In this app's design, orange means "live".
- Do not download Parakeet automatically for people who already use the app. For the owner's
  Mac, step 5 installs it by hand.

## Commit

```
feat(pipeline): surface transcript gaps and a dead system-audio stream

A meeting whose note begins "Incomplete" shows a visible warning. A
system-audio stream that stops mid-recording is reported and no longer holds
up the microphone. Setup installs Parakeet alongside BAPS Whisper so the
backup check is present. The headless transcribe mode prints the accounting line.
```
