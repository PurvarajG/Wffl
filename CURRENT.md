# START HERE: what is current

**Branch:** `master` (same commit as `app-v2`). There are no other live design branches.

**Final app design: "Ask the library" (app v2).** Native macOS shell, search/ask-first home.
- Direction + rationale: `design-handoff/app-v2/APP-DIRECTION.md`
- Reference screens (final, built): `design-handoff/app-v2/built/`
- Design system: `DESIGN.md`, `design-handoff/DESIGN.md`; product truth: `design-handoff/PRODUCT.md`
- Code: `Sources/Wffl/Views/` (shell, Ask, meeting detail), `Sources/Wffl/Welcome/FilmScenes.swift` (update film, ends on app v2)
- Website: `website/index.html` (already aligned to app v2)

**Ignore / archived:** `design-handoff/_archive/` and any `archive/*` git tag. That is the earlier in-app redesign, rejected.
Do not restore yellow/cream/sage; ember orange means "live" only.

Open work: Settings still uses the old card style. Opening-reveal studies live in `design-handoff/opening-reveal/` (not yet integrated).

### Training clips from your corrections

Right-click a transcript line and choose **Correct this line**. Wffl rewrites the line, remembers each word you changed so later transcripts get it right, and keeps the corrected line as a training example.

`scripts/export-training-clips.sh --publish` writes those examples to `docs/corpus/training-clips/clips/` as 16 kHz mono WAV files with a JSON label each, the layout Atlas's `finetune_turbo.py` reads. The folder holds real meeting audio and is gitignored. Getting the clips into an Atlas training run is a separate step in the Atlas repo.
