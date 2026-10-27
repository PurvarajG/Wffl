# Wffl 2.1: setup inside the update film, and a real updater

Planned 27 October 2026. Decisions confirmed by the owner:

- **Order.** Opening film, then the feature tour (Same meetings, Voice, Voices, Minutes, Your Mac), then **setup**, then the falling cubes that reveal live Ask.
- **Forced once for everyone.** A new campaign. Returning users (including those who acknowledged 2.0) get film, tour, setup, cubes. New installs get setup alone, then the cubes. A user's mode is decided once per campaign and stored, so a new user who interrupts is not later treated as returning.
- **Real states, done shows done.** Setup reads the selected transcription engine, microphone and Screen & System Audio Recording permission. Finished clauses arrive already inked; only missing steps ask for anything.
- **Handover.** After Finish setup (or Set up later), the finished setup page itself is the face that breaks into the cubes. No lockup and no iris in production (the opening already has the lockup).
- **Updates.** Sparkle 2: Check for Updates in the app menu; a Settings section for automatic checks, check interval and automatic download; appcast and EdDSA signing in the release workflow.

Version: 2.1.0, build 22.

## Work packages

Built in three packages; A and C run in parallel in their own worktrees, B builds on A.

### A. Setup module (new files only)

`Sources/Wffl/Welcome/Setup/`, ported from the approved study in `design-handoff/startup-setup/` (SetupContract, AssemblingSentence, MarkInstrument, SetupStage). Keep the motion, layout and copy rules exactly; change only what production needs:

- **Namespacing.** Every type gets a `Setup` prefix or nests in `enum Setup`, so nothing collides with the app (`Color(hex:)`, `Palette`, `Motion`, `Voice` and so on). Fonts via `AppFonts.sans` / `AppFonts.mono`; colours from the study's palette as private constants or `Theme` where identical.
- **Real observation instead of simulation.** `SetupCore` keeps its pure-function-of-time design, but its inputs are observed: `mutating func observe(_ o: SetupObservation, at t: Double)` records each change time so ramps (ink sweep, glow, dots, lanes) ease exactly as in the study. The download closed form, failure arming and `Voice` speech simulation are removed from production paths.

  ```swift
  enum SetupEngineStatus: Equatable { case notStarted, downloading(Double?), preparing, ready, failed(String) }
  enum SetupAccess: Equatable { case notAsked, asking, granted, denied, later }
  struct SetupObservation: Equatable {
      var engineName: String        // "BAPS Whisper", "Parakeet", "Whisper large-v3-turbo"
      var engineSize: String        // "about 1.6 GB", "about 600 MB"
      var engineBytes: Double?      // total bytes when known, for "0.61 of 1.6 GB"
      var canCancel: Bool           // only the ggml Whisper download can be cancelled
      var engine: SetupEngineStatus
      var mic: SetupAccess
      var sys: SetupAccess
  }
  ```
- **Steps and copy (no em or en dashes, no kickers).**
  - Model, not started: "Download <name>, the model that writes your transcripts. It is <size> and runs on this Mac." Primary "Download model".
  - Downloading: same body; readout "38%" and "0.61 of 1.6 GB" (percent only when known; Parakeet shows "Downloading" without a number). Primary **Continue** (the download carries on in the background; the clause stays partly inked). Quiet "Cancel" only when `canCancel`.
  - Preparing (BAPS first load compiles for the Neural Engine): "Preparing <name> for this Mac. The first time takes a few minutes." Primary Continue.
  - Failed: "The download stopped: <short reason>. Check your network, then try again." Primary "Try again"; quiet "Set up later".
  - Ready: "<name> is downloaded and ready." Primary Continue.
  - Microphone not asked: "Wffl records your side of a call from the microphone. macOS will ask you to allow it." Primary "Allow microphone". Granted: "The microphone is on. Wffl can hear your side of a call." Denied or restricted: "Microphone access is off. Turn on Wffl in System Settings, under Privacy & Security, Microphone." Primary "Open System Settings"; quiet "Check again", "Continue without it".
  - System audio not asked: "Also record what plays on this Mac, so the other side of a call is in the transcript." Primary "Allow system audio"; quiet "Set up later". Granted: "System audio is on. Both sides of a call reach the transcript." Primary "Finish setup". Denied: "System audio access is off. Turn on Wffl in System Settings, under Privacy & Security, Screen & System Audio Recording. macOS may ask you to quit and reopen Wffl." Primary "Open System Settings"; quiet "Set up later".
  - Back is a quiet link on steps 2 and 3, and on step 1 only when `canBackOut` (the tour is behind it).
- **Completion rules.** Model is complete once it is downloading, preparing or ready (failed is passable through Set up later). Microphone is complete when granted or explicitly continued without. System audio is complete when granted or later. Finish setup appears on step 3 when granted; Set up later also finishes.
- **`SetupSession`** (`@MainActor final class`, `ObservableObject`): owns the reference clock, the core, and the live sources. It subscribes to `BapsModelManager.shared.$state`, `ParakeetModelManager.shared.$state`, `ModelManager.shared` (`$progress`, `$downloaded`, `$errors`) for the engine `Prefs.effectiveEngine` selects, and re-reads `AVCaptureDevice.authorizationStatus(for: .audio)` and `CGPreflightScreenCaptureAccess()` on `NSApplication.didBecomeActiveNotification` and after each request. `send(_:)` performs the real effect: start the engine's download; cancel (Whisper only); `AVCaptureDevice.requestAccess(for: .audio)`; `CGRequestScreenCaptureAccess()` then re-check for a few seconds (asking until then, denied if still off); open the privacy pane (`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone` / `Privacy_ScreenCapture`, as AskHome does); navigation actions go to the core. `init(fixture:)` builds a session with a fixed observation and no side effects (tests, review harness). Announces outcomes to VoiceOver (engine ready or failed, permission granted or denied).
  - `var canBackOut: Bool`, `var onBackOut: (() -> Void)?`, `var onFinish: ((SetupFrame) -> Void)?`; `func freeze() -> SetupFrame`.
  - **Microphone meter.** `SetupMicMeter`: an `AVAudioEngine` input tap computing RMS, running only while the mic is authorized, the active step is microphone or system audio, and the session is visible and not finished; it publishes a short history (44 values) and the current level. Stop it on finish, on disappear and on deinit. The mark breathes and the Me lane moves from these real levels. The Them lane never pretends to be live: when system audio is granted it shows a still, lit waveform shape with no ember dot.
- **Views.** `SetupStageView(core:t:levels:reduced:interactive:send:)` (pure; `interactive: false` renders a frozen face with no hit testing), and `WelcomeSetupView(session:reduced:)` (TimelineView wrapper, starts and stops the meter). Production chrome: the "1 of 3" counter and segments sit **top left**, in the tour chrome's position and style (`Theme.text(11)`, dim), because the welcome overlay's Skip lives top right. No lockup, iris, Ask still or Skip inside setup. `struct SetupFrame { core; t; levels }` for the frozen face.
- **Tests.** `Tests/WfflTests/SetupCoreTests.swift`: observation ramps start from the previous value, block copy for every engine and permission state (including engine names and Parakeet with no percent), completion rules, back-out visibility, no em or en dash in any user-facing string.

### B. Welcome flow (after A lands)

- `WelcomeJourneyPolicy`: campaign `quiet-instrument-2`. Everyone who has not acknowledged this campaign is eligible. `enum WelcomeMode: String { case film, setupOnly }`, captured once per campaign (`wffl.welcome.<campaign>.mode`): returning evidence gives `.film`, a fresh install `.setupOnly`. Stop marking new installs not applicable. The coordinator publishes `mode`.
- `WelcomeOpeningModel`: new phase `.setup` between `.tour` and `.folding`. Forward input at the tour's end enters setup; in setup, scroll is ignored and arrows go to the setup session (Right next, Left back; Left on step 1 returns to the tour's end when `canBackOut`). `beginFold()` after setup finishes plays `foldProgress` 0 to 1 automatically over 5.0 s (the cube bake is 601 frames at 120 Hz), then `finish()`. `startSetupOnly()` starts directly in `.setup`. Reduced Motion: finishing setup completes directly into Ask. The tour chrome's percent covers the tour only; in setup it hides the scroll hint and the ember hairline and keeps Skip.
- `WelcomeJourneyView`: owns the `SetupSession` (`canBackOut = mode == .film`), shows `WelcomeSetupView` in `.setup`, and passes the frozen `SetupFrame` to the fold.
- `WelcomeFoldHost` and `OpeningTourCapture`: a source enum, `.tour(time)` or `.setup(SetupFrame)`; the hosting view and the offscreen resize recapture render the frozen setup face for `.setup`.
- `ContentView`: passes the mode; a new install runs setup only.
- The isolated review app (`design-handoff/opening-reveal/final/FinalOpeningApp.swift`, `build-preview.sh`) injects a fixture `SetupSession` and gains a Setup phase jump, so the full sequence can be reviewed without touching real permissions or models.
- Tests in `WelcomeJourneyTests`: the new campaign re-shows to a user who acknowledged quiet-instrument-1; mode is captured once and persists; tour to setup to folding to complete; back-out; setup-only start; Reduced Motion completion.

### C. Sparkle updater (parallel with A)

- `Package.swift`: Sparkle 2 by SPM (`https://github.com/sparkle-project/Sparkle`, from a 2.x release at least two weeks old), product `Sparkle` on the Wffl target, rpath `@executable_path/../Frameworks`.
- `Sources/Wffl/Updates/AppUpdater.swift`: wraps `SPUStandardUpdaterController`; `checkForUpdates()`, a published `canCheckForUpdates`, and settings: automatically check (on by default), interval (daily, weekly, monthly), automatically download and install, last check date. It does not start in previews, tests or the review app.
- App menu: "Check for Updates…" after About. Settings: an Updates section in the existing Settings style: version and build, the three options, "Last checked", and a "Check Now" button. If the build has no public key, the section says updates are not set up in this build instead of failing.
- `Support/Info.plist`: `SUFeedURL` `https://github.com/PurvarajG/Wffl/releases/latest/download/appcast.xml`, `SUPublicEDKey` (from the owner's `generate_keys`), `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` 86400.
- `scripts/bundle.sh`: embed `Sparkle.framework` in `Contents/Frameworks` and sign its XPC services, Autoupdate and Updater.app inside out with the same identity and hardened runtime before signing the app.
- `.github/workflows/release.yml`: after the notarized DMG, sign it with `sign_update` using a `SPARKLE_ED_PRIVATE_KEY` secret, write `appcast.xml` (version, build, DMG URL, length, signature, minimum system version, release notes link) and upload it as a release asset. `docs/release-signing.md` explains the one-time key generation and the secret.
