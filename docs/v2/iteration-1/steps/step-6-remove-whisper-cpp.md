# Step 6: delete whisper.cpp

**Rules served:** 5 (one code path).
**Checked in advance:** no. This step has not been applied or built. Give it to the strongest
model available, and expect to fix compile errors by following the tables below.
**Owner approval needed:** **yes.** Do not start until STATUS.md records the owner's yes.

## What the owner is agreeing to

Wffl stops offering other languages and translation to English. The README and website say it
has both. After this step Wffl transcribes English, including anglicised Gujarati, with BAPS
Whisper, and offers Parakeet as an English alternative.

## Why

whisper.cpp is the only engine with its own live class, its own file function, its own
voice-activity model, its own hallucination filter and its own coverage measure. Every fix to
the pipeline has to be made twice or it applies to one engine only. That is how the coverage
warning came to exist for an engine nobody was using. It is also 43 MB of vendored code and
1,857 tracked files.

Anglicised Gujarati does not depend on it. BAPS Whisper runs on WhisperKit.

## Before you start

- [ ] Steps 1 to 5 are done, and STATUS.md records the owner's approval for step 6.
- [ ] `swift test` passes.
- [ ] `git status` is clean.

## Do it

Work in this order. Build after each numbered group and fix what breaks using "Fixing compile
errors" below.

### 1. Move the three things that must survive

Do this first, so nothing is lost when files are deleted.

| What | From | To |
|---|---|---|
| `struct WhisperSegment` (the whole struct, lines 4 to 16) | `Sources/Wffl/Transcription/WhisperContext.swift` | top of `Sources/Wffl/Transcription/ChunkedTranscriber.swift` |
| `enum Resampler` (the whole enum, at the end of the file) | `WhisperContext.swift` | bottom of `ChunkedTranscriber.swift` |
| `static var modelsDir: URL { ... }` (five lines) | `Sources/Wffl/Transcription/ModelManager.swift` | into `BapsModelManager` in `BapsWhisper.swift`, as `private static var modelsDir`; change `ModelManager.modelsDir` in that file to `Self.modelsDir` |

In `WhisperSegment`, update the doc comments so they no longer mention `HallucinationGate` or
`Vocabulary.correct`.

One more thing survives in reduced form. `HallucinationGate.placeholderText` is a string that
old transcripts in users' databases contain, and the cleanup code still recognises it. Add to
the top of `Sources/Wffl/LLM/CleanupPipeline.swift`:

```swift
/// The marker older versions wrote where whisper.cpp audio was judged unreadable.
/// Old transcripts still contain it, so cleanup must keep recognising it.
enum HallucinationGate {
    static let placeholderText = "[unclear audio / non-English — not transcribed]"
}
```

### 2. Delete files

```bash
git rm -r -q vendor Sources/CWhisper
```

```bash
git rm -q Sources/Wffl/Transcription/WhisperContext.swift Sources/Wffl/Transcription/WhisperLiveTranscriber.swift Sources/Wffl/Transcription/ModelManager.swift Sources/Wffl/Transcription/VADModel.swift Sources/Wffl/Transcription/TranscriptionCoverage.swift
```

```bash
git rm -q Tests/WfflTests/HallucinationGateTests.swift Tests/WfflTests/AcceptanceCorpusTests.swift Tests/WfflTests/LiveHarnessTests.swift Tests/WfflTests/TranscriptionCoverageTests.swift
```

### 3. `Package.swift`

- Remove the whole `.target(name: "CWhisper", path: "Sources/CWhisper")` entry.
- Remove `"CWhisper",` from the Wffl target's dependencies.
- Remove `.unsafeFlags(["-L", "vendor/lib"]),`.
- Remove `.linkedFramework("Metal")`, `.linkedFramework("MetalKit")` and `.linkedLibrary("c++")`.
  If the link then fails with undefined symbols, put back only the one the error names.
- Keep the Sparkle rpath flag and the other frameworks.

### 4. The engine choice

`Sources/Wffl/Support/Prefs.swift`:

- `enum TranscriptionEngine` loses `whisper`.
- `effectiveEngine` becomes:
  ```swift
  static var effectiveEngine: TranscriptionEngine {
      transcriptionEngine == "parakeet" ? .parakeet : .baps
  }
  ```
  A user whose stored engine was `whisper` now gets BAPS Whisper.
- Delete `whisperModel`, `effectiveWhisperModel`, `language`, `translate`, `offlineBeamSearch`.

### 5. Remove the `LiveTranscriber` protocol

Only one class conforms now. In `ChunkedTranscriber.swift`, remove `: LiveTranscriber` from
`ChunkedLiveTranscriber`. In `RecorderController.swift`, change the type of `transcriber` and
the return type of `makeLiveTranscriber` from `LiveTranscriber` to `ChunkedLiveTranscriber`,
and delete the `.whisper` case.

### 6. `AppState.swift`

- `EngineSource` loses `.whisper`. `resolveEngineSource` and `missingModelMessage` lose their
  whisper branches.
- In `runTranscription`: delete `case .whisper`, the `language`, `translate` and `beam` locals,
  `whisperCoverage`, `coverageSnapshot`, and the whole `else if !segs.isEmpty { ... }` branch
  that built the old note. `fileStats` is now always set, so make it a non-optional `let`
  assigned in each case, and write the note unconditionally.

### 7. The app shell and views

- `WfflApp.swift`: delete the `models: ModelManager` state object and its
  `.environmentObject(models)`. In the `--transcribe` handling, delete everything from
  `guard let modelPath = ModelManager.shared.path(for: modelId)` to the end of that `if`
  block, so the mode is BAPS Whisper only; the third argument becomes unused and is removed.
- Remove the Whisper model list and the language and translate controls from
  `Views/SettingsPane.swift` and `Views/SettingsSections.swift`.
- Remove the `.whisper` cases from `Views/AskHome.swift` and
  `Welcome/Setup/SetupSession.swift` (including `whisperInfo`).
- `Welcome/ProductionOpening/OpeningNativeAskCapture.swift`: remove its `ModelManager`
  environment object.

### 8. Words

- `README.md`: remove the "Whisper (whisper.cpp)" row from the engines table and every other
  mention of whisper.cpp, other languages and translation. `website/index.html`: the same.
- `.gitignore`: remove the two `vendor/whisper.cpp/build` lines.

## Fixing compile errors

Build, read the first error, fix it by this table, build again. Do not fix by adding code back.

| The error mentions | Do this |
|---|---|
| `ModelManager` | Delete the reference. If it is a whole UI row or section about Whisper models, delete the row or section. |
| `Prefs.language`, `Prefs.translate`, `"language"`, `"translate"`, `whisperModel` | Delete the control or argument that uses it. |
| `.whisper` in a `switch` | Delete that case. |
| `WhisperContext`, `WhisperLiveTranscriber`, `WhisperFileTranscriber`, `VADModel` | Delete the code that uses it. It is whisper.cpp only. |
| `TranscriptionCoverage`, `whisperCoverage` | Delete. `TranscriptionStats` replaced it. |
| `HallucinationGate.apply` or `droppedSegmentCount` | Delete the call. Only `placeholderText` survives. |
| `LiveTranscriber` | Replace with `ChunkedLiveTranscriber`. |
| A test file that tests only deleted code | Delete the test case, or the file if nothing is left. |

If an error does not fit the table, or fixing it would mean changing `BapsWhisper.swift`,
`NormalizationPack.swift`, `AudioChunker.swift`, `MixBus.swift` or `Database.swift`, stop and
report.

## Verify

```bash
swift build 2>&1 | grep -E " error|Build complete"
```

Expect: `Build complete!`, and no linker warnings about `libggml` or `libwhisper`.

```bash
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3
```

Expect: `0 failures`. The count will be lower than 332, because four test files were deleted.

```bash
swift test --filter "PipelineRulesTests|MixBusClockTests|NormalizationPackTests|BapsBackupRuleTests" 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
```

Expect: `0 failures`. These four suites must be untouched and passing.

```bash
grep -rn -i "whisper_\|CWhisper\|ggml\|ModelManager\.shared" Sources Package.swift | grep -v "BapsModelManager\|ParakeetModelManager\|DiarizerModelManager"
```

Expect: no output.

```bash
.build/debug/Wffl --transcribe ~/Library/Application\ Support/Wffl/recordings/0912DB0B-A414-417A-B051-B2EC0E94911D.wav > ~/wffl-checks/nov15-step6.txt 2> ~/wffl-checks/nov15-step6.log; grep "engine: baps-whisper" ~/wffl-checks/nov15-step6.log
```

Expect: the same `transcribed` figure as step 5's check A.

## Done when

- [ ] Every "Verify" result matches.
- [ ] The app launches, Settings opens, and its Transcription section shows BAPS Whisper and
      Parakeet only (**Owner**, or a model that can drive the app).
- [ ] STATUS.md is updated.

## Commit

```
refactor(pipeline): remove whisper.cpp

whisper.cpp was the one engine with its own live transcriber, file
transcriber, voice-activity model, hallucination filter and coverage measure,
so every pipeline fix had to be made twice. Wffl now transcribes English with
BAPS Whisper (WhisperKit) or Parakeet through one code path. Other languages
and translation are removed. Deletes vendor/ (43 MB) and Sources/CWhisper.
```
