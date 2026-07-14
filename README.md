# Wffl

**Wffl** is a fully native Swift/SwiftUI meeting assistant for macOS — a rebuild based on
[Meetily](https://github.com/Zackriya-Solutions/meetily), the open-source, privacy-first AI
meeting assistant. Everything runs **100% on your Mac** with open-source models: no cloud,
no API costs, no data leaving the machine.

## Features

- **Record meetings** — microphone + system audio (ScreenCaptureKit) mixed with per-channel gain
  and soft-limiting, saved as WAV. Live level meters, pause/resume, mic-only fallback if
  screen-recording permission is missing.
- **Local transcription** — [whisper.cpp](https://github.com/ggml-org/whisper.cpp) v1.9.1
  (Metal + Accelerate, statically linked). Live silence-aligned chunked transcription while you
  record. In-app model manager downloads ggml Whisper models (tiny → large-v3-turbo) from
  Hugging Face. 99 languages + optional translate-to-English.
- **Transcript clean-up** — one click rewrites the raw timestamped Whisper output into readable,
  structured paragraphs with topic headings: punctuation and capitalization fixed, filler removed,
  timecodes preserved. Runs through the same local/self-hosted (or optional cloud) model as
  summaries; toggle between Raw and Cleaned views.
- **AI summaries with open-source models** — Ollama (default, local) or any self-hosted
  OpenAI-compatible endpoint (llama.cpp server, vLLM, LM Studio, LocalAI). Cloud providers
  (Anthropic, Groq, OpenRouter) are strictly optional. Map-reduce chunking for long transcripts.
- **Meetings library** — SQLite storage, search, notes per meeting, Markdown export,
  copy-to-clipboard.
- **Import & re-transcribe** — drop in any audio file, or re-run a meeting's recording through a
  different Whisper model.

## Build

Requires Xcode 15+ on Apple Silicon. whisper.cpp static libs are prebuilt in `vendor/lib`
(rebuild them from `vendor/whisper.cpp` with CMake if needed).

```bash
./scripts/bundle.sh release     # builds + assembles + signs dist/Wffl.app
open dist/Wffl.app
```

Headless self-test (no GUI):

```bash
./dist/Wffl.app/Contents/MacOS/Wffl --transcribe /path/to/audio.wav base.en
```

## Install (from the DMG)

Wffl.dmg is ad-hoc signed, not notarized — macOS Gatekeeper will flag it as
from an unidentified developer. To open it:

1. Open the DMG and drag `Wffl.app` into `/Applications`.
2. Right-click (or Control-click) `Wffl.app` → **Open** → confirm in the dialog.
   (Only needed once; after that it launches normally.)
3. If macOS still refuses, run `xattr -cr /Applications/Wffl.app` in Terminal.

## First run

1. Settings → Transcription → download a Whisper model (base.en is a good start;
   large-v3-turbo-q5_0 for best quality).
2. Install [Ollama](https://ollama.com) and `ollama pull llama3.2` for local summaries
   and transcript clean-up.
3. Grant Microphone (and optionally Screen & System Audio Recording) permission when prompted.

Upgrading from the app's previous identity (Meetily for macOS)? Wffl adopts the old
`~/Library/Application Support/MeetilyMac` data folder and preferences automatically on
first launch — meetings, recordings, and downloaded models all carry over.

## Architecture

```
Sources/Wffl/
  Audio/           MicrophoneCapture (AVAudioEngine) · SystemAudioCapture (ScreenCaptureKit)
                   MixBus (mix + limiter) · RecorderController · AudioDevices (CoreAudio)
  Transcription/   WhisperContext (C API wrapper) · WhisperLiveTranscriber (chunking)
                   ModelManager (HF downloads)
  LLM/             LLMClient (Ollama/Anthropic/Groq/OpenRouter/custom) · SummaryService
                   TranscriptCleanupService (LLM post-processing pass, timecode-preserving)
  Database/        SQLite (meetings · transcript_segments · summaries · cleaned_transcripts)
  Views/           SwiftUI: sidebar · detail (transcript/summary/notes) · settings · recording bar
Sources/CWhisper/  module map exposing whisper.h; links vendor/lib/*.a
```

MIT-licensed components. Based on [meetily.ai](https://meetily.ai) by Zackriya Solutions.
