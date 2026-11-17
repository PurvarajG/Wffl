# Step 7: delete the correction layers that guess

**Rules served:** none directly. This step removes code that the five rules make unnecessary
and that has been measured to do harm on BAPS Whisper's output.
**Checked in advance:** no. Give it to the strongest model available.
**Owner approval needed:** **yes.** Do not start until STATUS.md records the owner's yes.

## What the owner is agreeing to

The vocabulary term editor in Settings goes. New spellings are added to the spelling pack
instead. Nothing else the user sees changes: the cleaned-transcript view, paragraphs and the
spelling pack all stay.

## What stays, and why

These three carry the product. This step must not change their behaviour.

| Keep | File | Why |
|---|---|---|
| The spelling pack | `Sources/Wffl/Transcription/NormalizationPack.swift` | Exact-match aliases to canonical spellings. No guessing. |
| The Parakeet check | `BapsBackupRule`, `BapsChunkReader` in `BapsWhisper.swift` | Catches the model's known failures. |
| Deterministic cleanup | In `Sources/Wffl/LLM/CleanupPipeline.swift`: the part of `CleanupScanner.scan` that applies the pack, drops duplicate lines and removes fillers and stutters; `StructurePass`; the function that assembles the result | Produces the cleaned view. |

## What goes, and why

Each of these guesses at words. Each is already switched off for BAPS Whisper, or was built
for an engine removed in step 6.

| Delete | Where | Evidence |
|---|---|---|
| The LLM arbiter | `ArbiterPass`, `CleanupEditGuard`, and the "suspects" scanning in `CleanupPipeline.swift`; `TextFidelity.swift` | The code's own comment on `CleanupScanner.scan`: on a held-out talk it accepted three edits, all wrong (`brahmam` to `Brahman`). The owner's database shows 196 edits ever proposed and 36 accepted. For BAPS Whisper, `writesGujarati` already sends nothing to it. |
| Fuzzy vocabulary matching | In `Vocabulary.swift`: `prompt`, `nearMisses`, `candidateTerms`, `outOfDictionaryWords`, `outOfDictionaryFraction`, `looksLikeProperNoun`, `mishearingHints`, `fullGlossary`, `tripwires`, `tripwireKeys`, and the term list with its editor | Built to repair stock Whisper and Parakeet. `Prefs.swift` says BAPS Whisper replaced it. |
| The vocabulary gate | `VocabularyGate.swift` | It decided when to switch the layers above on. |
| Profiles | `TranscriptionProfile` and its helpers in `Prefs.swift` | "Devotional" chose whisper.cpp, beam search and the glossary. All three are gone. |
| The prototype | `Sources/WfflPrototype/`, `Support/Prototype/`, `scripts/prototype.sh`, and its target in `Package.swift` | Marked "Not shipped" in `Package.swift`. |

What survives from `Vocabulary.swift`: only what `NormalizationPack.swift` calls, which is
`Vocabulary.shared.isEnglishWord` and `Vocabulary.contains`, plus anything those two need.

## Before you start

- [ ] Step 6 is committed, and STATUS.md records the owner's approval for step 7.
- [ ] `swift test` passes.

## Do it

### 1. Pin today's behaviour with a test, before deleting anything

The cleaned view for a BAPS Whisper transcript must come out identical before and after. Add
`Tests/WfflTests/CleanupUnchangedTests.swift`:

1. Write a fixture transcript of about 40 lines in the format the cleanup takes
   (`[mm:ss] text` per line; see the existing fixtures in `CleanupPipelineTests.swift`). Make
   up the content; do not use a real recording. Include: three aliases from the default pack
   (for example `Kachar`, `Bhagavan`, `Jeeva`), two consecutive duplicate lines, fillers
   (`um`, `uh`), a stutter (`the the the`), and enough lines to form several paragraphs.
2. The test calls
   `TranscriptCleanupService(config:).clean(transcript: fixture, writesGujarati: true)`
   and compares `result.markdown` with a string stored in the test.
3. To get that string, run the test once with an empty expected value, copy the actual output
   from the failure message into the test, and run it again. It must pass.

Commit this test on its own before going further:
`test(cleanup): pin cleaned output for a BAPS Whisper transcript`.

If `clean` needs a running language model even with `writesGujarati: true`, stop and report.
That would mean the arbiter is not as separate as this plan assumes.

### 2. Remove the arbiter

In `TranscriptCleanupService.clean`, remove the arbiter call and everything that only feeds
it. In `CleanupPipeline.swift`, delete `ArbiterPass`, `CleanupEditGuard`, and the second half
of `CleanupScanner.scan` (the loop that fills `suspects`). `scan` no longer needs its
`writesGujarati` parameter, and `clean` no longer needs one either. Delete
`TextFidelity.swift`.

Then remove what only the arbiter used: `Prefs.arbiterModel`, `Prefs.cleanupLlmConfig`,
`AppState.warmUpCleanupModel` and its call in `stopRecording`, and the model lookup in
`generateCleanedTranscript`. The `writesGujarati` line in `AppState.generateCleanedTranscript`
goes too.

Run the test from part 1. It must still pass, unchanged.

### 3. Remove the gate and the profiles

- Delete `VocabularyGate.swift`.
- Remove the `gate:` parameter from `ChunkedLiveTranscriber.init`,
  `ChunkedFileTranscriber.transcribe`, and every caller (`RecorderController`, `AppState`,
  `WfflApp`, `PipelineRulesTests`), along with the `gate.observe` calls and
  `RecorderController.gate`.
- In `Prefs.swift`, delete `TranscriptionProfile`, `transcriptionProfile`,
  `selectDevotionalProfileFromVocabularyGate`, `clearGateSelectedProfile`,
  `markProfileExplicit`, `vocabMode`, `effectiveVocabMode`, and every call to them.
- Remove the profile and vocabulary-mode controls from Settings.

### 4. Reduce `Vocabulary.swift`

Delete everything in it that is not reached from `isEnglishWord` or `contains`. Remove the
vocabulary term editor from `Views/SettingsSections.swift`. Leave the section that shows the
spelling pack and its rejected entries.

Do not delete the user's `vocabulary.json` file from Application Support. It is simply no
longer read.

### 5. Remove the prototype

```bash
git rm -r -q Sources/WfflPrototype Support/Prototype scripts/prototype.sh
```

Remove the `WfflPrototype` executable target from `Package.swift`.

### 6. Tests

Delete tests that test only deleted code: `VocabularyGateTests.swift`,
`TranscriptFidelityTests.swift`, `PrefsProfileTests.swift`, `ArbiterGlossaryTests.swift`,
`ArbiterPromptTests.swift`, and the arbiter and vocabulary cases inside
`CleanupPipelineTests.swift`, `MeetingJul27RegressionTests.swift` and
`TranscriptProvenanceTests.swift`. Keep every case that tests the pack, structure, duplicates,
fillers, the mixer's mute behaviour, or speaker labels.

## Fixing compile errors

Same method as step 6: build, fix the first error, repeat.

| The error mentions | Do this |
|---|---|
| `VocabularyGate`, `gate` | Delete the parameter, property or call. |
| `TranscriptionProfile`, `transcriptionProfile`, `vocabMode` | Delete the use. If it chose between two behaviours, keep the one that was `general`. |
| `ArbiterPass`, `CleanupEditGuard`, `TextFidelity`, `suspects` | Delete. |
| A `Vocabulary.shared` member other than `isEnglishWord` | Delete the caller if it is arbiter or gate code. If the caller is in `NormalizationPack.swift`, stop and report. |
| `cleanupLlmConfig`, `arbiterModel`, `warmUpCleanupModel` | Delete. Cleanup no longer uses a language model. |

Stop and report if fixing an error would change `NormalizationPack.swift`, `BapsWhisper.swift`,
or the output of the test from part 1.

## Verify

```bash
swift build 2>&1 | grep -E " error|Build complete"
```

```bash
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3
```

Expect: `0 failures`.

```bash
swift test --filter "CleanupUnchangedTests|NormalizationPackTests|BapsBackupRuleTests|PipelineRulesTests|MixBusClockTests" 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
```

Expect: `0 failures`. `NormalizationPackTests.swift` must show no changes in `git diff`.

```bash
git diff --stat HEAD -- Sources/Wffl/Transcription/NormalizationPack.swift Sources/Wffl/Transcription/BapsWhisper.swift
```

Expect: no output.

```bash
grep -rn "VocabularyGate\|ArbiterPass\|TextFidelity\|TranscriptionProfile" Sources Tests
```

Expect: no output.

## Done when

- [ ] Every "Verify" result matches.
- [ ] The summary still generates for a meeting (**Owner**, or a model that can drive the app).
      The summary uses its own language-model settings (`Prefs.llmConfig`), which this step
      does not touch.
- [ ] STATUS.md is updated.

## Commit

```
refactor(pipeline): remove the correction layers that guess

The LLM arbiter, fuzzy vocabulary matching, the vocabulary gate and the
general/devotional profiles were built to repair what stock Whisper and
Parakeet misheard. BAPS Whisper replaced them, and on its output the arbiter
was measured accepting only wrong edits. The spelling pack, the Parakeet
check and deterministic cleanup are unchanged, pinned by CleanupUnchangedTests.
Also removes the unshipped WfflPrototype target.
```
