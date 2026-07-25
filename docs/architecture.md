# Architecture invariants

Rules that are load-bearing but not obvious from any single file. Each one has
been violated at least once and cost a debugging session. Check this list before
changing audio capture, diarization, or background processing.

## Recording is two-track, and the track layout is a contract

Recordings are 48 kHz **stereo** WAV where the two channels are not left/right
audio — they are separate sources:

| Channel | Source |
|---|---|
| 0 | microphone (the local user) |
| 1 | system audio (remote participants) |

`MixBus` produces `micTrack` and `sysTrack` separately
([MixBus.swift:90](../Sources/Wffl/Audio/MixBus.swift:90)) and
`RecordingFileWriter` persists them as the two channels of one file
([RecorderController.swift:53](../Sources/Wffl/Audio/RecorderController.swift:53)).

Consequences:

- **Never read only channel 0 when decoding.** It looks like a mono downmix and
  silently discards every remote participant. `AudioFileDecoder` explicitly
  mixes *all* channels for this reason
  ([AudioFileDecoder.swift:44](../Sources/Wffl/Transcription/AudioFileDecoder.swift:44)),
  and a regression test guards it.
- A dead microphone yields a file that is still perfectly valid — channel 0 is
  simply all zeros. Nothing downstream will report an error. This is why
  microphone health is detected at capture time (below) rather than inferred
  later.

### The WAV writer owns its own serial queue

`RecordingFileWriter` holds `AVAudioFile` on one private `DispatchQueue`
([RecorderController.swift:50](../Sources/Wffl/Audio/RecorderController.swift:50)).
MixBus invokes callbacks off the main actor, so routing appends through an
unstructured `Task { @MainActor in try? … }` loses write ordering under UI load
and swallows disk-full errors. Do not reintroduce a main-actor hop, and do not
discard the error from `write`.

### Microphone silence is judged per channel, never in aggregate

A single silence counter reset by *either* channel cannot detect a dead mic,
because remote audio keeps resetting it — a 30-minute meeting recorded a fully
silent microphone without one warning. `RecordingHealth` therefore tracks
`micSilentSeconds` independently
([RecorderController.swift:16](../Sources/Wffl/Audio/RecorderController.swift:16)).

Related: macOS binds the microphone TCC grant to the app's **code signature**.
An ad-hoc-signed rebuild gets a new cdhash, the grant silently stops matching,
and CoreAudio delivers all-zero buffers with no error at all. This is why
`scripts/bundle.sh` hard-fails rather than falling back to ad-hoc signing —
never re-add that fallback.

## Only the system track is diarized

Microphone segments are always the local user and are assigned `Speaker.meId`
directly. Diarization runs on `system`/`mixed` segments only
([SpeakerAttributor.swift:75](../Sources/Wffl/Diarization/SpeakerAttributor.swift:75)).

Sending mic audio through the diarizer would let the local speaker be clustered
as an anonymous "Speaker N" and, worse, be matched into the cross-meeting
speaker library as a remote participant.

Within one meeting, cluster→speaker assignment is **one-to-one**: two distinct
clusters must never resolve to the same stored speaker, or two real people get
merged into one.

## Summary and cleanup work is app-owned, not view-owned

Summary and cleanup run as `Task.detached` stored on `AppState`
([AppState.swift:330](../Sources/Wffl/AppState.swift:330),
[AppState.swift:380](../Sources/Wffl/AppState.swift:380)).

They are deliberately **not** attached to a SwiftUI view or a navigation tab. If
they were, switching tabs would cancel in-flight LLM work. Tab switching is not,
and never was, the cause of a lost summary — do not "fix" it by moving this work
into a view.

`AppState` is `@MainActor`; these tasks must stay detached.

## Interrupted jobs are reconciled in one place

A crash or force-quit leaves rows in `summaries` / `cleaned_transcripts` stuck
at `status='generating'`, which the UI renders as an eternal spinner. The sweep
that marks them failed lives in `Database.reconcileInterruptedJobs()` and runs
at database open
([Database.swift:61](../Sources/Wffl/Database/Database.swift:61)).

Do not duplicate this in `AppState.init` — running it twice is harmless today
but hides where the behavior actually lives.

## Secrets never touch UserDefaults

LLM API keys live in the Keychain via `KeychainStore`
([KeychainStore.swift](../Sources/Wffl/Support/KeychainStore.swift)), not
`@AppStorage`. UserDefaults writes plaintext into a preferences plist readable
by any process running as the user and captured by every backup of the home
folder. Settings uses `KeychainSecureField`, not an `@AppStorage` binding.

The custom LLM endpoint sends the transcript *and* an `Authorization: Bearer`
header to a user-supplied URL, so `EndpointPolicy` requires https for anything
that is not loopback
([EndpointPolicy.swift](../Sources/Wffl/Support/EndpointPolicy.swift)).
Loopback keeps plain http because self-hosted llama.cpp / vLLM / LM Studio have
no TLS.

## Releases

See [release-signing.md](release-signing.md) for signing/notarization setup and
[RELEASING.md](RELEASING.md) for the release process. The website's download
button resolves to `releases/latest/download/Wffl.dmg`, so **it 404s until a
release workflow run actually publishes** — a green build is not enough.

The `.dmg` must be notarized in its own right, not merely built around a
notarized `.app`. A ticket for the app is not a ticket for the image, and
stapling an unsubmitted image fails with `CloudKit query … Record not found`
(error 65).
