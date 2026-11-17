# Wffl v2, iteration 1: make the transcript trustworthy

Start here. This folder is the whole plan. You do not need the conversation that produced it,
and you do not need to investigate the codebase before you begin. Everything a step needs is in
that step's file.

## The goal

Wffl exists to give flawless English transcription that writes anglicised Gujarati correctly.
On 2026-11-15 it recorded a 22-minute conversation and transcribed 90 seconds of it, with no
warning. This iteration makes that impossible, and removes the code that kept producing
failures like it.

It is finished when a quiet conversation across a room is transcribed in full, the app says so
when it is not, and Record works the moment it is pressed.

## The five rules

These are the specification. Every step serves them. A change that breaks one is wrong,
whatever else it fixes.

1. **Recording never waits for, or depends on, a model.**
2. **Audio level never decides whether audio is transcribed.**
3. **Every second of audio is either sent to the model or listed as skipped with a reason, and
   the totals are stored with the meeting.**
4. **A transcript is never replaced by one that covers less audio.**
5. **One code path transcribes.** Live recording, the pass after Stop, import and re-transcribe
   all call the same function.

## What carries the product, and must not be removed

| Part | File | What it does |
|---|---|---|
| BAPS Whisper | `Sources/Wffl/Transcription/BapsWhisper.swift` | The tuned model. Writes English with Gujarati words in Latin letters. |
| The Parakeet check | `BapsBackupRule` in the same file | When BAPS Whisper loops on a word, writes another script, or drops most of a chunk, Parakeet reads that chunk instead. |
| The spelling pack | `Sources/Wffl/Transcription/NormalizationPack.swift` | Exact-match aliases to one canonical spelling (Kachar to Khachar). No guessing. |

## The steps

Do them in order. Each is one commit, and the test suite passes at the end of each.

| Step | File | What it does | Checked in advance? | Needs the owner's yes? |
|---|---|---|---|---|
| 1 | [steps/step-1-chunker.md](steps/step-1-chunker.md) | Stop discarding quiet audio; count every second | Yes: patch applies, 332 tests pass | No |
| 2 | [steps/step-2-mixer.md](steps/step-2-mixer.md) | Stop the mixer inserting silence | Yes | No |
| 3 | [steps/step-3-one-pass.md](steps/step-3-one-pass.md) | Record without a model; one pass; never replace with less | Yes | No |
| 4 | [steps/step-4-visibility.md](steps/step-4-visibility.md) | Show the user when a transcript has gaps | Yes | No |
| 5 | [steps/step-5-measure.md](steps/step-5-measure.md) | Prove it on the real recording and on the model's test clips | Partly: see the step | No |
| 6 | [steps/step-6-remove-whisper-cpp.md](steps/step-6-remove-whisper-cpp.md) | Delete the engine that has its own separate pipeline | No | **Yes** |
| 7 | [steps/step-7-remove-guessing-layers.md](steps/step-7-remove-guessing-layers.md) | Delete the correction layers that guess at words | No | **Yes** |
| 8 | [steps/step-8-docs-and-release.md](steps/step-8-docs-and-release.md) | One architecture document; delete old plans; release | No | **Yes** (deletes files for good) |

Steps 1 to 5 fix the failure on their own. Steps 6 to 8 remove about 4,400 lines of app code that
the fix makes unnecessary, plus their tests and 43 MB of vendored source. If the owner has not approved a step marked "Yes", stop before it.

"Checked in advance" means the change was applied to a throwaway copy of the repository at
commit `5a201ae`, the app was built, and the full test suite was run. The exact changes are
saved as patches in [reference/](reference/).

## How to run this plan

One step at a time, with a fresh session per step. Give the session two files: this README
and the step file. Nothing else is needed.

For every step:

1. Read the step file to the end before changing anything.
2. Check the "Before you start" list. If any item is false, stop and report.
3. Make the change. Where the step offers a patch, use the patch. Edit by hand only if the
   patch does not apply, and then follow the step's "By hand" section exactly.
4. Run the step's "Verify" commands. Compare the output with what the step says to expect.
5. Tick the step in [STATUS.md](STATUS.md) and paste the evidence it asks for.
6. Commit with the message the step gives. Do not push unless the owner asks.

### Stop and report instead of improvising

Stop, change nothing further, and write what happened in STATUS.md when:

- a patch does not apply and the "By hand" instructions do not match the code you see;
- a test fails that the step does not name as expected;
- the build fails with an error the step does not mention;
- a step would require touching a file the step does not list;
- you are about to add a threshold, a retry, a fallback or a correction layer that the step
  does not describe. That is how the code got into this state.

### Which model for which step

The plan works with one model or three. If you have three tiers, split the work like this.

| Role | Model tier | Steps and duties |
|---|---|---|
| Executor | middle (for example Sonnet) | Steps 1 to 5 and 8. Applies patches, runs the checks, commits. |
| Surgeon | strongest (for example Opus) | Steps 6 and 7, which were not checked in advance and involve deleting code with many references. Also takes over any step where the executor stopped. |
| Checker | smallest (for example Haiku) | After each step: re-runs the "Verify" commands in a clean session and confirms STATUS.md matches the output. Changes no code. |

A smaller model can run steps 1 to 4 alone, because each is a patch plus a command with a
known result. Do not give steps 6 or 7 to the smallest tier.

### Commands used throughout

Run from the repository root, `/Users/purvarajsinhgohil/Developer/Wffl`.

```bash
swift build
```

```bash
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3
```

A passing run ends with a line like `Executed 332 tests, with 3 tests skipped and 0 failures`.
Three skipped tests are normal: they need audio files that are not on this Mac.

Never run `scripts/bundle.sh` or release anything unless a step says to. Never open the app's
database except as a step describes, and then only with `sqlite3 -readonly`.

## What is in this folder

| Path | What it is |
|---|---|
| `README.md` | This file |
| `CONTEXT.md` | What failed and why, the map of the pipeline, and terms used in the steps. Read once. |
| `STATUS.md` | The checklist. Update it after every step. |
| `steps/` | One file per step |
| `reference/step-N.patch` | The exact change for steps 1 to 4, made against commit `5a201ae` |
| `reference/*.swift` | The finished form of each new or rewritten file, for editing by hand |
| `reference/t4-result.md` | What the fixed pipeline produced on the 2026-11-15 recording |

## What this iteration deliberately leaves out

Each of these is real. None is needed for the five rules, and each one added now would be
another layer to debug. They are listed in [CONTEXT.md](CONTEXT.md#left-for-iteration-2) with
enough detail to pick up later.

- Telling speakers apart in a room, and transcribing the microphone and system audio separately.
- "Me" and "Them" labels that work at any volume.
- Rebinding the mute monitor when the input device changes.
- Handling sleep and wake during a recording.
- The 60-second "microphone silent" warning, which can fire in a quiet room.
- Verifying model downloads.
