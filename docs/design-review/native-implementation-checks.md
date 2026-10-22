# Quiet Instrument native implementation checks

## Build and source verification

- The native source implements the monochrome adaptive theme, Hanken Grotesk and Fragment Mono resources, responsive Home/Dashboard/meeting/settings surfaces, a recording instrument with truthful transport states, provider disclosure, and a five-chapter welcome.
- `swift test`: 212 tests, three skipped, zero failures in the final root-run suite (`/tmp/Wffl-quiet-instrument/final-tests.log`). The baseline was 204 tests, three skipped, zero failures. New tests cover effective local/remote endpoints and welcome eligibility, first-active launch, busy deferral, acknowledgment and replay without changing engine/provider preferences.
- `swift build`: passes. The vendor static-library macOS 26 link warnings, AppState warnings and unhandled test fixture warning predate this change; there are no compiler warnings from newly added files.
- `git diff --check`: passes.
- `WFFL_SIGN_IDENTITY='Developer ID Application: Purvarajsinh Gohil (26FGCLN3AH)' WFFL_APP_PATH=/tmp/Wffl-quiet-instrument/Wffl.app scripts/bundle.sh debug`: signed, verified temporary app. The installed application was not replaced or launched by the implementer.
- Font bundle: `/tmp/Wffl-quiet-instrument/Wffl.app/Contents/Resources/Wffl_Wffl.bundle/Contents/Resources/Resources/Fonts/` contains both TTFs and both OFL licenses. CoreText metadata reports `HankenGrotesk-Regular` and `FragmentMono-Regular`; the loader uses these PostScript names and a system fallback.

## Native visual QA

The root orchestrator checked isolated native builds and corrected a welcome sizing defect, Home/Settings copy and permission links, Dashboard hierarchy, and the Me rename affordance. The current welcome sheet uses an explicit 760×500 layout in the 900×560 host, an intrinsic two-column composition, a scrollable stacked fallback, and a pinned footer. The installed Wffl process remained running throughout QA. For debug visual QA only, `WFFL_UI_PREVIEW_DATA_DIR` redirects the database to an isolated directory and bypasses legacy data migration; the same flag skips preference migrations, Keychain migration, meeting auto-detection and notification authorization. DEBUG-only `WFFL_UI_PREVIEW_APPEARANCE` and `WFFL_UI_PREVIEW_REDUCE_MOTION` allow dark and static welcome checks without changing global settings. `WFFL_UI_PREVIEW_RECORDING=1` creates a paused, labeled sample transcript purely in memory; transport actions are inert in that fixture. The root used copied temporary bundles with distinct preview identifiers and `LSEnvironment` overrides, then re-signed them. No recording or model download was performed.

Verified native observations: compact Home and Settings were readable and reachable; Summary and Transcript fit the compact window; Dashboard stacked correctly at compact width and placed the calendar beside the dominant weekly count at native zoom; the paused and collapsed recording instruments fit with reachable controls; all five welcome chapters were inspected across light and dark previews, including the compact pinned footer; the identity and speaker scenes showed their completed states under Reduced Motion. The senior design reviewer approved the Dashboard composition. Screenshots: `/tmp/wffl-native-welcome-light.png`, `/tmp/wffl-native-welcome-baps.png`, `/tmp/wffl-native-welcome-dark.png`, `/tmp/wffl-native-transcript-light.png`, `/tmp/wffl-native-dashboard-dark-compact.png`, `/tmp/wffl-native-dashboard-dark-wide.png`, `/tmp/wffl-native-recording-paused.png`, `/tmp/wffl-native-recording-collapsed.png`.

Release QA still needs a manual foreground launch to witness the first-active automatic welcome sheet and a complete keyboard/VoiceOver pass. The native preview tool launched the app in the background and exposed no reliable activation API; the welcome correctly remained pending instead of becoming a mid-session invitation. Focused policy tests verify that the first active, idle event opens once and a busy first active event remains invitation-only. The HTML prototype is design evidence, not native verification.

## Functional boundaries

- No audio, database schema, ASR routing, model management or cleanup algorithm was changed. Recording shortcuts call the existing recorder methods; menu enablement follows `.recording` and `.paused`.
- Provider labels use the effective endpoint: remote Ollama and empty custom URL (OpenAI default) disclose transcript transfer; loopback custom endpoints remain local. Audio capture and transcription stay local.
- The welcome campaign key is `quiet-instrument-1`. Eligibility is captured before preference migrations, from historical meetings or allowlisted preexisting current/legacy app preferences. Fresh installs are marked not applicable for this campaign. A journey acknowledges only after actual presentation and dismissal; an inactive launch waits for its first active event; a busy first active event leaves an invitation, without a surprise later modal.
- The static sample content in the welcome is labeled illustrative. The mic stays Me; an unknown remote voice becomes Speaker 1 with a visible Rename label. The model chapter does not claim BAPS Whisper is downloaded.

## Changed-file map and handoff status

- `Package.swift`, `scripts/bundle.sh`, `Sources/Wffl/Resources/Fonts/`, `Sources/Wffl/Support/AppFonts.swift`: native fonts, licenses, registration, and signed bundle resources.
- `Sources/Wffl/Support/Theme.swift`, `Sources/Wffl/Views/InstrumentComponents.swift`, and existing view files in `Sources/Wffl/Views/`: adaptive visual system, shell, Home, Dashboard, recording, meetings, transcripts, summaries, imported audio, and settings.
- `Sources/Wffl/Support/ProcessingDisclosure.swift`, `Sources/Wffl/Support/WelcomeJourney.swift`, `Sources/Wffl/Views/WelcomeJourneyView.swift`, `Sources/Wffl/WfflApp.swift`, and `Sources/Wffl/AppState.swift`: truthful provider labels and five-scene, once-per-campaign welcome lifecycle.
- `Sources/Wffl/Support/PreviewRuntime.swift`, narrow DEBUG-only changes in `Sources/Wffl/Database/Database.swift`, and `Sources/Wffl/LLM/LLMProvider.swift`: safe isolated preview and effective endpoint support.
- `Tests/WfflTests/ProcessingDisclosureTests.swift`, `Tests/WfflTests/WelcomeJourneyTests.swift`: pure behavior tests.

Implementation, isolated visual review, build, signature verification, and full tests are complete. Manual first-foreground welcome activation and a complete keyboard/VoiceOver pass remain release QA items. No app commit, version bump, installed-app replacement, or publication was made.

The final isolated animated review bundle is `/tmp/Wffl-quiet-instrument/Wffl Preview.app` (preview bundle identifier `com.purvaraj.wffl.preview.finalreview`). It uses labeled sample records and separate preferences; Reduce Motion is not forced in this review copy. Replay is available through Help → What’s New in Wffl. The final native workspace illustration uses normal word wrapping for its small tab labels rather than splitting Summary and Transcript mid-word. The final build, signature and 212-test result were verified after this adjustment.

## Cinematic revision — 21 October 2026

User explicitly chose stronger spatial movement and dramatic transitions, using fewer elements, and confirmed this is a macOS-only app. All small native layouts refer to smaller Mac windows, not a mobile variant.

The native welcome now keeps one workspace and waveform alive through five user-controlled geometry states, with 900 ms camera moves. Copy remains anchored and changes immediately. The same transcript row changes from Them to Speaker 1, with a visible Rename hint; it does not duplicate the row. The BAPS scene has a dedicated model band. Home readiness, transcript and summary lose redundant card frames without changing their data/actions. Lifecycle/campaign/processing policy remains unchanged.

Final senior visual approval is recorded in app-ui-review.md. Root verified the final build at the 900×560 Mac window minimum: waveform/sidebar landing, transcript/rename/minutes clearance, BAPS qualifier and scroll region, final workspace, Help replay, Escape dismissal and Explore dismissal. Dark appearance with forced Reduced Motion shows complete static target states. Focus/arrow behavior was not conclusively exercised by the background UI automation; foreground keyboard and full VoiceOver checks remain release QA, alongside the existing automatic-first-active-launch manual check.

Evidence:
- `/tmp/wffl-cinematic-native-ch2-final.png`
- `/tmp/wffl-cinematic-native-ch3-approved.png` (latest geometry and same-row speaker transition)
- `/tmp/wffl-cinematic-native-ch4-final.png`
- `/tmp/wffl-cinematic-native-ch5-approved.png`
- `/tmp/wffl-cinematic-native-dark-reduced.png`
- `/tmp/wffl-cinematic-native-home.png`

Latest full `swift test`: 212 tests, 3 skipped, 0 failures (`/tmp/wffl-cinematic-final-tests.log`, 16:19 BST). Final debug bundle and both preview copies passed deep/strict code-signature verification. Existing vendor deployment-target warnings remain baseline.

Review build: `/tmp/Wffl-cinematic/Wffl Cinematic.app` (Help → What’s New). Bundle ID `com.purvaraj.wffl.preview.cinematicfinal`; DEBUG data path `/tmp/Wffl-cinematic/final-data`, seeded only from the prior sample preview database via SQLite backup. The dark/reduced-motion copy has its own bundle ID and data folder and was closed after checking. Installed `/Applications/Wffl.app` and the older user-open preview were left running untouched. Native source remains local, uncommitted and unreleased.

Website: cinematic revision committed/pushed as `ffd0aabd0759f66afc6e998638767d061597bb26`, website-only. Senior checked wide/smaller-browser/reduced-motion states; root additionally checked a 375 px browser viewport. Website responsiveness does not imply a mobile app. Local review URL: `http://127.0.0.1:4181/website/`. At the final check, GitHub/Vercel had not posted a deployment for this SHA; do not claim it is live in production.
