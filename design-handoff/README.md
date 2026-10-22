# Wffl design handoff

Everything from the website and app UI redesign pass, in one folder. The macOS app source (`Sources/Wffl`) was NOT changed; the app screens here are mockups only.

## Where things are

| Path | What it is |
|---|---|
| `website/index.html` | The redesigned landing page. Single file, no build step. Fonts in `website/fonts/`. `vercel.json` is unchanged. |
| `mockups/index.html` | Every app screen as a mockup, plus a clickable walkthrough (Home, Start Recording, live recording, Stop & save, summary). Light and dark switch built in. |
| `PRODUCT.md` | Product truth (users, positioning, constraints, what must not be claimed). Inferred from the repo, labeled as such. |
| `DESIGN.md`, `.impeccable/design.json` | The design system as built: tokens, type, shape rules, components, motion, named rules. |
| `.impeccable/surfaces/website-index-html.md` | The direction contract for the site (thesis, own-world, story, first viewport). |
| `.impeccable/review/` | Screenshots used for review (real in-browser captures of the journey chapters, plus full-page mockup captures). |
| `inspiration/` | The user's reference folder (monochrome phone UIs, waveform logos, a dot-matrix video). The direction comes from these. |
| `tools/` | The Python generators that produced both HTML files (`gen_site.py`, `gen_mock2.py`, `mock.css`, `site_base.html`). Optional: the HTML files are the source of truth now. The scripts use absolute paths from the original machine, so edit the HTML directly unless you fix those paths. |
| `.claude/launch.json` | Preview config: serves this folder on port 4173. |

## Run it

```bash
cd design-handoff && python3 -m http.server 4173
```

Then open `http://localhost:4173/website/index.html` and `http://localhost:4173/mockups/index.html`.

## The design in one paragraph

A quiet instrument for voice. Monochrome page (cool off-white `#F2F2F0`, near-black `#0A0A0A` in dark), one soft grainy light (ember orange into lavender), one working instrument: a dot field that swells as speech arrives and resolves into words. Hanken Grotesk at light and regular weights, Fragment Mono only for captions and timecodes. Panels 24 to 32px radius, every button and tag a pill. Ember orange is the only accent and means "live" (recording lamp, playhead, glow). The features section is a scroll-driven journey through one meeting (record, transcribe, name speakers, clean up, write minutes, keep and find) with a sticky stage, a running timecode and a rail. Logo is a proposed eight-ellipse waveform mark that traces a W; the old stroke W is in git history.

## Status

- Website: built, checked at 1440 and 390 wide, light and dark. Two independent review rounds run. Round 3 (journey) returned a fix list that is NOT yet applied: see `TODO.md`.
- Mockups: built, checked light and dark. Fixes from round 3 are listed in `TODO.md`.
- Not deployed. Not committed. The tracked `website/index.html` in the repo root currently holds the new design uncommitted (a copy is here). Revert it with `git checkout website/index.html` if it should stay out of the 1.9 commit; `website/fonts/` is untracked.

## Facts to verify before shipping the site

- "Signed and notarized" in the setup copy is the existing claim; confirm it matches the latest release.
- The site says BAPS Whisper and Parakeet are for English, Whisper for 99 languages. Re-check against what 1.9 ships.
- Privacy copy: "Your audio stays on your Mac", telemetry "sends no usage data", cloud summaries opt-in, models download over the network once. Keep these wordings honest if 1.9 changes anything.
- Download and GitHub URLs point at `github.com/PurvarajG/Wffl/releases/latest/download/Wffl.dmg` and the repo.

## Mapping the mockups to the app (for the "mad update")

Mockup screen to SwiftUI file: Home `HomeView.swift`, Recording `RecordingBar.swift` (`RecordingSurface`), Dashboard `DashboardView.swift`, Meetings and detail `MeetingListView.swift`, `MeetingDetailView.swift`, `SummaryView.swift`, `TranscriptView.swift`, Audio files `AudioFilesView.swift`, Settings `SettingsPane.swift` and `SettingsView.swift`, shell and sidebar `ContentView.swift`, tokens `Support/Theme.swift`.

New tokens to replace `Theme.swift` values (light / dark): bg `#F2F2F0` / `#0F0F0F`, sidebar `#E9E9E6` / `#0A0A0A`, surface `#FFFFFF` / `#181818`, ink `#0B0B0B` / `#F2F2F0`, text `#2B2B29` / `#D7D7D3`, dim `#6B6B67` / `#9B9B96`, ember `#FF5B1F` / `#FF6A33` (live only). Selected row and primary action are a black pill (inverted in dark). Live recording rows say "Me" and "Them"; names appear only after diarization.
