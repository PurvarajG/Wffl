# Meetily for macOS (Native Swift)

A fully native Swift/SwiftUI rebuild of [Meetily](https://github.com/Zackriya-Solutions/meetily) —
the open-source, privacy-first AI meeting assistant. Everything runs **100% on your Mac** with
open-source models: no cloud, no API costs, no data leaving the machine.

## Features

- **Record meetings** — microphone + system audio (ScreenCaptureKit) mixed with per-channel gain
  and soft-limiting, saved as WAV. Live level meters, pause/resume, mic-only fallback if
  screen-recording permission is missing.
- **Local transcription** — [whisper.cpp](https://github.com/ggml-org/whisper.cpp) v1.9.1
  (Metal + Accelerate, statically linked). Live silence-aligned chunked transcription while you
  record. In-app model manager downloads ggml Whisper models (tiny → large-v3-turbo) from
  Hugging Face. 99 languages + optional translate-to-English.
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
./scripts/bundle.sh release     # builds + assembles + signs dist/Meetily.app
open dist/Meetily.app
```

Headless self-test (no GUI):

```bash
./dist/Meetily.app/Contents/MacOS/Meetily --transcribe /path/to/audio.wav base.en
```

## First run

1. Settings → Transcription → download a Whisper model (base.en is a good start;
   large-v3-turbo-q5_0 for best quality).
2. Install [Ollama](https://ollama.com) and `ollama pull llama3.2` for local summaries.
3. Grant Microphone (and optionally Screen & System Audio Recording) permission when prompted.

## Architecture

```
Sources/Meetily/
  Audio/           MicrophoneCapture (AVAudioEngine) · SystemAudioCapture (ScreenCaptureKit)
                   MixBus (mix + limiter) · RecorderController · AudioDevices (CoreAudio)
  Transcription/   WhisperContext (C API wrapper) · WhisperLiveTranscriber (chunking)
                   ModelManager (HF downloads)
  LLM/             LLMClient (Ollama/Anthropic/Groq/OpenRouter/custom) · SummaryService
  Database/        SQLite (meetings · transcript_segments · summaries)
  Views/           SwiftUI: sidebar · detail (transcript/summary/notes) · settings · recording bar
Sources/CWhisper/  module map exposing whisper.h; links vendor/lib/*.a
```

MIT-licensed components. Original product: [meetily.ai](https://meetily.ai) by Zackriya Solutions.
