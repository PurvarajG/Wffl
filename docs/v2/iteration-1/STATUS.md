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
| 3 One pass | done 2026-11-17; quit check passes, "before the model loads" not tested | `e84075b` | 332 tests, 3 skipped, 0 failures. "still loading": 0 lines. Automatic re-transcribe call sites: 1. Quit mid-recording (signed app, driven by script, 2026-11-17): the WAV was finalised (36.8 s, 2 channels, 48 kHz), the meeting row was saved with its duration, and on relaunch the meeting was transcribed within 5 s with an accounting note. Press Record before the model loads: not tested, because the model loads in about a second at launch now. |
| 4 Visibility | done 2026-11-17 | `7d28001` | 332 tests, 3 skipped, 0 failures. `onStopped` assigned: 1 line. |
| 5 Measure | in progress: A, C, D and E pass; B and F waiting for owner | | See the table below |
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
| C: word count against stock large-v3 | at least 85% of the independent count (revised 2026-11-17, was "within 15%") | Wffl 3,888 · stock large-v3 3,073 (2026-11-17): Wffl is 126%. | yes |
| D: silent room, two minutes | at most 10 words | 0 words on every file: two minutes of generated room noise at -55, -62, -73 and -78 dBFS, plus digital silence (headless). 0 words on two quiet-room recordings in the signed app (37 s and 20 s, microphone at -48 dBFS). | yes (see notes) |
| E: Atlas held-out clips, word error rate | at most 8.0% | 7.6% on 207 clips (2026-11-17), Atlas's `score_fair.py`. Same scorer gives Atlas 7.3%. | yes |
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
- Per step 5's rule, nothing was changed in code.
- **Owner, 2026-11-17: listened to both stretches; both are real speech.** At 22:04 large-v3 had written a 30-second
  run of "Mmmm", so its count there was its own failure. The owner's decision: the bar fails only when Wffl hears
  less. Step 5's check C now says so.

Notes from check E (2026-11-17):

- Word error rate by Gujarati share, Wffl against BAPS Whisper as Atlas runs it (both with the Parakeet check):

  | | All | English only | A few Gujarati words | Mixed | Mostly Gujarati (9 clips) |
  |---|---|---|---|---|---|
  | Atlas | 7.3% | 3.9% | 6.3% | 10.8% | 30.4% |
  | Wffl | 7.6% | 4.0% | 6.2% | 11.5% | 34.6% |

- Accounting: 5,174 s of audio, 5,132 s transcribed, 0 failed, 0 skipped. Parakeet read a chunk in 6 clips.
- Three clips are marked "Incomplete": the first clip of three talks (006, 018, 020), each with one empty chunk of
  10 to 12 s. These are talk openings, where the chants are. An empty chunk there is expected, but it means a
  recording that starts with chanting will show "Parts of this recording were not transcribed."
- Where the gap comes from, probably: Wffl's chunker cut 132 of the 207 clips (each 30 s or less) into two chunks,
  because it cuts at a pause after 10 s once it is near 28 s. Atlas reads each clip whole. Of the 9 clips more than 5
  points worse in Wffl, the ones checked were all cut in two. This is within the bar, so nothing was changed. For
  iteration 2: let the chunker keep a chunk whole up to 30 s, the model's trained length.
- The Atlas scorer fails on `build/gemini/full-11h/clips/` as it is now, because later `*.judge.json` and
  `*.cand.json` files there have no `id`. Step 5's check E describes the workaround; Atlas was not changed.

Notes from check D and step 3's quit check (2026-11-17, run by script):

- Not exactly the check as written: the two minutes were generated noise, read headless, and the real-room
  recordings in the app were shorter. For the noise files, Parakeet also read every chunk and returned nothing, so
  neither model invented text from noise raised by `LevelNormalizer`. Digital silence was counted as skipped, not
  empty. In the app's quiet-room recording, stock large-v3 found 4 words in 37 s (no-speech probability 0.64 to 0.77),
  which confirms the room was quiet.
- A silent recording shows as "Incomplete", as step 5 predicted.
- **Finding:** the app's `transcriptionEngine` preference was `parakeet`, so every recording in the app was being
  transcribed by Parakeet (English only, 14.0% on Atlas's clips) instead of BAPS Whisper (7.6%). It was set back
  with `defaults write com.purvaraj.wffl transcriptionEngine baps`. The next recording's note said
  `engine: baps-whisper ... (+parakeet backup)`. How it came to be `parakeet` is not known. It may have been chosen
  while installing Parakeet in Settings. For iteration 2: Parakeet is now BAPS Whisper's backup, so the Settings
  engine choice should not invite switching to it in order to download it.
- Two test meetings were left in the app (2026-11-17 at 19:17 and 19:19, 37 s and 20 s, no text). Delete them in the app.

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
