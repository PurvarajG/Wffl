# Wffl setup study

A native SwiftUI study of first-run setup, built to feel like the same world as the opening film and the tour. Setup is one sentence, "Wffl turns speech into words on this Mac. It hears you, and them.", assembled by doing it. Each clause belongs to one step: it flies in letter by letter, waits dim, and turns to ink as the step completes. The Wffl mark on the right is written by the download, breathes with your voice, opens into Me and Them lanes, and then becomes the lockup before Ask opens through a circle.

## Open, build, render

```sh
open "design-handoff/startup-setup/Wffl Setup Study.app"
zsh design-handoff/startup-setup/build.sh             # rebuild
zsh design-handoff/startup-setup/build.sh --render    # rebuild, then write keyframes
```

`--render` writes 24 PNGs at 2x into `renders/` (1100 by 700) and `renders/compact/` (900 by 560). Every frame is the real stage drawn at an exact time, so the stills match the live app. The binary also takes `--compact` (smaller window), `--reduce-motion` (force Reduced Motion) and `--render <dir>` (keyframes only, no window).

Requires macOS 14 and the Xcode command line tools. No packages.

## Controls

- Return or Enter: the main button of the current step
- Right arrow: next. Left arrow: back
- Escape: skip the ending
- Command-R: replay from the start
- Option-click a button: simulate the failure or denial for that action (a failing download, a refused microphone or system audio prompt)
- Study menu: Replay, Simulate failures (Command-Shift-F, the same as holding Option), and Jump to Download, Download failed, Microphone, Microphone denied, System audio, System audio denied, Ending

Reduce Motion follows the system setting. It swaps travel, flight, blur, breathing and overshoot for short fades and keeps every state legible.

## What is simulated

- The model download: about 7 seconds for 1.6 GB, with Pause, Cancel, a failure at 42%, and Try again.
- The macOS permission prompts: an answer arrives 0.9 s after Allow. Denied states show the System Settings path; Open System Settings and Check again simply grant after a moment.
- The microphone level and the second voice: a deterministic function of time, not audio.
- Nothing is written to disk, nothing is persisted, and nothing talks to the real app.

## What production would need

- A real model download with resume, checksum and a disk-space check before it starts, plus a clear failure when the network or disk runs out.
- Real permission states from `AVCaptureDevice` for the microphone and ScreenCaptureKit for system audio, including the denied-then-granted-in-Settings path, re-checked when the app becomes active.
- Persistence of what is finished, so setup resumes and "Set up later" can be reopened from Settings.
- Wiring into the welcome journey so the iris opens onto the live Ask window instead of a still image.
- Real input levels driving the mark and the Me and Them lanes.
