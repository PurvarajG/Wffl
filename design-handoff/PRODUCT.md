# Product

<!-- impeccable:product-schema 1 -->

<!-- Inferred from README.md, website/index.html and Sources/Wffl on 2026-10-21 and the user's brief. Not interviewed beyond the visual-world and mockup-scope questions. Confirm before treating as final. -->

## Platform

web

(The website is `web`. The macOS app is native SwiftUI; app screens are delivered as mockups only, no app code changes.)

## Stack

Static HTML/CSS in `website/index.html`, deployed on Vercel (`website/vercel.json`). Keep it dependency-free.

## Users

People who sit in meetings and calls on a Mac (Zoom, Teams, Meet, FaceTime) and want a written record without sending audio to a cloud service. Includes people recording devotional talks (satsang) with Gujarati and Sanskrit terms, which the BAPS Whisper engine and the Devotional profile are built for.

## Product Purpose

Wffl records the microphone plus system audio, transcribes live on the Mac, labels speakers, cleans up the transcript, and writes a summary with a local model (Ollama by default). Success: a visitor downloads the DMG and records a first meeting with nothing leaving the machine.

## Positioning

Local-first, not local-optional: there is no account and no server in the loop, and the app works with the network off. Cloud providers exist but are opt-in and off by default.

## Operating Context

Apple Silicon Mac, macOS 15 or later. Models are downloaded once from inside the app (BAPS Whisper about 1.6 GB, Parakeet about 600 MB, Whisper ggml models, an Ollama model for summaries). Free and open source, MIT licensed, based on Meetily by Zackriya Solutions. Source and releases live at github.com/PurvarajG/Wffl.

## Capabilities and Constraints

- Mic + system audio capture (ScreenCaptureKit), live level meters, pause and resume.
- Live transcription: BAPS Whisper, Parakeet (English), whisper.cpp; 99 languages and translate-to-English via Whisper.
- Post-meeting clean-up with raw/cleaned toggle; speaker labeling (FluidAudio) with "Me" for the mic channel.
- Summaries from Ollama or any OpenAI-compatible self-hosted endpoint; template is editable.
- Local SQLite library with search, notes, Markdown export, copy, import and re-transcribe.
- Meeting auto-detect: Off, Nudge, or Auto-start.
- Constraints: no telemetry; do not claim speaker counts the diarizer did not identify; Parakeet and BAPS Whisper are English only.

## Brand Commitments

Name "Wffl". The logo is an eight-ellipse vertical waveform mark whose heights trace a W (revision 2026-10-21, proposed by the design pass after the user supplied waveform-logo references; the earlier single-stroke W is in git history and can be restored). Download and GitHub URLs stay stable. Copy voice is plain and calm. Live recording surfaces label speakers "Me" and "Them"; named speakers appear only after diarization.

## Evidence on Hand

No testimonials, customer logos, benchmarks or press. Do not fabricate any. Real demonstration material: the app itself (`dist/Wffl.app`), accuracy notes in `docs/fidelity-v3-ledger.md`. Demonstration transcripts on the site must be labeled as sample content.

## Product Principles

1. Privacy is a structural fact, shown through the product doing its job offline, not through badges.
2. Show the real workflow (record, transcript, summary) before describing it.
3. Never overclaim accuracy, speaker identification, or language support.
4. One primary action per surface: download the app, or start recording.

## Accessibility & Inclusion

WCAG AA contrast, visible keyboard focus, reduced-motion support on the site; the app is used with long transcripts so reading comfort matters.
