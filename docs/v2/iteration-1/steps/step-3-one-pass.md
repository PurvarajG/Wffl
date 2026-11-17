# Step 3: record without a model, transcribe once, never replace with less

**Rules served:** 1 (recording never waits), 4 (never replace with less), 5 (one code path).
**Checked in advance:** yes. Builds, and all 332 tests pass. The behaviour itself needs the
manual check at the end of this step, because no automated test starts a real recording.
**Owner approval needed:** no.

## What is wrong today

1. **Record refuses to start until the model is in memory.** `RecorderController.start` fails
   with "BAPS Whisper is still loading — try again in a moment." Loading can take minutes after
   macOS clears the model's compiled cache. Capturing audio needs only the microphone and a
   file.
2. **Every recording is transcribed twice.** After Stop, `AppState` re-transcribes the whole
   file and replaces the live transcript with the result, whenever that result is not empty.
   On 2026-11-15 the second pass was far worse than the first, and it won.
3. **The audio file is closed only after the transcriber finishes.** Quitting during that wait
   leaves a file with a broken header.

## What this step changes

**In `RecorderController`:**

- `start` builds a live transcriber if the engine is ready. If it is not, recording starts
  anyway with no transcriber, and shows: "Recording. No transcription model is ready yet, so
  the transcript will be written once it has loaded." Recording never fails for want of a
  model.
- The special case that used Parakeet for live text when BAPS Whisper was selected is gone.
  Live text now comes from BAPS Whisper, with the Parakeet check, the same as the file pass.
- `stop` closes the audio file and links it to the meeting **before** waiting for the
  transcriber.
- Two new read-only properties: `lastRunStats` (what the live pass did with the audio, or nil
  if there was no live pass) and `lastRunEngine` (the engine and model names for the note).

**In `AppState`:**

- After a recording finishes, the file is transcribed again **only if** the live pass did not
  cover it: there was no live pass, or a chunk failed. Otherwise `finishLiveTranscript` runs
  the things that follow a transcript: speaker labels, the note, cleanup, summary.
- `needsFilePass` holds the meetings waiting for a file pass. `runPendingFilePass` starts one
  when a model is ready and nothing else is transcribing or recording. It is called after Stop,
  when a model finishes loading, and when a transcription job ends.
- At launch, any recording that has audio but no transcript and no note is added to
  `needsFilePass`. This also covers recordings recovered after a crash.
- Manual Re-transcribe still replaces the transcript, behind one check: if the new result
  covers less than 95% of the seconds the existing one covers, the existing transcript is kept
  and the user is told.
- For the BAPS Whisper and Parakeet engines, the note is now the accounting line from
  `TranscriptionStats.note`, and it is written even when nothing was heard.

**In `WfflApp`:** quitting during a recording stops the recording first
(`applicationShouldTerminate`), so the audio file is closed properly.

The "Re-transcribe and clean after recording" setting (`Prefs.autoPolish`) keeps its name and
its storage. It now controls only whether cleanup runs after a recording.

## Before you start

- [ ] Steps 1 and 2 are committed.
- [ ] `swift test` passes.

## Do it

### With the patch (preferred)

```bash
git apply --check docs/v2/iteration-1/reference/step-3.patch
```

```bash
git apply docs/v2/iteration-1/reference/step-3.patch
```

### By hand

Open `docs/v2/iteration-1/reference/step-3.patch` beside the code. It is the specification:
lines starting with `-` are removed, lines starting with `+` are added. The changes, in order:

**`Sources/Wffl/Audio/RecorderController.swift`**

1. After `var onSegmentsChanged`, add the two properties `lastRunStats` and `lastRunEngine`.
2. In `start`, replace everything from the comment `// 2. Transcription engine` down to, but
   not including, `// 3. Output WAV` with the new block. The new block resets the two
   properties, calls `makeLiveTranscriber`, wires `onSegments` and `onProcessing` exactly as
   before if it returned a transcriber, and otherwise sets `errorMessage` to the "Recording.
   No transcription model is ready yet..." text.
3. Add the method `makeLiveTranscriber(gate:)` just above `setMicMuted`. It returns a
   transcriber plus engine and model names, or nil. It contains a `switch` on
   `Prefs.effectiveEngine` with three cases, and never throws.
4. In `stop`, move `let wavWriteFailed = wavWriter.finish()` and the block that re-reads the
   meeting row and sets `audioPath` to just after `bus.stop()`, before the
   `withCheckedContinuation` that waits for the transcriber. After that wait, add
   `lastRunStats = transcriber?.stats` before `transcriber = nil`.

**`Sources/Wffl/AppState.swift`**

5. In `init`, inside `recorder.onFinished`, replace the three lines that call
   `self.retranscribe(m, quietly: true)` under `if Prefs.autoPolish` with the new block that
   chooses between `finishLiveTranscript` and `needsFilePass.insert(id)`, then calls
   `runPendingFilePass()`.
6. Directly after that closure, add `AppDelegate.recorder = recorder` and the two `$state`
   subscriptions that call `runPendingFilePass()`.
7. At the end of `recoverInterruptedRecordings`, add the loop that fills `needsFilePass`.
8. After `recoverInterruptedRecordings`, add the property `needsFilePass` and the methods
   `runPendingFilePass` and `finishLiveTranscript`.
9. In `runTranscription`:
   - beside `var whisperCoverage`, add `var fileStats: TranscriptionStats?`;
   - in the `.parakeet` and `.baps` cases, keep the result of
     `ChunkedFileTranscriber.transcribe` in `let result`, then set `segs = result.segments` and
     `fileStats = result.stats`;
   - before `replaceSegments`, add the rule 4 check;
   - beside `let coverageSnapshot`, add `let statsSnapshot = fileStats`;
   - where the note is written, write `stats.note(...)` when `statsSnapshot` exists, and keep
     the old note for the whisper.cpp engine in an `else if !segs.isEmpty`;
   - replace the "Transcript polished from the full recording." toast as the patch shows;
   - call `self.runPendingFilePass()` at the end of the success block and in the `catch` block.

**`Sources/Wffl/WfflApp.swift`**

10. In `AppDelegate`, add the static `recorder` property and `applicationShouldTerminate`.

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
grep -n "still loading" Sources/Wffl/Audio/RecorderController.swift
```

Expect: no output.

```bash
grep -n "retranscribe(m, quietly: true)" Sources/Wffl/AppState.swift
```

Expect: exactly one line, inside `runPendingFilePass`.

### Manual check (needs a person, or a model that can drive the app)

This is the only part of steps 1 to 4 that a test cannot cover. Build and sign the app as
"Building the app" in [step-5-measure.md](step-5-measure.md) describes, then:

1. Quit Wffl. Start it, and press Record within five seconds, before the model has loaded
   (Settings shows "Loading" for BAPS Whisper while it loads).
   **Expect:** recording starts at once, with the "No transcription model is ready yet" message.
2. Speak for thirty seconds. Stop.
   **Expect:** once the model has loaded, the transcript appears without any further action.
3. Record again with the model loaded. Speak for a minute. Stop.
   **Expect:** the transcript is the one that appeared while recording. There is no progress
   bar for a second transcription.
4. Start a recording, then quit the app with Cmd-Q.
   **Expect:** the app takes a moment to quit. On relaunch the meeting has its audio and plays.

If a person is not available, record that the manual check is outstanding in STATUS.md and
continue. Step 5 exercises the file pass with the real model.

## Done when

- [ ] Build completes and all tests pass.
- [ ] Both greps give the expected result.
- [ ] The manual check is done, or marked outstanding in STATUS.md.

## Do not

- Do not delete `Prefs.autoPolish` or its toggle in Settings.
- Do not add buffering that feeds a late-loaded model with audio from earlier in the
  recording. The file pass does that job with code that already exists.
- Do not make `runPendingFilePass` re-transcribe meetings that already have a transcript. That
  would re-transcribe every old meeting in a user's library on first launch.
- Do not change `Database.replaceSegments`.

## Known limit

If the app is quit while a recording's live pass has failed chunks, the meeting keeps its
partial transcript and is not picked up automatically at the next launch, because it has
segments. Manual Re-transcribe fixes it. This is rare and left as it is.

## Commit

```
fix(recording): record without a model; one pass; never replace with less

Record no longer waits for the transcription model: with none loaded, audio is
captured and the file is transcribed once the model is ready. The automatic
second pass after Stop is gone; the file is read again only when the live pass
had no model or a chunk failed. Re-transcribe keeps the existing transcript if
the new one covers less audio. The audio file is closed before waiting for the
transcriber, and quitting mid-recording stops the recording first.
```
