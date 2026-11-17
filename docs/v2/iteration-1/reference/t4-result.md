# The fixed pipeline on the 2026-11-15 recording

Measured on 2026-11-16 with steps 1 to 4 applied to commit `5a201ae`, using the real BAPS
Whisper model and the headless mode:

```
.build/debug/Wffl --transcribe "<recordings>/0912DB0B-A414-417A-B051-B2EC0E94911D.wav" baps
```

The Parakeet check was **not** active, because Parakeet v3 is not installed on this Mac.
No transcript text is reproduced here; the recording is a private conversation.

## Result

| | Before (installed app, 2.1.1) | After (steps 1 to 4) |
|---|---|---|
| Audio in the recording | 1,367 s | 1,367 s |
| Seconds transcribed | 90 s (7%) | 1,266 s (93%) |
| Lines | 21 | 62 |
| Words | about 270 | 3,791 |
| Time to transcribe | about 12 s | 74 s |

The accounting line the app printed:

```
engine: baps-whisper · model: whisper-large-v3-turbo-baps · audio 1367 s · transcribed 1266 s · empty 6 (102 s) · failed 0 (0 s) · skipped 0 s
```

## What the numbers show

- **The fix works.** Fourteen times more of the conversation is transcribed.
- **Chunk lengths are as designed:** shortest 11 s, median 21 s, longest 28 s.
- **Speaking rate is plausible:** median 3.0 words per second. No line is suspiciously sparse.
- **All text is in Latin script.**

## What is still open

- **Six chunks came back empty (102 s, 7.5% of the audio).** They are not quieter than the
  chunks that were transcribed (their levels are 0.0049 to 0.0088 against a median of 0.0055
  for transcribed chunks). The model returned nothing for them. Their positions: 0-10 s,
  437-459 s, 1066-1086 s, 1230-1256 s, 1324-1334 s, 1354-1367 s.
- **One chunk (1280-1301 s) repeats a word four or more times in a row** and runs at 5.6 words
  per second, above the limit `BapsBackupRule` allows.

Both are exactly what the Parakeet check exists for: `BapsBackupRule.needsBackup` returns true
for an empty result and for a result that is too fast. With Parakeet installed, Parakeet reads
those seven chunks instead. That has not been measured yet. Step 5 measures it.

The pass bar for this recording is 95% transcribed. Without the Parakeet check the result is
93%, so the bar is **not yet met**.

## Also verified in this run

- The whole pipeline, from file to accounting line, runs end to end with the real model.
- Level normalisation does not make the model fail: 56 of 62 chunks of a recording at -45 dBFS
  were read.
- The first run of a new binary spends about 85 s compiling the model for the Neural Engine
  before transcription starts. That is expected and happens once per binary.
