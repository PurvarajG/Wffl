# PLAN: Cleanup speed (tiny-draft/big-verifier) + honest determinate progress bar

**Executor:** Claude Sonnet 5 (high reasoning). Follow this plan literally. Where it says
"verbatim", copy the text exactly. Do not refactor, rename, or "improve" anything outside
the listed files. If a step's verification fails, stop and report — do not improvise a
different architecture.

## Context

Wffl's post-meeting cleanup (`Sources/Wffl/LLM/CleanupPipeline.swift`, four passes:
Scan → Structure → Arbiter → Assemble, shipped in commit f6344a4) is functionally
correct but too slow: a 9-minute transcript takes many minutes. Two work streams:

1. **Speed** — measured root cause is *memory contention*, not model quality:
   with gemma3:4b + gemma3:12b + gemma4:12b-mlx all resident (~22 GB of a 24 GB
   Mac17,9), `gemma4:12b-mlx` collapses from a healthy 42–51 tok/s to ~1 tok/s.
   Fix: tiny draft model + one big model everywhere, plus concurrency, a compact
   output schema, and per-call generation caps. Add real metrics so efficiency is
   measurable from now on.
2. **Progress UI** — replace the indeterminate `AnimatedProgressBar` +
   "this may take a minute" with a determinate, eased bar: moves within seconds,
   shows the stage, structurally cannot park at 99%, snaps to 100% on completion.

## Environment facts (verified 2026-07-13, do not re-derive)

- Mac17,9, 24 GB unified memory, Ollama 0.31.1 at `http://localhost:11434`.
- Installed: `gemma4:12b-mlx` (7.7 GB), `gemma3:12b` (8.1 GB), `gemma3:4b` (3.3 GB),
  `qwen3.5:4b`. **`gemma3:1b` is NOT installed yet — Step 0 pulls it.**
- Measured throughput (`/api/generate`, ~900-token prompt, num_ctx 16384):

  | Model | prompt tok/s | gen tok/s |
  |---|---|---|
  | gemma3:4b | ~350 | ~83 |
  | gemma3:12b | ~680 | ~34 |
  | gemma4:12b-mlx (other models resident) | 18–220 erratic | **1.4 → 0.3** |
  | gemma4:12b-mlx (alone) | ~220 | **42–51** |

- Memory budget rule this plan enforces: during cleanup only `gemma3:1b` (~0.8 GB)
  and `gemma4:12b-mlx` (~9 GB resident) may be loaded. Summaries also move to
  `gemma4:12b-mlx` so a summary after cleanup never re-crowds memory.
- Ollama's streamed final chunk (`"done": true`) carries `prompt_eval_count`,
  `eval_count`, `prompt_eval_duration`, `eval_duration`, `load_duration`,
  `total_duration` (durations in nanoseconds). `LLMClient.ollamaChat` currently
  discards all of them.
- The git index still holds the large staged Meetily→Wffl rename. Use a
  **path-scoped commit** (Step 10). Do not push.
- `Support/Info.plist`: currently `CFBundleShortVersionString = 1.2.0`,
  `CFBundleVersion = 4`.

## Step 0 — Preflight

```bash
ollama pull gemma3:1b            # ~0.8 GB
ollama list                      # must now include gemma3:1b
swift build 2>&1 | tail -5       # baseline must build
swift test 2>&1 | tail -5        # baseline must pass
```

## Step 1 — `Sources/Wffl/LLM/LLMProvider.swift`: stats, per-call options, keep_alive

1. Add near the top (after `LLMConfig`):

   ```swift
   /// Per-call token/timing stats from Ollama's final stream chunk.
   /// Durations are seconds (converted from Ollama's nanoseconds).
   struct LLMCallStats {
       var promptTokens = 0
       var evalTokens = 0
       var promptSeconds = 0.0
       var evalSeconds = 0.0
       var loadSeconds = 0.0
       var totalSeconds = 0.0
   }
   ```

2. Extend `LLMClient.complete` with per-call overrides and a stats sink,
   defaulted so **every existing call site compiles unchanged**:

   ```swift
   func complete(system: String, user: String,
                 numPredict: Int? = nil,
                 temperature: Double? = nil,
                 onStats: ((LLMCallStats) -> Void)? = nil) async throws -> String
   ```

   Thread all three through to `ollamaChat` only (other providers ignore them —
   pass the parameters along but only the Ollama branch uses them).

3. In `ollamaChat`:
   - options become `["num_ctx": 16_384, "num_predict": numPredict ?? 8192]`,
     plus `"temperature": temperature` when non-nil.
   - add `"keep_alive": "10m"` to the request body (top level, sibling of
     `"options"`), so models stay warm across passes and manual re-cleans.
   - in the stream loop, when `json["done"] as? Bool == true`, also read the six
     stat fields (each `as? NSNumber`, default 0; divide durations by 1e9) into an
     `LLMCallStats`, store it on the `Result` box, and after the task group call
     `onStats?(stats)` before returning.

4. Do not touch the doom-loop detector, stall watchdog, or non-Ollama providers.

`swift build` must pass after this step.

## Step 2 — `Sources/Wffl/Support/Prefs.swift`: model tiering defaults + one-time migration

1. Change the cleanup model default: `cleanupModel` returns
   `d.string(forKey: "cleanupModel") ?? "gemma3:1b"`.
2. `arbiterModel` default stays `"gemma4:12b-mlx"` (unchanged).
3. Change the Ollama summary default: in `LLMProviderKind.defaultModel`
   (`LLMProvider.swift`), `.ollama` returns `"gemma4:12b-mlx"` instead of
   `"gemma3:12b"`. If Prefs stores a summary model key with its own default,
   update that default identically — search for `"gemma3:12b"` across
   `Sources/` and update every *default* (never a user-stored value read).
4. One-time migration in `Prefs` (call it from app startup — `WfflApp.init` or
   wherever Prefs is first touched; a `static func migrateModelDefaults()` guarded
   by a `d.bool(forKey: "migratedTinyDraft_1_2_1")` flag):
   - if stored `cleanupModel` == "gemma3:4b" (old default) → remove the key
     (falls back to the new default).
   - if stored summary model == "gemma3:12b" (old default) → remove the key.
   - never touch keys holding any other value (explicit user choices win).
5. Live-correction model (`correctionModel`) is untouched.

## Step 3 — `Sources/Wffl/LLM/CleanupPipeline.swift`: schema, concurrency, pipelining, metrics, progress

### 3.1 Metrics aggregation

Add:

```swift
/// Aggregates wall time + token counts per pass; rendered as one summary
/// string for the log and the cleaned_transcripts.stats column.
final class CleanupMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var passes: [(name: String, calls: Int, promptTokens: Int,
                          evalTokens: Int, wallSeconds: Double)] = []
    func record(pass: String, calls: Int, promptTokens: Int, evalTokens: Int, wallSeconds: Double)
    var summary: String   // e.g. "scan 0.1s | structure 3 calls 28.4s (2.1k prompt / 950 gen, 33 tok/s) | arbiter 2 calls 9.0s (…) | total 37.5s"
}
```

`record` appends under the lock; `summary` renders passes in insertion order with
tok/s = evalTokens / max(sum of per-pass eval wall, wallSeconds) — keep it simple:
`evalTokens / wallSeconds` per pass, "total" is the sum of wallSeconds. Token
counts ≥ 1000 render as `2.1k`.

### 3.2 Progress reporting

Define:

```swift
struct CleanupProgress {
    let fraction: Double   // 0...1, monotonically non-decreasing
    let stage: String      // e.g. "Structuring section 2 of 4"
}
```

Stage weights: scan = 0.05, structure = 0.75 (divided evenly across windows,
credited as each window *completes*), arbiter = 0.20 (divided across batches).
When the arbiter has nothing to do, jump straight to 1.0. The pipeline emits via a
`((CleanupProgress) -> Void)?` callback threaded from `TranscriptCleanupService`.

### 3.3 Pass B — compact output schema

Replace `StructurePass.systemPrompt` with, verbatim (note `<GLOSSARY>` is
substituted at runtime with `Vocabulary.shared.glossary` — build the prompt in a
`static func systemPrompt(glossary: String) -> String`):

```
You analyze raw speech-to-text meeting transcript lines. You never rewrite the
transcript. You output ONLY a single JSON object, no markdown fences, no prose:

{"breaks":[12,16,21],
 "headings":{"12":"Budget review"},
 "edits":[{"line":12,"old":"gun curtain swami","new":"Gunkirtan Swami","confidence":0.9}]}

Rules:
- "breaks": the line indexes where a NEW paragraph starts (one speaker turn or one
  thought per paragraph). Strictly increasing. The first line of the input is
  always a paragraph start — do not include it.
- "headings": optional map from a paragraph-start index (as a string key) to a
  2-5 word topic title, ONLY where the discussion clearly moves to a new topic.
  Usually empty: {}.
- "edits": ONLY for text that is clearly a speech-recognition error: a garbled
  word/phrase phonetically close to a glossary term, an obvious mis-recognition
  fixable from context, or a filler phrase ("you know", false starts) safe to drop
  (use "new":""). "old" must be copied EXACTLY from the line's text. Keep edits
  short — a few words, never a whole line. "confidence" 0.0-1.0: use below 0.85
  whenever unsure; a reviewer model checks those. Never invent content, never
  change wording that is already plausible, never touch numbers or timecodes.
- If nothing needs editing, "edits" is [].

Glossary of correct spellings: <GLOSSARY>
```

User message: same as today **minus** the glossary line (keep the suspect-words
line and the `INDEX [TIMECODE] TEXT` lines).

Parsing/validation for the new schema:
- `breaks`: ints, each strictly greater than the previous, each in
  `(windowStart, windowEnd]`. Values equal to `windowStart` are tolerated and
  ignored (models often include the first line despite instructions). Any other
  violation → window falls back to `fallbackGrouping` (unchanged).
- Reconstruct paragraphs: starts = `[windowStart] + breaks`; each paragraph ends
  at the next start − 1, last ends at `windowEnd`. Attach `headings[start]` when
  present and non-empty.
- `edits`: identical validation to today (containment check with case-insensitive
  fallback, confidence clamp). The parse-fail → one retry → fallback flow is
  unchanged.
- LLM calls in Pass B use `numPredict: 1500, temperature: 0` and pass `onStats`
  into the metrics aggregator.

### 3.4 Pass B — bounded concurrency + arbiter pipelining

Rework `StructurePass.run` + `TranscriptCleanupService` orchestration:

- Compute all windows up front (`windowSize` stays 100).
- Run windows with `withThrowingTaskGroup`, **max 2 in flight** (submit 2, then
  one new task per completion). Each task returns
  `(windowIndex, [CleanupParagraph], [CleanupEdit])`; collect into a dictionary
  and flatten in window order at the end.
- As each window completes: credit its progress slice, and hand its edits with
  `confidence < 0.85` (new escalation threshold — update
  `ArbiterPass.escalationThreshold` to 0.85) plus its unresolved Pass-A suspects
  to an **arbiter feeder** so the 12b verifies while the 1b keeps structuring.
  Implementation: an `AsyncStream<[CleanupEdit]>` (or actor-guarded queue) that a
  single consumer task drains, batching 10 spans per request exactly like today's
  `runBatch`. Arbiter calls use `numPredict: 500, temperature: 0` + stats.
  Suspect de-duplication against covering edits must now happen per-window (a
  suspect is "covered" if any edit from ITS OWN window's results contains it —
  same semantics as today, evaluated when the window completes).
- Arbiter failure semantics unchanged: a failed batch = all-reject, never throws.
- Keep the existing `cleanup: N edits (...)` log line, and add the metrics
  summary log line at the end.

### 3.5 Assembler

Unchanged.

## Step 4 — `Sources/Wffl/LLM/TranscriptCleanupService.swift`

Signature becomes:

```swift
func clean(transcript: String,
           progress: ((CleanupProgress) -> Void)? = nil) async throws -> (markdown: String, stats: String)
```

It creates the two clients as today (structure client = config as passed; arbiter
client swaps model to `Prefs.arbiterModel` when `config.kind == .ollama`), owns the
`CleanupMetrics` instance, times each pass, and returns `(assembled, metrics.summary)`.

## Step 5 — `Sources/Wffl/Database/Database.swift` + `Models.swift`: stats column

- `CleanedTranscript` gains `var stats: String?`.
- Additive migration following the existing pattern in `Database.swift` (look at
  how earlier `ALTER TABLE` migrations are done there and copy the idiom):
  `ALTER TABLE cleaned_transcripts ADD COLUMN stats TEXT` guarded so it runs once.
- Read/write the column wherever `cleaned_transcripts` rows are mapped.

## Step 6 — `Sources/Wffl/AppState.swift`: progress state + wiring

1. Add `@Published var cleanupProgress: [String: CleanupProgress] = [:]`.
2. In `generateCleanedTranscript(for:)`:
   - before starting the task: `cleanupProgress[meeting.id] = .init(fraction: 0, stage: "Preparing…")`.
   - pass a progress closure into `clean` that hops to the main actor and updates
     the dictionary (drop updates whose fraction is lower than the stored one —
     monotonic guarantee for the UI).
   - on success store `c.stats = stats` alongside `c.markdown`.
   - in ALL exit paths (success, cancel, failure) remove the meeting's entry from
     `cleanupProgress` on the main actor.
3. `cancelCleanup(for:)` also removes the entry.
4. `warmUpCleanupModels()` needs no logic change (it already warms cleanup +
   arbiter models); just confirm it now warms `gemma3:1b` + `gemma4:12b-mlx`.

## Step 7 — Progress UI: `EasedProgressBar` + `TranscriptView`

New file `Sources/Wffl/Views/EasedProgressBar.swift`:

```swift
/// Determinate progress bar with perception-tuned easing:
/// - displayed value = real fraction * 0.92, so it can never park near 100%;
/// - between real updates it creeps forward ~1% per 4s, asymptotically,
///   never crossing the 0.92 ceiling, so it never looks frozen;
/// - when the real fraction reaches 1.0 it animates to 100% in ~0.4s —
///   the fast finish that makes the whole wait feel shorter.
struct EasedProgressBar: View {
    let fraction: Double   // real progress 0...1
    ...
}
```

Implementation notes:
- `@State private var displayed: Double = 0`; a `TimelineView(.periodic(from:by: 0.5))`
  or `Timer.publish` drives the creep; on `fraction` change animate `displayed`
  to `min(fraction * 0.92, ceiling)` with `.easeOut(duration: 0.6)`; when
  `fraction >= 1` animate to 1.0 with `.easeIn(duration: 0.4)`.
- Creep: `displayed += (0.92 * fractionBase - displayed) * 0.02` per tick where
  `fractionBase` is the next stage boundary — simplest correct version:
  `displayed = min(displayed + 0.0025, fraction * 0.92 + 0.03, 0.92)` per 0.5s tick.
- Visual: reuse the app's existing bar styling (`Theme` colors, capsule track,
  ~0.6 width like `AnimatedProgressBar`). Do not delete `AnimatedProgressBar`
  (other views may use it — check; if nothing else uses it, delete it).

In `TranscriptView.cleanedBody`, generating case becomes:

```swift
let p = app.cleanupProgress[meeting.id]
EasedProgressBar(fraction: p?.fraction ?? 0)
Text(p?.stage ?? "Preparing…")            // stage label
    .font(.callout).foregroundStyle(.secondary)
Text(elapsedLabel)                         // "0:42 elapsed" — @State start date set onAppear of this branch
    .font(.caption).foregroundStyle(Theme.muted)
```

Cancel button unchanged. Completed case: after the markdown view, if
`c.stats` is non-nil render a muted `.caption` footnote line: the stats summary.

## Step 8 — Tests: `Tests/WfflTests/CleanupPipelineTests.swift`

Keep every existing test green (the scanner/assembler behavior is unchanged; the
Pass-B parse tests must be updated to the new schema). Add:

1. **Breaks-schema parsing**: reply with `breaks`/`headings`/`edits` (wrapped in
   ```` ```json ```` fences + prose preamble) parses; paragraphs reconstruct to the
   correct `[start,end]` ranges with headings attached.
2. **Breaks validation**: non-increasing breaks, out-of-window breaks → nil
   (fallback path); a break equal to windowStart is tolerated/ignored.
3. **Escalation threshold**: edit at confidence 0.84 escalates, 0.86 bypasses.
4. **Metrics summary formatting**: two recorded passes render calls/tokens/total
   as specified (spot-check the `2.1k` formatting and total).
5. **Progress monotonicity**: stage weights emit non-decreasing fractions ending
   at 1.0 for a synthetic 3-window + 2-batch run (test the weight math as a pure
   function if needed — factor it so it's testable without an LLM).

`swift test` must pass.

## Step 9 — Version bump + build + install + smoke test

1. `Support/Info.plist`: `CFBundleShortVersionString` → `1.2.1`, `CFBundleVersion` → `5`.
2. `bash scripts/bundle.sh` → must end with `Built dist/Wffl.app`.
3. Install:
   ```bash
   osascript -e 'quit app "Wffl"' 2>/dev/null; sleep 1
   ditto dist/Wffl.app /Applications/Wffl.app.new && rm -rf /Applications/Wffl.app && mv /Applications/Wffl.app.new /Applications/Wffl.app
   codesign --verify --deep /Applications/Wffl.app && open /Applications/Wffl.app
   ```
4. Smoke test (computer-use) on the 9-minute meeting that was slow:
   - hit **Re-clean**; the bar starts moving within ~2s, stage labels advance
     ("Structuring section 1 of N" → "Reviewing corrections…"), the bar never
     exceeds ~92% until it snaps to 100%;
   - completion well under the previous wall time — record the metrics log line
     (`log stream --predicate 'process == "Wffl"'` or Console.app) as the
     before/after evidence;
   - during cleanup `ollama ps` shows ONLY `gemma3:1b` and `gemma4:12b-mlx`;
   - cleaned output quality: paragraphs with `**[M:SS]**` timecodes all present in
     the raw transcript, glossary names correct, headings sensible. If the 1b
     draft's structure quality is visibly bad (garbled paragraphs, nonsense
     headings on this real meeting), STOP and report — the fallback is to set
     `cleanupModel` default to `gemma3:4b` while keeping every other change, but
     that is a decision for the user, not the executor.
   - stats footnote visible under the cleaned transcript.
5. Generate a summary on the same meeting → badge shows `gemma4:12b-mlx`, completes
   normally, `ollama ps` still shows only the two models.

## Step 10 — Commit (path-scoped — CRITICAL)

The index holds a large unrelated staged rename. Commit ONLY this work's paths:

```bash
git add <the files below>
git commit -m "Tiny-draft cleanup tiering + determinate eased progress bar

gemma3:1b drafts structure, gemma4:12b-mlx verifies; summaries move to
gemma4:12b-mlx so only two models are ever resident (fixes the ~1 tok/s
memory-contention collapse). Compact breaks-schema output, 2-way window
concurrency, pipelined arbiter, per-call num_predict/temperature caps,
keep_alive, and per-pass metrics persisted to the DB. UI: EasedProgressBar
(92% ceiling, creep, fast finish) with stage labels + elapsed time.
Bump to 1.2.1.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" \
  -- Sources/Wffl/LLM/LLMProvider.swift \
     Sources/Wffl/LLM/CleanupPipeline.swift \
     Sources/Wffl/LLM/TranscriptCleanupService.swift \
     Sources/Wffl/AppState.swift \
     Sources/Wffl/Views/TranscriptView.swift \
     Sources/Wffl/Views/EasedProgressBar.swift \
     Sources/Wffl/Support/Prefs.swift \
     Sources/Wffl/Database/Database.swift \
     Sources/Wffl/Models/Models.swift \
     Sources/Wffl/WfflApp.swift \
     Tests/WfflTests/CleanupPipelineTests.swift \
     Support/Info.plist \
     PLAN-speed-and-progress.md \
     PLAN-cleanup-pipeline.md
```

(`PLAN-cleanup-pipeline.md` is already deleted from the working tree and staged as
a deletion — including its path commits the removal.)

`git show --stat HEAD` must list only those files. Do not push; do not touch the
staged Meetily→Wffl rename.

## Acceptance checklist

- [ ] `swift build` and `swift test` clean
- [ ] 9-minute meeting re-cleans dramatically faster; metrics line recorded as evidence
- [ ] Only `gemma3:1b` + `gemma4:12b-mlx` resident during cleanup (`ollama ps`)
- [ ] Progress bar: moves in ~2s, stage labels, ≤92% until the fast snap to 100%
- [ ] Stats footnote under the cleaned transcript; `stats` column populated
- [ ] Summary path works on `gemma4:12b-mlx`; live correction untouched
- [ ] Explicit user-chosen model prefs survive the migration (only old defaults migrate)
- [ ] Version 1.2.1 / build 5 installed; path-scoped commit contains exactly the listed files
