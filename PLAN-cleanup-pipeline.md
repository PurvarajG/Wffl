# PLAN: Edit-list cleanup pipeline (draft → verify, truncation-proof)

**Executor notes:** Follow this plan literally. Where it says "verbatim", copy the text exactly.
Do not refactor, rename, or "improve" anything outside the listed files. If a step's
verification fails, stop and report — do not improvise a different architecture.

## Context

Wffl is a native macOS SwiftUI app (SwiftPM, no Xcode project) that records meetings,
live-transcribes with Whisper/Parakeet, and post-processes with local Ollama models.

The post-meeting "Clean Up" feature (`Sources/Wffl/LLM/TranscriptCleanupService.swift`)
currently sends 24,000-char chunks to `gemma3:4b` and asks it to **rewrite the whole
chunk**. Output length therefore scales 1:1 with input, and the model hits Ollama's
`num_predict: 8192` output cap on long meetings → `"Ollama reply truncated"` error
(observed on a real 37-minute meeting). Doom-loop risk also scales with output length.

**The fix:** the model never writes the transcript. It emits small structured
*decisions* (paragraph groupings, headings, word-level edits) and Swift applies them
to the original text. Output size becomes independent of meeting length, so truncation
and corruption become structurally impossible.

Four passes:

| Pass | Actor | Job |
|---|---|---|
| A — Scan | Swift (no LLM) | glossary fuzzy-fix via existing `Vocabulary.correct()`, dedupe, strip fillers, flag suspect spans |
| B — Structure | `gemma3:4b` (Prefs.cleanupModel) | per-window JSON: paragraph groupings + topic headings + micro-edits with confidence |
| C — Arbiter | `gemma4:12b-mlx` (new Prefs.arbiterModel) | rules only on low-confidence edits + unresolved suspects; never reads the whole transcript |
| D — Assemble | Swift (no LLM) | validate + apply edits against original lines, build final Markdown |

## Environment facts (verified, do not re-derive)

- Ollama at `http://localhost:11434` has: `gemma4:12b-mlx`, `gemma3:12b`, `gemma3:4b`, `qwen3.5:4b`.
  `gemma4:12b-mlx` responds correctly via `/api/chat` (already tested).
- `LLMClient` (in `Sources/Wffl/LLM/LLMProvider.swift`) streams Ollama with
  `num_ctx: 16_384`, `num_predict: 8192`, a stall watchdog, and a doom-loop detector.
  **Do not modify LLMProvider.swift.** Windows sized below keep well inside these limits.
- `Vocabulary` (`Sources/Wffl/Transcription/Vocabulary.swift`) already provides
  `correct(_:allowForce:)` (fuzzy snap + phrase rewrite), `tripwires`, `glossary`,
  `terms`, and private `editDistance`/`fuzzyPool`/`isEnglishWord`.
- Raw transcript lines look like `[3:42] some text` or `[1:02:07] some text`.
  (Rendered by the app as `[M:SS]` / `[H:MM:SS]` prefixes, one segment per line.)
- Cleanup is launched from `AppState.generateCleanedTranscript(for:)`
  (`Sources/Wffl/AppState.swift` ~line 201), which calls
  `TranscriptCleanupService(config:).clean(transcript:)` — **keep that signature**.
- App version in `Support/Info.plist`: currently `CFBundleShortVersionString = 1.1.1`,
  `CFBundleVersion = 3`.
- The git index already contains a large staged Meetily→Wffl rename that must NOT be
  swept into this work's commit. Use a **path-scoped commit** (Step 8).

---

## Step 0 — Preflight

```bash
ollama list            # must show gemma3:4b, gemma3:12b, gemma4:12b-mlx
swift build 2>&1 | tail -5   # baseline must build before you start
```

## Step 1 — `Vocabulary.nearMisses` (Pass A support)

In `Sources/Wffl/Transcription/Vocabulary.swift`, add one public method (place it
right after `correct(_:allowForce:)`). It exposes "close but not confident" fuzzy
candidates — words within edit distance 3 of a glossary term that `correctWord`
would NOT auto-snap (it stops at distance 2):

```swift
    /// Words that are *near* a vocabulary term but not close enough for the
    /// deterministic snap in `correctWord` (edit distance exactly 3, word and
    /// term both >= 6 chars, word not already a known spelling and not valid
    /// English). These are handed to the LLM passes as suspect spans.
    func nearMisses(in text: String) -> [String] {
        var found: [String] = []
        var word = ""
        func flush() {
            defer { word = "" }
            guard word.count >= 6 else { return }
            let lower = word.lowercased()
            guard knownSpellings[lower] == nil, !isEnglishWord(word) else { return }
            for cand in fuzzyPool where cand.lower.count >= 6
                && abs(cand.lower.count - lower.count) <= 3 {
                if Self.editDistance(lower, cand.lower, limit: 3) == 3 {
                    found.append(word)
                    return
                }
            }
        }
        for ch in text {
            if ch.isLetter { word.append(ch) } else { flush() }
        }
        flush()
        return found
    }
```

No other changes to this file. Build after this step (`swift build`) — it must compile.

## Step 2 — New file `Sources/Wffl/LLM/CleanupPipeline.swift`

This file contains the scanner (Pass A), the two LLM pass drivers (B, C), and the
assembler (Pass D). Write it exactly to this specification.

### 2.1 Data types

```swift
struct CleanupLine {
    let index: Int        // 0-based global line number
    let timecode: String  // "3:42" or "1:02:07" (no brackets)
    var text: String      // text after the timecode, glossary-corrected by Pass A
}

struct CleanupEdit {
    let line: Int
    let old: String
    var new: String
    var confidence: Double
}

struct CleanupParagraph {
    let start: Int        // first line index (inclusive)
    let end: Int          // last line index (inclusive)
    var heading: String?  // optional "### Topic" title inserted before it
}
```

### 2.2 Pass A — `CleanupScanner`

`static func scan(transcript: String) -> (lines: [CleanupLine], suspects: [Int: [String]])`

1. Split on `\n`. Parse each non-empty line with the regex
   `^\[(\d{1,2}:)?\d{1,2}:\d{2}\]\s*(.*)$`. Lines that do not match (no timecode)
   are appended to the text of the previous parsed line (or skipped if there is
   none). Empty-text lines are dropped.
2. Decide `allowForce` the same way the live path's gate does:
   - `Prefs.vocabMode == "on"` → `true`
   - `Prefs.vocabMode == "off"` → `false`
   - `"auto"` → `true` iff the raw transcript contains any
     `Vocabulary.shared.tripwires` text, matched case-insensitively (also try each
     tripwire with spaces removed when its `collapsible` flag is true).
3. For every line: `text = Vocabulary.shared.correct(text, allowForce: allowForce)`.
4. Drop a line whose corrected text is identical (case-insensitive, trimmed) to the
   previous kept line's text (ASR duplicate).
5. Strip standalone fillers conservatively: remove whole-word tokens `Um`, `Uh`,
   `Uhm`, `Hmm` (case-insensitive, `\b(um+|uh+|hmm+)\b[,.]?\s*` at most — do NOT
   strip "you know" or "like"; those need context and Pass B handles them via edits
   if at all). Collapse resulting double spaces. Drop the line if it becomes empty.
6. Re-index kept lines 0..n-1 (indices used by Passes B–D refer to these).
7. `suspects[lineIndex] = Vocabulary.shared.nearMisses(in: line.text)` for lines
   where the result is non-empty.

### 2.3 Pass B — `StructurePass`

`func run(lines: [CleanupLine], suspects: [Int: [String]], client: LLMClient, progress: ...) async throws -> (paragraphs: [CleanupParagraph], edits: [CleanupEdit])`

- Window the lines: **50 lines per window** (last window takes the remainder).
  Windows do not overlap; paragraphs cannot span windows (acceptable seam cost).
- For each window build the user message:

  ```
  Suspect words flagged by a scanner (may be garbled Gujarati/Sanskrit terms): <comma-joined suspects for lines in this window, or "none">

  Glossary of correct spellings: <Vocabulary.shared.glossary>

  Transcript lines (format: INDEX [TIMECODE] TEXT):
  12 [3:42] so the next thing gun curtain swami said was
  13 [3:45] that seva is its own reward
  ...
  ```

- System prompt, verbatim:

  ```
  You analyze raw speech-to-text meeting transcript lines. You never rewrite the
  transcript. You output ONLY a single JSON object, no markdown fences, no prose:

  {"paragraphs":[{"start":12,"end":15,"heading":null}],
   "edits":[{"line":12,"old":"gun curtain swami","new":"Gunkirtan Swami","confidence":0.9}]}

  Rules:
  - "paragraphs": group consecutive line indexes into paragraphs of one speaker turn
    or one thought each. Every input line index must appear in exactly one paragraph,
    in order, with no gaps and no overlaps. "heading" is null unless the discussion
    clearly moves to a new topic at that paragraph — then a 2-5 word title.
  - "edits": ONLY for text that is clearly a speech-recognition error: a garbled
    word/phrase phonetically close to a glossary term, an obvious mis-recognition
    fixable from context, or a filler phrase ("you know", false starts) safe to drop
    (use "new":""). "old" must be copied EXACTLY from the line's text. Keep edits
    short — a few words, never a whole line. "confidence" 0.0-1.0: use below 0.7
    whenever unsure; a reviewer model checks those. Never invent content, never
    change wording that is already plausible, never touch numbers or timecodes.
  - If nothing needs editing, "edits" is [].
  ```

- Call `client.complete(system:user:)`. Parse the reply:
  - Trim; if it contains ```` ```json ```` fences or any leading prose, extract the
    substring from the first `{` to the last `}` before parsing with
    `JSONSerialization`.
  - On parse failure: retry the window **once** with the same messages. On second
    failure, use the fallback grouping for the window (below) and no edits. The
    pipeline never throws for a single bad window.
- Validate per window:
  - Paragraph list must exactly tile the window's indexes in order (sort by `start`,
    check `start <= end`, first `start` == window start, each next `start` ==
    previous `end + 1`, last `end` == window end). If invalid → **fallback
    grouping**: paragraphs of up to 4 consecutive lines, breaking early whenever the
    gap between consecutive line timecodes exceeds 15 seconds.
  - Each edit: `0 <= line < lines.count`, and `lines[line].text` must contain
    `edit.old` (exact match first; else one case-insensitive attempt, replacing
    `old` with the matched original casing region). Invalid edits are dropped
    silently. Clamp confidence to 0...1.

### 2.4 Pass C — `ArbiterPass`

`func run(edits: [CleanupEdit], unresolvedSuspects: [Int: [String]], lines: [CleanupLine], client: LLMClient) async -> [CleanupEdit]`

- Input spans: (a) Pass-B edits with `confidence < 0.75`; (b) suspect words from
  Pass A that no Pass-B edit's `old` contains (send as edits with `old` = the
  suspect word, `new` = "", confidence 0 — the arbiter proposes the fix).
- High-confidence Pass-B edits (>= 0.75) bypass the arbiter and are returned as-is.
- If there are no spans, return immediately.
- Batch spans **10 per request**. For each span include ±2 lines of context:

  ```
  Span 3:
  Context:
  [3:38] and then after the katha finished
  [3:42] so the next thing gun curtain swami said was    <-- line with the span
  [3:45] that seva is its own reward
  Text in question: "gun curtain swami"
  Proposed replacement: "Gunkirtan Swami"   (or: Proposed replacement: none — suggest one or reject)
  ```

- System prompt, verbatim:

  ```
  You are the senior reviewer for speech-to-text corrections in meeting transcripts
  that mix English with Gujarati/Sanskrit (BAPS Swaminarayan satsang vocabulary).
  For each numbered span decide whether the text is a recognition error and what it
  should say, using the context and this glossary: <Vocabulary.shared.glossary>

  Output ONLY a JSON array, one object per span, no fences, no prose:
  [{"span":3,"action":"replace","new":"Gunkirtan Swami"}]

  "action" is one of:
  - "replace": the text is wrong; "new" is the correction (short, only the span).
  - "reject": leave the transcript as transcribed (use when unsure — changing
    correct text is worse than leaving an error).
  Never invent content that was not plausibly said.
  ```

- Parse defensively (same first-`[`-to-last-`]` extraction). If a batch's call
  throws or fails to parse after one retry, treat every span in that batch as
  "reject" and continue — **the arbiter failing must never fail the cleanup**.
- Result: accepted/replaced spans become edits with confidence 1.0; rejected spans
  are dropped. Return bypass edits + arbiter-approved edits.
- Use `os_log`/`print` to log counts: `cleanup: N edits (H high-conf, E escalated, A approved)`.

### 2.5 Pass D — `CleanupAssembler`

`static func assemble(lines: [CleanupLine], paragraphs: [CleanupParagraph], edits: [CleanupEdit]) -> String`

1. Apply edits: group by line; for each, replace the **first occurrence** of `old`
   in that line's text with `new` (re-verify containment; drop silently if the text
   changed since validation). `new == ""` also removes an immediately following
   double space / leading space artifact.
2. Drop lines whose text became empty after edits.
3. For each paragraph in order:
   - If `heading` is non-nil/non-empty: emit `### <heading>` line, blank line.
   - Emit `**[<timecode of first surviving line in range>]** ` followed by the
     texts of the paragraph's surviving lines joined with a single space.
   - Blank line between paragraphs.
4. Return the joined Markdown, trimmed.

## Step 3 — Rewrite `Sources/Wffl/LLM/TranscriptCleanupService.swift`

Replace the whole file body: keep `struct TranscriptCleanupService { let config: LLMConfig }`
and the public `func clean(transcript: String) async throws -> String`, delete the
old `systemPrompt`, `chunkBudget`, and chunk loop. New `clean`:

```swift
func clean(transcript: String) async throws -> String {
    let (lines, suspects) = CleanupScanner.scan(transcript: transcript)
    guard !lines.isEmpty else { return transcript }

    let structureClient = LLMClient(config: config)   // config.model = cleanupModel (4b)
    var arbiterConfig = config
    if config.kind == .ollama { arbiterConfig.model = Prefs.arbiterModel }
    let arbiterClient = LLMClient(config: arbiterConfig)

    let structure = try await StructurePass().run(lines: lines, suspects: suspects,
                                                  client: structureClient)
    let finalEdits = await ArbiterPass().run(edits: structure.edits,
                                             unresolvedSuspects: suspects,
                                             lines: lines, client: arbiterClient)
    return CleanupAssembler.assemble(lines: lines,
                                     paragraphs: structure.paragraphs,
                                     edits: finalEdits)
}
```

Notes:
- `config` arrives from `Prefs.cleanupLlmConfig()` with `disableThinking = true`
  already set by AppState — leave AppState's call site unchanged.
- Non-Ollama providers use the single configured model for both passes (arbiter
  config only swaps the model when `kind == .ollama`).
- Only Pass B can throw (total structure failure after retries or network death);
  Pass C never throws.

## Step 4 — `Sources/Wffl/Support/Prefs.swift`

Add below `cleanupModel`:

```swift
    // Arbiter tier for the cleanup pipeline: reviews only the low-confidence
    // spans the small model escalates, so it never reads a whole transcript.
    static var arbiterModel: String { d.string(forKey: "arbiterModel") ?? "gemma4:12b-mlx" }
```

No migration needed — the key has never existed, so the default applies everywhere.

## Step 5 — `Sources/Wffl/Views/SettingsView.swift`

Next to the existing "Transcript cleanup model" picker (~line 260), add an identical
picker bound to `@AppStorage("arbiterModel") private var arbiterModel = "gemma4:12b-mlx"`,
labeled `"Cleanup arbiter model"`, with the same "show current value if not in
ollamaModels" pattern used by the cleanup picker. Add a one-line footnote text under
it: `"Reviews uncertain corrections; only sees flagged snippets, not the whole transcript."`

## Step 6 — Unit tests `Tests/WfflTests/CleanupPipelineTests.swift`

Add tests that need no LLM (check how existing tests in `Tests/` are structured and
match the module/import style):

1. **Scanner parses & dedupes**: feed a 6-line transcript with one `[1:02:07]`
   long-form timecode, one exact duplicate line, one `um` filler token, one
   continuation line without a timecode → assert line count, indexes, timecodes,
   merged continuation, filler removed.
2. **Assembler edit safety**: an edit whose `old` is not in the line is dropped;
   an edit with `new: ""` removes the phrase; paragraph output starts with
   `**[timecode]**`; a heading paragraph emits `### `.
3. **Fallback grouping determinism**: (if implemented as a testable function)
   grouping breaks at >15s timecode gaps and at 4 lines.
4. **JSON extraction**: parser recovers the object from a reply wrapped in
   ```` ```json ... ``` ```` fences with a prose preamble.

`swift test` must pass.

## Step 7 — Version bump + build + install + smoke test

1. `Support/Info.plist`: `CFBundleShortVersionString` → `1.2.0`,
   `CFBundleVersion` → `4`.
2. `bash scripts/bundle.sh` → must end with `Built dist/Wffl.app`.
3. Install (replaces the running app):
   ```bash
   osascript -e 'quit app "Wffl"' 2>/dev/null; sleep 1
   ditto dist/Wffl.app /Applications/Wffl.app.new && rm -rf /Applications/Wffl.app && mv /Applications/Wffl.app.new /Applications/Wffl.app
   codesign --verify --deep /Applications/Wffl.app && open /Applications/Wffl.app
   ```
   (If `ditto`-then-swap fails on permissions, `rm -rf /Applications/Wffl.app && ditto dist/Wffl.app /Applications/Wffl.app` is fine.)
4. Smoke test in the running app (computer-use): open the existing 37-minute
   meeting (the one that previously hit the truncation error) → Transcript tab →
   **Re-clean / Clean Up**. Expect:
   - progress label mentions `gemma3:4b`;
   - it completes with NO "reply truncated" error and no doom-loop error;
   - output is Markdown paragraphs starting with `**[M:SS]**` timecodes that all
     exist in the raw transcript (spot-check 3);
   - glossary names (e.g. "Gunkirtan Swami", "Bhagwan Swaminarayan") are spelled
     correctly where the raw text had near-misses;
   - the log line `cleanup: N edits (...)` appears (Console.app or `log stream
     --predicate 'process == "Wffl"'` if using os_log; skip if print-only).
5. Verify the stored row: `sqlite3` the app DB (same path used in the previous
   session's verification) — the newest `cleaned_transcripts` row has
   `status = 'completed'` and `model = 'gemma3:4b'`.

## Step 8 — Commit (path-scoped — CRITICAL)

The index holds a large unrelated staged rename. Commit ONLY this work's paths:

```bash
git add Sources/Wffl/LLM/CleanupPipeline.swift Tests/WfflTests/CleanupPipelineTests.swift
git commit -m "Edit-list cleanup pipeline: scan/structure/arbiter/assemble — truncation-proof

Model outputs decisions (paragraphs, headings, micro-edits) instead of
rewriting the transcript; Swift applies them. gemma3:4b structures,
gemma4:12b-mlx arbitrates escalated spans only. Bump to 1.2.0.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" \
  -- Sources/Wffl/LLM/CleanupPipeline.swift \
     Sources/Wffl/LLM/TranscriptCleanupService.swift \
     Sources/Wffl/Support/Prefs.swift \
     Sources/Wffl/Views/SettingsView.swift \
     Sources/Wffl/Transcription/Vocabulary.swift \
     Tests/WfflTests/CleanupPipelineTests.swift \
     Support/Info.plist \
     PLAN-cleanup-pipeline.md
```

Then `git show --stat HEAD` and confirm ONLY those files are in the commit. Do not
push; do not touch the staged Meetily→Wffl rename.

## Acceptance checklist

- [ ] `swift build` and `swift test` clean
- [ ] 37-minute meeting cleans successfully, no truncation error, on first try
- [ ] Timecodes in output are a subset of raw-transcript timecodes (never invented)
- [ ] Summary path still uses `gemma3:12b` (untouched — verify badge in Summary tab)
- [ ] Live correction path untouched (`correctionModel` still `gemma3:4b`)
- [ ] `/Applications/Wffl.app` reports version 1.2.0 (`mdls -name kMDItemVersion` or About)
- [ ] Path-scoped commit contains exactly the 8 listed files
