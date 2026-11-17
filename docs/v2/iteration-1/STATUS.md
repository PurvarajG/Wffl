# Status

Update this file after every step. Write numbers and command output, not "done".
If you stopped, say exactly where and why under "Stops".

Plan written: 2026-11-16, against commit `5a201ae` (branch `feat/review-and-learn`).
Work branch: `fix/pipeline-v2-iteration-1`. Baseline before step 1: 325 tests, 3 skipped, 0 failures.
All four patches applied cleanly with `git apply`; nothing was edited by hand.

## Owner decisions

Steps marked "needs the owner's yes" must not start until the owner writes yes here.

| Decision | Owner's answer | Date |
|---|---|---|
| Step 6: remove whisper.cpp, which removes other languages and translation | | |
| Step 7: remove the guessing correction layers and the vocabulary term editor | | |
| Step 8 part 2: delete the old plan files (or move them to `~/Documents/wffl-old-plans`) | | |
| Live text arrives every 10 to 28 seconds, and a transcript line is that long | | |

## Steps

| Step | State | Commit | Evidence |
|---|---|---|---|
| 1 Chunker | done 2026-11-17 | `327ce45` | 329 tests, 3 skipped, 0 failures. Build complete. Gate grep: 0 lines. |
| 2 Mixer | done 2026-11-17 | `3b529fd` | 332 tests, 3 skipped, 0 failures. MixBusClockTests: 3 passed. |
| 3 One pass | done 2026-11-17, manual check outstanding | `e84075b` | 332 tests, 3 skipped, 0 failures. "still loading": 0 lines. Automatic re-transcribe call sites: 1. Manual check (press Record before the model loads; quit mid-recording): **not done**, needs the signed app. |
| 4 Visibility | done 2026-11-17 | `7d28001` | 332 tests, 3 skipped, 0 failures. `onStopped` assigned: 1 line. |
| 5 Measure | not started | | See the table below |
| 6 Remove whisper.cpp | waiting for owner | | |
| 7 Remove guessing layers | waiting for owner | | |
| 8 Docs and release | not started | | |

## Step 5 measurements

| Check | Bar | Result | Pass? |
|---|---|---|---|
| A: 2026-11-15 recording, seconds transcribed | at least 1,299 of 1,367 | 1,266 without the Parakeet check (2026-11-16, advance run) | not yet |
| A: failed chunks | 0 | 0 | yes |
| A: Parakeet check active | yes | no (Parakeet v3 not installed) | not yet |
| B: Gujarati terms in canonical spelling | at least 90% | waiting for owner | |
| C: word count against stock large-v3 | within 15% | Wffl 3,791 · independent: | |
| D: silent room, two minutes | at most 10 words | waiting for owner | |
| E: Atlas held-out clips, word error rate | at most 8.0% | | |
| F: 2026-11-15 meeting re-transcribed in the app | about 60 lines | waiting for owner | |

Calibration changes made in step 5 (what, number before, number after):

- none yet

## Release

| | |
|---|---|
| Five-minute room recording, accounting line | |
| Version released | |

## Stops

Nothing yet. Format: date, step, what was attempted, the exact error or mismatch, what was
left unchanged.
