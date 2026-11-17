# Step 5: prove it on real audio

**Rules served:** all five. This is the step that says whether iteration 1 worked.
**Checked in advance:** partly. Check A below was run once without the Parakeet check; the
result is in [../reference/t4-result.md](../reference/t4-result.md). The other checks have not
been run.
**Owner approval needed:** no, but two checks need the owner in person (marked **Owner**).

This step changes code only if a check fails, and then only as "If a check fails" allows.

## Before you start

- [ ] Steps 1 to 4 are committed and `swift test` passes.
- [ ] Read [../reference/t4-result.md](../reference/t4-result.md).

## Preparation: install the Parakeet check (**Owner**)

BAPS Whisper's safety net needs Parakeet v3, which is not on this Mac. It is a download of
about 600 MB.

1. Open Wffl, then Settings, then Transcription.
2. Download Parakeet.
3. Wait until it shows as ready.

Confirm from a terminal:

```bash
ls ~/Library/Application\ Support/FluidAudio/Models/ | grep "parakeet-tdt-0.6b-v3"
```

Expect: one line. If there is none, the checks below still run, but without the safety net,
and check A will repeat the 93% already recorded.

## Check A: the recording that failed

Build, then transcribe the recording with the headless mode. The transcript goes to a file
outside the repository, because it is a private conversation.

```bash
swift build 2>&1 | grep -E " error|Build complete"
```

```bash
mkdir -p ~/wffl-checks && .build/debug/Wffl --transcribe ~/Library/Application\ Support/Wffl/recordings/0912DB0B-A414-417A-B051-B2EC0E94911D.wav baps > ~/wffl-checks/nov15.txt 2> ~/wffl-checks/nov15.log
```

The first run of a new build takes one to three minutes before it starts, while macOS
compiles the model. Then:

```bash
grep "engine: baps-whisper" ~/wffl-checks/nov15.log
```

**Pass when all three hold:**

| Measure | Bar | Without the Parakeet check (2026-11-16) |
|---|---|---|
| `transcribed` seconds | at least 1,299 (95% of 1,367) | 1,266 |
| `failed` chunks | 0 | 0 |
| The line starts with `engine:`, not `Incomplete` | yes | yes |

Also confirm the log's first line says `+ Parakeet backup`, not `(no Parakeet backup)`.

## Check B: Gujarati terms (**Owner**)

Only the owner knows which Gujarati and Sanskrit words were spoken in that conversation.

1. The owner writes 10 to 20 of them, one per line, in their canonical spelling, in
   `~/wffl-checks/terms.txt`. For example `Shastriji Maharaj`.
2. Count how often each appears:
   ```bash
   while read -r term; do printf "%s: " "$term"; grep -o -i "$term" ~/wffl-checks/nov15.txt | wc -l; done < ~/wffl-checks/terms.txt
   ```
3. The owner reads `~/wffl-checks/nov15.txt` and notes any of those words written another way.

**Pass when** at least 9 in 10 occurrences of the listed terms are in the canonical spelling.

If it fails, do not add a correction layer. Two things are allowed:

- Add the misspelling as an alias in the spelling pack (`NormalizationPack`), when the same
  wrong spelling occurs repeatedly. That is what the pack is for.
- Record the failure in STATUS.md as a model-quality finding for Atlas. The model card says
  the model was tested on clean recordings, not a room microphone, so weaker results on
  far-field speech would be a training-data question, not a pipeline one.

## Check C: an independent word count

A different model, stock Whisper large-v3, transcribes the same recording. It is not expected
to spell Gujarati words well; this check compares only how much was heard.

```bash
ffmpeg -y -i ~/Library/Application\ Support/Wffl/recordings/0912DB0B-A414-417A-B051-B2EC0E94911D.wav -ac 1 -ar 16000 ~/wffl-checks/nov15-16k.wav
```

```bash
cd ~/wffl-checks && uv run --with mlx-whisper python -I -c "import mlx_whisper; r = mlx_whisper.transcribe('nov15-16k.wav', path_or_hf_repo='mlx-community/whisper-large-v3-mlx', language='en', condition_on_previous_text=False); print(len(r['text'].split()))"
```

Then count Wffl's words:

```bash
sed 's/^\[[^]]*\] //' ~/wffl-checks/nov15.txt | wc -w
```

**Pass when** Wffl's word count is at least 85% of the independent count. This check exists to
catch Wffl hearing less. Wffl having more words is not a failure: the independent run reads
halved, un-raised audio and can drop or garble stretches itself. If Wffl is more than 15%
higher, the owner listens to the stretches where only Wffl has text and decides.

On 2026-11-17 Wffl had 3,888 words and stock large-v3 3,073. The owner listened to the two
stretches where only Wffl had text (7:17 and 22:04) and confirmed both were real speech. At
22:04 large-v3 had written a 30-second run of "Mmmm".

Note that `ffmpeg -ac 1` averages the two channels. That halves the microphone but does not
affect a model that has no loudness gate.

## Check D: a silent room (**Owner**)

With quiet audio now raised before the model reads it, confirm an empty room does not produce
invented text.

1. Build and sign the app (see "Building the app" below) and open it.
2. Record two minutes in a silent room. Say nothing.
3. Stop, and open the meeting.

**Pass when** the transcript has at most ten words in total. The note will probably begin
"Incomplete", because most chunks come back empty; for a silent room that is correct.

## Check E: the model's own test clips

This proves the pipeline changes did not cost accuracy on the audio the model was measured on.

The 207 held-out clips and their reference transcripts belong to the Atlas project at
`~/Documents/PROJECTS/atlas`. Found on 2026-11-17:

| What | Where, under `~/Documents/PROJECTS/atlas` |
|---|---|
| The 207 clips (`.wav`) | `build/gemini/full-11h-test/clips/` |
| Reference transcripts (`reference` field) | `build/gemini/full-11h/clips/<id>.json` |
| Which talks are held out | `build/turbo-ft/full-11h/split.json` (`test`) |
| The scorer behind the model card | `scripts/dictation/score_fair.py` |
| Atlas's own run, the card's 7.3% | `build/gemini/full-11h-test/ours-run-baps.json` |

Do not change anything in Atlas. Its reference folder also holds `*.judge.json` and
`*.cand.json` files without an `id`, which make the scorer fail, so link only the plain
reference files into a scratch folder (`$S` is any scratch directory):

```bash
A=~/Documents/PROJECTS/atlas; S=~/wffl-checks/checkE; mkdir -p $S/refs/clips $S/out
for f in $A/build/gemini/full-11h/clips/*.json; do case $f in *.cand.json|*.judge.json) ;; *) ln -sf "$f" $S/refs/clips/;; esac; done
```

Transcribe every clip (about 4 s each, 14 minutes in all):

```bash
for f in $A/build/gemini/full-11h-test/clips/*.wav; do id=$(basename "$f" .wav); .build/debug/Wffl --transcribe "$f" baps > $S/out/$id.txt 2> $S/out/$id.log; done
```

Turn the outputs into Atlas's run format, `{"clips": [{"id": ..., "stitched": <the clip's lines joined, timestamps removed>}]}`,
saved as `$S/wffl-run.json`, then score it beside Atlas's own run:

```bash
python3 -I $A/scripts/dictation/score_fair.py --folder $S/refs --split $A/build/turbo-ft/full-11h/split.json $A/build/gemini/full-11h-test/ours-run-baps.json $S/wffl-run.json
```

The `ours-run-baps` row must read 7.3%. If it does not, the references have changed since
the card was written: stop and record that, rather than comparing.

**Pass when** the `wffl-run` row's "all" figure is no worse than 8.0%.

On 2026-11-17 it was 7.6%. See STATUS.md for the breakdown.

## Check F: recover the meeting (**Owner**)

In the built app, open the 2026-11-15 meeting and choose Re-transcribe.

**Pass when** the transcript now has about 60 lines instead of 21, and the note shows the
accounting line. The short gaps the old mixer inserted into that file are permanent, so a
word may be clipped here and there.

## Building the app

Checks D and F, and the manual check in step 3, need the real app, signed so that macOS lets
it use the microphone. Find the signing identity:

```bash
security find-identity -v -p codesigning
```

Then build, putting the quoted name from that output in place of the placeholder:

```bash
WFFL_SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" scripts/bundle.sh
```

The app is written to `~/Applications/Wffl.app` (set `WFFL_APP_PATH` to change that). The
copy in `/Applications` is left alone. Quit any running Wffl before opening the new one, and
open it from `~/Applications` so you are not testing the old build. If
`bundle.sh` stops with a message about a missing identity, stop and report; never sign
ad hoc, because macOS then revokes the microphone permission.

## If a check fails

Change one thing, re-run the failing check and `swift test`, and record the before and after
numbers in STATUS.md. The allowed changes, in this order:

1. **Check A short of 95%, with the Parakeet check active.** In `BapsWhisper.swift`, in
   `BapsEngine.transcribe`, WhisperKit skips a chunk it believes is silent. Add
   `noSpeechThreshold: nil` to the `DecodingOptions(...)` call, so the decision is left to
   `BapsBackupRule`. Re-run checks A and D together: this change must not make the silent room
   produce text.
2. **Check D produces invented text.** Lower `LevelNormalizer.maxGain` in
   `ChunkedTranscriber.swift` from 32 to 16, so room hiss is raised less. Re-run checks A and D.
3. **Known model faults.** Atlas measured two on long recordings: after `ke,` the model can
   print commas for the rest of a clip, and it sometimes stops a clip a sentence early. If
   check B or the owner's reading shows these, record them for Atlas. Do not fix them here.

Not allowed: any new loudness threshold, any text correction by a language model, any fuzzy
matching of words, any second transcription pass that replaces the first.

If a check still fails after the allowed changes, stop. Write the numbers in STATUS.md. The
owner decides what happens next.

## Done when

- [ ] Checks A, C pass, or their failure is recorded with numbers.
- [ ] Checks B, D, F are done by the owner, or marked "waiting for owner".
- [ ] Check E passes, or is marked "outstanding: needs Atlas".
- [ ] STATUS.md holds every number.

## Commit

Only if code changed under "If a check fails":

```
fix(pipeline): calibrate against real recordings

<one line per change: what was changed, the number before, the number after>
```
