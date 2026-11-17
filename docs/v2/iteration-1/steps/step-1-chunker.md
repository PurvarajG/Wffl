# Step 1: stop discarding quiet audio, and count every second

**Rules served:** 2 (level never decides), 3 (every second accounted for), 5 (one code path).
**Checked in advance:** yes. The patch applies to commit `5a201ae`; the app builds; all tests pass.
**Owner approval needed:** no.

## What is wrong today

`AudioChunker` cuts the audio into chunks and then throws away any chunk that has no 300 ms
stretch louder than a fixed level (`silenceRMS = 0.008`). Quiet speech sits under that level,
so it is discarded before the model hears it. The same fixed level decides where to cut, so
quiet audio is always cut at the 4-second minimum, which gives the model too little context.
The callers ignore the "discarded" result, so nothing records the loss.

The live class and the file function each have their own copy of the loop that reads chunks,
and each swallows a failed or empty result silently.

## What this step changes

1. **`AudioChunker` never discards audio for being quiet.** It uses energy only to choose where
   to cut, and only by comparing the audio with itself. A pause is "the last 0.8 s is much
   quieter than the rest of this chunk". Chunks are 10 to 28 seconds. The only audio it skips
   is digital silence (no signal at all) or a final scrap under one second, and it reports
   every skipped second.
2. **One function reads a chunk: `ChunkStep.run`.** The live class and the file function both
   call it. It raises a quiet chunk to a normal speaking level (`LevelNormalizer`), calls the
   engine, and records what happened.
3. **`TranscriptionStats` counts every second**: transcribed, empty (the model returned
   nothing), failed (the model threw an error), or skipped. Nothing is dropped without being
   counted.

Why 10 to 28 seconds: BAPS Whisper was tuned on clips averaging 26 seconds and reads at most
30 seconds at once. Four-second chunks were far outside what it was measured on.

Effect the user will notice: live text appears every 10 to 28 seconds instead of every 4, and
a line of the transcript is that long.

## Before you start

- [ ] `git status` shows no changes under `Sources/` or `Tests/`.
- [ ] `swift test` passes (see README for the command).
- [ ] You are on a new branch for this work, for example `fix/pipeline-v2-iteration-1`.

## Do it

### With the patch (preferred)

```bash
git apply --check docs/v2/iteration-1/reference/step-1.patch
```

If that prints nothing, apply it:

```bash
git apply docs/v2/iteration-1/reference/step-1.patch
```

If `--check` reports an error, do not force it. Use the "By hand" section.

### By hand

Make exactly these eight changes.

1. **Replace** `Sources/Wffl/Transcription/AudioChunker.swift` with
   `docs/v2/iteration-1/reference/AudioChunker.swift`.
2. **Replace** `Sources/Wffl/Transcription/ChunkedTranscriber.swift` with
   `docs/v2/iteration-1/reference/ChunkedTranscriber.swift`.
3. **Delete** `Tests/WfflTests/AudioChunkerTests.swift`. It tests the behaviour being removed.
4. **Copy** `docs/v2/iteration-1/reference/PipelineRulesTests.swift` to `Tests/WfflTests/`.
5. In `Sources/Wffl/Transcription/WhisperLiveTranscriber.swift`:
   - In `protocol LiveTranscriber`, after the `onProcessing` line, add:
     ```swift
     /// What happened to the audio so far (rule 3). nil for an engine that does not count.
     var stats: TranscriptionStats? { get }
     ```
   - Directly after the protocol's closing brace, add:
     ```swift
     extension LiveTranscriber {
         var stats: TranscriptionStats? { nil }
     }
     ```
   - In `maybeProcess`, change `case .droppedSilence:` to `case .skipped:`.
6. In `Sources/Wffl/Transcription/TranscriptionCoverage.swift`, the type used three things from
   `AudioChunker` that no longer exist. Give it private copies. Add inside the struct:
   ```swift
   private static let silenceRMS: Float = 0.008
   private static let speechWindowSamples = Int(0.3 * 16_000)
   private static func rms(_ samples: ArraySlice<Float>) -> Float {
       guard !samples.isEmpty else { return 0 }
       var sum: Float = 0
       for s in samples { sum += s * s }
       return sqrt(sum / Float(samples.count))
   }
   ```
   and change every `AudioChunker.silenceRMS`, `AudioChunker.speechWindowSamples` and
   `AudioChunker.rms(` in that file to `Self.` plus the same name. (This type serves only
   whisper.cpp and is deleted in step 6.)
7. In `Sources/Wffl/AppState.swift` there are two calls of the form
   `segs = try await ChunkedFileTranscriber.transcribe( ... ) { p in ... }`. The function now
   returns a pair. Add `.segments` after the closing brace of each call's trailing closure.
8. In `Sources/Wffl/WfflApp.swift`, in `transcribeWithBaps`, the call
   `ChunkedFileTranscriber.transcribe(fileURL: file, ...)` also needs `.segments` added after
   its closing parenthesis.

## What each new piece is

| Name | In file | Purpose |
|---|---|---|
| `AudioChunker.pop(force:)` | `AudioChunker.swift` | Returns `.ready(samples, offset)`, `.skipped(seconds, reason)` or `.empty` |
| `AudioChunker.endsInPause()` | same | True when the last 0.8 s is under 30% of the whole chunk's level. A ratio, so it works at any volume. |
| `AudioChunker.bestCutPoint()` | same | At 28 s, cuts at the quietest 300 ms between 20 s and 28 s |
| `TranscriptionStats` | `ChunkedTranscriber.swift` | The counts for one run, plus `isHealthy` and `note(engine:model:)` |
| `TranscriptionStatsBox` | same | The same counts, safe to update from two threads |
| `LevelNormalizer.apply` | same | Raises a chunk towards -26 dBFS, by at most 30 dB. Never lowers. |
| `ChunkStep.run` | same | Normalise, call the engine, count the result. The only place a chunk becomes a line. |

`isHealthy` is false when any chunk failed, or when the model returned nothing for more than a
third of the audio it was given. `note` then starts with the word "Incomplete". Step 4 uses
that word to warn the user.

## Verify

```bash
swift build 2>&1 | grep -E " error|Build complete"
```

Expect: `Build complete!`

```bash
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3
```

Expect: a final line with `0 failures`. In the advance check the count was 332 tests after
step 2; after step 1 alone it is 329.

```bash
swift test --filter PipelineRulesTests 2>&1 | grep -E "passed|failed" | grep "Test Case"
```

Expect: nine test cases, all `passed`. The two that prove the fix are
`testQuietSpeechReachesTheModelLive` and `testQuietSpeechReachesTheModelFromAFile`: speech-like
audio at -50, -40, -30 and -20 dBFS, with at least 99% of it reaching the model.

```bash
grep -rn "silenceRMS\|containsSpeech\|droppedSilence" Sources/Wffl --include="*.swift" | grep -v TranscriptionCoverage
```

Expect: no output.

## Done when

- [ ] Build completes.
- [ ] All tests pass.
- [ ] The grep above prints nothing.
- [ ] STATUS.md is updated with the test count.

## Do not

- Do not add a loudness threshold anywhere, however small. `noSignalPeak` (0.0001) is the one
  exception and it means "nothing is connected", not "quiet".
- Do not change `AudioFileDecoder.swift`. Its channel averaging no longer matters, because
  level is normalised before the model and nothing is discarded.
- Do not change `BapsWhisper.swift` in this step.
- Do not tune `pauseRatio`, `minChunkSeconds`, `targetRMS` or `maxGain`. Step 5 is the only
  place those are judged, against real recordings.

## Commit

```
fix(pipeline): never discard quiet audio; count every second

AudioChunker cut chunks and then dropped any without a 300 ms stretch above
a fixed level, so quiet speech never reached the model. It now cuts at pauses
measured against the chunk itself and skips only digital silence. One
function, ChunkStep.run, reads a chunk for both the live and file paths and
records what happened to every second in TranscriptionStats.
```
