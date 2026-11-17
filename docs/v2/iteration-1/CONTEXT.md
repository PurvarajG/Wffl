# Context: what failed, and how the pipeline is built

Read this once. The step files assume you have.

## What happened on 2026-11-15

A 22-minute in-person conversation was recorded on the laptop's built-in microphone. The
transcript held 21 lines covering 90 seconds. The app showed no warning and reported
"Transcript polished from the full recording."

The audio was captured correctly. The recording holds continuous speech for all 1,367 seconds.
It is quiet, about -45 dBFS, which is normal for people talking across a room from a laptop.

Five separate faults turned that recording into 90 seconds of text. All five were confirmed
against the code and against the recording itself.

| # | Fault | Where (at commit `5a201ae`) | Effect on this recording |
|---|---|---|---|
| 1 | A fixed loudness threshold treats quiet audio as silence and discards it before the model hears it. | `AudioChunker.swift`, `silenceRMS = 0.008` and `containsSpeech` | Dropped about 28% during recording |
| 2 | The pass that runs after Stop reads the file by averaging its two channels. With nothing on the system channel, that halves the microphone. | `AudioFileDecoder.swift:52` | The same threshold then dropped 91% |
| 3 | That pass replaces the live transcript whenever its own result is not empty. | `AppState.swift:777` | A transcript of about 980 s was replaced by one of 123 s |
| 4 | The only measure of lost speech runs for a different engine, uses the same threshold, and its formula is wrong. | `AppState.swift:724-735`, `TranscriptionCoverage.swift` | No warning was possible |
| 5 | The mixer pads the shorter of its two inputs with silence on every tick. | `MixBus.swift:75-98` | 2,509 gaps (173 s) inside the microphone track; the recording is 14% longer than real time |

A sixth fault cost the start of the conversation: Record refused to start until the model had
loaded, and macOS had cleared the model's compiled cache, so loading took minutes
(`RecorderController.swift:256-261`).

Signing, microphone permission and model speed were checked and are not causes.

## Why this kind of failure kept returning

Three reasons, each addressed by a rule in the README.

1. **"Speech" was defined as "louder than a fixed number" in five places.** Each number was
   tuned on loud audio. In a quiet room they all fail together, so the part that discards
   audio, the part that measures loss and the part that warns the user go blind at once.
2. **Nothing protected the audio.** Any stage could drop audio or text without recording that it
   had. The audit counted 26 such places.
3. **Every test used loud audio.** The chunker's tests used a tone 25 times louder than the
   threshold. The threshold was once "cleared" on a loud imported file and then marked "do not
   touch" in two later plans.

## The pipeline today

```
MicrophoneCapture ─┐
                   ├─> MixBus ──> RecordingFileWriter ──> <id>.wav   (48 kHz, 2 channels: mic, system)
SystemAudioCapture ┘     │
                         └─> LiveTranscriber ──> transcript_segments rows in SQLite
                               (AudioChunker cuts chunks; a ChunkReader reads each one)

After Stop:  AppState.retranscribe ──> ChunkedFileTranscriber ──> replaces the rows
             then SpeakerAttributor, then cleanup, then summary
```

| File | Role |
|---|---|
| `Sources/Wffl/Audio/RecorderController.swift` | Starts and stops a recording; owns the pieces below |
| `Sources/Wffl/Audio/MicrophoneCapture.swift`, `SystemAudioCapture.swift` | Deliver 48 kHz mono samples |
| `Sources/Wffl/Audio/MixBus.swift` | Every 200 ms, combines the two inputs; emits the two tracks (for the file) and their mix (for transcription) |
| `Sources/Wffl/Audio/ChannelActivityTracker.swift` | Records which input was audible, to label lines "mic" or "system" |
| `Sources/Wffl/Transcription/AudioChunker.swift` | Cuts the 16 kHz stream into chunks |
| `Sources/Wffl/Transcription/ChunkedTranscriber.swift` | `ChunkedLiveTranscriber` (while recording) and `ChunkedFileTranscriber` (from a file), for BAPS Whisper and Parakeet |
| `Sources/Wffl/Transcription/BapsWhisper.swift` | The BAPS Whisper model, its loader, and `BapsBackupRule` |
| `Sources/Wffl/Transcription/ParakeetLiveTranscriber.swift`, `ParakeetModelManager.swift` | Parakeet as a `ChunkReader` |
| `Sources/Wffl/Transcription/WhisperLiveTranscriber.swift`, `WhisperContext.swift`, `ModelManager.swift`, `VADModel.swift`, `Sources/CWhisper/`, `vendor/` | whisper.cpp, a third engine with its own live and file classes. Used only for other languages and translation. |
| `Sources/Wffl/Transcription/AudioFileDecoder.swift` | Reads any audio file as 16 kHz mono |
| `Sources/Wffl/AppState.swift` | App-level flow: start, stop, import, re-transcribe, cleanup, summary |
| `Sources/Wffl/Database/Database.swift` | SQLite. Meetings, segments, notes |
| `Sources/Wffl/Transcription/NormalizationPack.swift` | The spelling pack |
| `Sources/Wffl/Transcription/Vocabulary.swift`, `VocabularyGate.swift`, `TextFidelity.swift`, `Sources/Wffl/LLM/CleanupPipeline.swift` | Correction layers. Most are already switched off for BAPS Whisper. |

Three engines are selectable. `Prefs.effectiveEngine` returns `.baps` (the default, English
only), `.parakeet`, or `.whisper`.

## The pipeline after this iteration

```
mic + system ──> MixBus (one clock) ──> <id>.wav            always, no model involved
                     │
                     └─> AudioChunker ──> ChunkStep.run ──> transcript row
                          cuts at pauses,   normalises level,
                          never discards    calls the engine,
                                            counts the result
                                                 │
                                                 └─> TranscriptionStats ──> the meeting's note
```

After Stop, nothing more is transcribed if the live pass covered the recording. If it did not,
because no model was loaded or a chunk failed, the same function runs over the file.

## Terms used in the steps

| Term | Meaning |
|---|---|
| Chunk | A piece of audio, 10 to 28 seconds, handed to the model in one call |
| ChunkReader | A function that takes a chunk and returns a line of text, or nothing. BAPS Whisper and Parakeet each provide one. |
| Live pass | Transcription while recording |
| File pass | Transcription from a saved audio file |
| dBFS | Loudness relative to the loudest a file can hold. 0 is the maximum; -45 is quiet. |
| RMS | A measure of loudness: the average size of the samples. 0.008 is about -42 dBFS. |
| Digital silence | Samples that are exactly zero. A muted or disconnected input produces this. Quiet speech does not. |
| The note | The `transcription_note` column of a meeting, shown in the app as "How it was transcribed" |
| The Parakeet check | `BapsBackupRule`: Parakeet reads a chunk when BAPS Whisper's text looks wrong |

## Facts about this Mac that the steps rely on

- The app's data is in `~/Library/Application Support/Wffl/`: `wffl.sqlite` and `recordings/`.
- The failing recording is `recordings/0912DB0B-A414-417A-B051-B2EC0E94911D.wav`. It is a
  private conversation. Analyse it on this Mac only. Do not upload it, and do not paste its
  text into any document or commit.
- BAPS Whisper is downloaded. Parakeet v3, which the Parakeet check needs, is **not**
  installed; only an older v2 from another app is on disk. Step 5 installs it.
- The model card for BAPS Whisper is at
  `~/Documents/PROJECTS/atlas/docs/baps-whisper-model-card.md`. It reports a 7.3% word error
  rate on 207 held-out clips, tested on clean recordings, not on a room microphone.
- The app has a headless mode: `Wffl --transcribe <audio-file> baps` prints a transcript and
  exits. Step 5 uses it.
- The installed app at `/Applications/Wffl.app` is version 2.1.1 and has the same pipeline code
  as commit `5a201ae`.

## Left for iteration 2

Do not do these in iteration 1. They are recorded here so they are not lost.

**Speakers in a room, and transcribing each channel separately.** The microphone and system
audio are mixed before transcription, and the microphone is assumed to be one person. In a
room it is several. `AudioFileDecoder.decodeStereoTracks` already reads the two channels
separately and is used only for speaker labels.

**"Me" and "Them" labels at any volume.** `ChannelActivityTracker.swift:18` marks a channel as
speaking when its level is above 0.01. For a quiet room that is almost never true. A design
that needs no fixed level: for each line, compare the energy on the two channels over that
line's time span, and label it by whichever is at least four times the other. This needs the
tracker to store levels instead of true/false, and to keep reading old sidecar files.

**The mute monitor.** `RecorderController.swift` starts `InputMuteMonitor` once, on the device
chosen at the start. If the microphone falls back to another device, the monitor is not
restarted, so a stale "muted" state can drop the microphone for the rest of a recording.

**Sleep and wake.** Nothing observes them. A capture stream that dies across sleep is reported
for system audio after step 4, but not restarted.

**The 60-second silence warning.** `RecordingHealth` in `RecorderController.swift` warns when
the microphone stays under 0.01 for a minute and points the user at Privacy settings. In a
quiet room that message is wrong. The exact-zero check beside it is the real test for a dead
or unauthorised microphone.

**A newer model.** The BAPS Whisper build Wffl downloads is Atlas's 2026-10-07 model (558
training clips). Atlas has since promoted a checkpoint trained on 894 clips with a lower error
rate, which has not been converted and published for Wffl. Atlas also measured two faults on
long recordings: a run of commas after `ke,`, and stopping a clip a sentence early.

**Chunk length.** The chunker cuts at a pause once a chunk passes 10 s, up to 28 s. On Atlas's
held-out clips (each 30 s or less) it cut 132 of 207 in two, and the word error rate was 7.6%
against Atlas's 7.3% reading each clip whole; the gap is widest on mostly-Gujarati clips. The
model was trained on clips of up to 30 s. Try a longer minimum chunk, and up to 30 s, and re-run
step 5's check E.

**Model downloads.** No hash or pinned revision. The note cannot say which checkpoint ran.

**The spelling pack on transcript rows.** It is applied in the cleaned view only.

**The backup label.** `BapsChunkReader.make` hides a failure to build the Parakeet check, so the
note can say "(+parakeet backup)" when the check is not running.
