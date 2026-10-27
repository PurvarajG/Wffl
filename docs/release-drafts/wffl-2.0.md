<!-- DRAFT: Publish only after the v2.0.0 tag exists. The hero image below is an absolute raw.githubusercontent.com URL, so it only resolves once docs/assets/v2/hero-opening.webp is pushed to master.
Optionally drag final-release-v1.mp4 into the GitHub release editor to embed the full film.
Confirm before publishing: signed and notarized DMG attached to the release; the "How to update" and "Known issues" text still matches the build.
Candidates for Known issues, NOT verified, left out of the visible text:
- Ask matching: the code searches transcript lines, summaries, titles and notes, but I did not check whether it handles typos or word forms. Do not describe it beyond "search".
- Ollama models are stored outside Wffl's data folder, so they are not touched by an update, but this was not tested on a real upgrade.
- Settings carry over: they live in UserDefaults for com.purvaraj.wffl, the same bundle ID as v1.9.0 (verified in Support/Info.plist and Prefs.swift). Not yet tested on a real upgrade.
- Whether Liquid Glass shows on macOS 26 depends on the SDK stamp (see scripts/bundle.sh); check the shipped binary before saying so.
- Speaker labels and voice matching shipped in 1.x (Sources/Wffl/Diarization since July 2026); only the inspector is new, hence "as before".
-->

<p align="center">
  <img src="https://raw.githubusercontent.com/PurvarajG/Wffl/master/docs/assets/v2/hero-opening.webp" alt="The Wffl 2.0 opening film. Wffl 1.x plays on an old CRT television, the screen turns to static, a chat bubble admits the old app was a little boring, then the word Introducing and the Wffl waveform mark appear." width="100%">
</p>

A little boring, isn't it? **I agree. Let's change that.**

Wffl 2.0 is a new macOS interface built around search: one place to find what was said in any meeting, with your open action items beside it.

## What's new

**Ask and Action Items**

- **Ask.** Search all your meetings by a word, a name or a decision. Home also shows your recent meetings and open action items. A match opens the transcript at that line, with the recording cued.
- **Action Items.** Open items from your summaries collect in one list. Tick one off and the summary updates.

**The new window**

- **Light and dark.** Built for macOS 15 and later, with a sidebar for Ask, Action Items, Audio Files and your meetings by day.
- **A clearer meeting page.** Summary, Transcript and Notes in one window, with an inspector for speakers and recording details.

**Recording and playback**

- **Recording in the main window.** Pause, mute the mic and take timestamped notes without leaving the window.
- **Playback.** Play the recording from the meeting page, with a waveform read from the audio file.

**Speakers**

- **Speakers in the inspector.** The meeting page lists who spoke. As before, your microphone is Me, other voices on the call are labeled Speaker 1, Speaker 2, and a voice you rename once can be matched in later meetings.

**Privacy**

- Recording and transcription run locally. Hosted summary providers are optional and receive transcript text when you select one.

## What changed

- Home is now Ask. It replaces the old dashboard, and the separate meeting list, transcript and summary screens are now one meeting page.

## Requirements

- An Apple Silicon Mac
- macOS 15 or later

## How to update

Wffl does not update itself yet. Download the DMG below, open it, and drag Wffl into Applications to replace the old copy.

Your meetings, recordings, notes and settings stay where they were; Wffl keeps them outside the app. Models you downloaded are kept there too. If you used Meetily for macOS, Wffl adopts its old data folder the first time it opens.

For first-run setup (permissions, models, summaries), see the [README](https://github.com/PurvarajG/Wffl#first-run).

## Known issues

- There is no in-app updater. Update by downloading the new DMG.
- Parakeet and BAPS Whisper transcribe English only. For other languages or translation to English, Wffl uses Whisper.

Wffl is based on Meetily and includes open-source speech and audio components.
