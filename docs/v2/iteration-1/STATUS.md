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
| 5 Measure | in progress: A passes, C fails as written (owner to decide) | | See the table below |
| 6 Remove whisper.cpp | waiting for owner | | |
| 7 Remove guessing layers | waiting for owner | | |
| 8 Docs and release | not started | | |

## Step 5 measurements

| Check | Bar | Result | Pass? |
|---|---|---|---|
| A: 2026-11-15 recording, seconds transcribed | at least 1,299 of 1,367 | 1,367 (2026-11-17, Parakeet check active; 68 lines, 3,888 words, 95 s). Without the check on 2026-11-16: 1,266. | yes |
| A: failed chunks | 0 | 0; empty 0; skipped 0 | yes |
| A: Parakeet check active | yes | yes: log says "+ Parakeet backup". Parakeet read 7 chunks (0:00, 7:17, 17:46, 20:30, 21:20, 22:04, 22:34). | yes |
| B: Gujarati terms in canonical spelling | at least 90% | waiting for owner | |
| C: word count against stock large-v3 | within 15% | Wffl 3,888 · stock large-v3 3,073 (2026-11-17). Wffl is 26.5% higher. | **no, as written**: see the notes below |
| D: silent room, two minutes | at most 10 words | waiting for owner | |
| E: Atlas held-out clips, word error rate | at most 8.0% | | |
| F: 2026-11-15 meeting re-transcribed in the app | about 60 lines | waiting for owner | |

Notes from check A (2026-11-17):

- No uncovered stretch anywhere in the recording. No line over BapsBackupRule's speed limit, and no non-Latin script.
- The 7 chunks Parakeet read are English-only readings, so Gujarati words in them (about 2 minutes of audio) will be
  spelled as English. Check B should look at those times in particular.
- One line, at 18:53, repeats the Gujarati word "kem" four times in a row. It is under the speed limit, so it may be
  real speech. Owner to confirm by listening during check B.

Notes from check C (2026-11-17):

- The bar fails in the direction of Wffl hearing more, not less. Stock large-v3 transcribed only 1,195 s of segments
  and ran on `ffmpeg -ac 1` audio, which halves the microphone, with no level raising.
- In the chunks BAPS Whisper read, Wffl has about 16% more words, and a median 72% of Wffl's distinct words in each
  chunk also appear in large-v3's text for the same time. That fits the same speech, heard more completely, with
  Gujarati words spelled differently.
- Two Parakeet chunks have text where both Whisper models heard nothing: 7:17-7:39 (46 words) and 22:04-22:14
  (26 words), 0% shared words. These may be real speech, or Parakeet inventing words from room noise.
  **Owner: listen to those two stretches.** If they are invented, that is a reason to refine BapsBackupRule so an
  empty BAPS result is kept empty when Parakeet's reading is suspect; it is not a reason to change the chunker.
- Per step 5's rule, nothing was changed. The owner decides whether the bar should only fail when Wffl hears less.

Calibration changes made in step 5 (what, number before, number after):

- none needed for check A

## Release

| | |
|---|---|
| Five-minute room recording, accounting line | |
| Version released | |

## Stops

Nothing yet. Format: date, step, what was attempted, the exact error or mismatch, what was
left unchanged.
