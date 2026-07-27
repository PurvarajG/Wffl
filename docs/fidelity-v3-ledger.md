# Fidelity v3 — role-handoff ledger

> ⚠️ **CLOSED 2026-07-27.** Its plan is superseded — see the banner in
> [`PLAN-fidelity-v3.md`](../PLAN-fidelity-v3.md). **T-02** stays BLOCKED (its
> finding was correct and is now explained), and **T-06** is **SUPERSEDED** by
> `PLAN-engine-and-pack-v1.md` T-05, which deletes `TranscriptCorrector`
> entirely. Do not resume either. New work logs to `docs/engine-pack-ledger.md`.

Format per §0.2 of PLAN-fidelity-v3.md. Baseline: `7745bf6`, build clean, 89 passed / 1 skipped / 0 failed.

## T-01 — Fix the headless self-test deadlock
- rev: uncommitted
- builder: WfflApp.swift:52-68. `Task {}` → `Task.detached` (matches
  AppState.swift:553) as the plan specifies. Discovered a SECOND deadlock the
  plan didn't anticipate: even with `Task.detached`, `sema.wait()` blocks the
  main thread's run loop, and `Vocabulary.shared`'s first init calls
  `DispatchQueue.main.sync` (Vocabulary.swift:416, NSSpellChecker hop) from the
  detached task — main queue never drains, deadlock persists. Confirmed via
  `sample` on the hung process (stack: detached-task thread parked in
  `_dispatch_sync_f_slow` → `__DISPATCH_WAIT_FOR_QUEUE__`, main thread parked
  in `_dispatch_semaphore_wait_slow` at the old WfflApp.swift:65). Fix: replace
  `DispatchSemaphore` with `RunLoop.main.run()` — keeps GCD main-queue work
  draining; the detached task still calls `exit()` directly on completion, so
  the run loop never needs to be told to stop. No other file touched; normal
  (non-headless) launch path unaffected — the run-loop call is inside the
  `--transcribe` branch only. Also added a stderr "transcribing..." progress
  line per the Now/Done text ("Print progress to stderr").
- tester: `swift build` clean. Ran the fixed binary
  (`.build/arm64-apple-macosx/debug/Wffl`) against `clip_A.wav`
  (893–930s of the Diversity in Satsang recording, regenerated per
  measurements.md §3) with the `base.en` model: exit 0, wall time 1s,
  non-empty timestamped output containing "traced back" (clip A's expected
  span, corroborating measurements.md §3 row A). Non-existent model id
  (`nonexistent-model-xyz`) exits 2 with `model ... not downloaded`, no hang.
  Full suite: `swift test` → 89 passed / 1 skipped / 0 failed — matches
  baseline, no regression.
- auditor: CLEAR — Task.detached confirmed, no MainActor.run reintroduced,
  non-headless path untouched (diff entirely inside --transcribe branch),
  exit() termination unconditional regardless of run-loop state. Noted
  RunLoop.main.run() could theoretically return early if no run-loop sources
  are attached, but did not re-run the binary to check — deferred to Tester's
  empirical result. Tester's run above (exit 0, 1s wall, correct output)
  already covers that gap.
- status: DONE

## T-11 — Gate and batch the LLM corrector
- rev: uncommitted
- builder: correctAll now calls the LLM only for near-miss/high-OOD segments;
  prompts include at most 49 phonetically supported terms for that segment.
- tester: TranscriptCorrectorTests 17/17 green, including plain-English
  no-call gating.
- auditor: FINDING — predicate was bookkeeping only; both live and batch paths
  still invoked the client.
- builder: both paths now bypass `correct` entirely for ineligible text while
  retaining it in rolling context.
- tester: TranscriptCorrectorTests 17/17 green after real no-call enforcement.
- auditor: FINDING — decoder contextual glossary had a character bound but no
  49-term bound.
- builder: contextual decoder glossary now stops at 49 terms as well.
- tester: build green after decoder glossary term cap.
- auditor: CLEAR — real no-call gating, both 49-term caps, shrink safety, and
  serialized correction behavior confirmed.
- status: DONE

## T-10 — Honest duration, headings, reject reasons
- rev: uncommitted
- builder: duration persistence now uses AVAudioFile sample-count duration,
  falling back to segment extent only if the audio file cannot be opened.
- builder: corrector attempt ledger now records `llm_unavailable`,
  `rejected_by_sanitize`, or `no_change` rather than a conflated reason.
- tester: TranscriptCorrectorTests 16/16 green; duration build green.
- auditor: CLEAR — sample-count duration is targeted and diarization-safe;
  correction reasons are distinct; heading grounding/metric path unchanged.
- status: DONE

## T-09 — Preserve interior timecodes
- rev: uncommitted
- builder: subdivideLongParagraphs now splits on >30 seconds elapsed even for
  short paragraphs, while retaining existing line-count and >15s gap guards.
- tester: CleanupPipelineTests/testSubdivideLongParagraphsCapsElapsedTime
  green after correcting the test target.
- auditor: FINDING — test lacked exact elapsed-cap and heading-placement cases.
- builder: added 30s/31s boundary and heading-on-first-subparagraph coverage.
- tester: elapsed-boundary/heading test green; prior 20-second gap test green.
- auditor: CLEAR — exact timecode cap, boundary, heading behavior, and no
  invented/mutated timecodes confirmed.
- status: DONE

## T-08 — Fix glossary corpus and brahmand collision
- rev: uncommitted
- builder: added the Paramhansa corpus as ordinary terms, removed `brahmand`
  to eliminate its one-edit collision with Brahmanand, and select glossary
  prompt terms phonetically from prior meeting context when evidence exists.
- tester: added corpus round-trip and Brahmanand-collision coverage; PENDING
  run.
- builder: test exposed `brahmand` persisted in pre-existing seeded vocabulary
  files; load migration now retires that obsolete default before building the
  correction pool.
- tester: TranscriptFidelityTests 11/11 green, including Paramhansa corpus
  round-trip and Brahmanand collision coverage.
- auditor: FINDING — no-match context still injected the static glossary, and
  migration deleted indistinguishable user-owned `brahmand` terms.
- builder: no-match context now receives no glossary; removed destructive
  migration and protect Brahmanand directly against legacy `brahmand` snaps.
- tester: TranscriptFidelityTests 12/12 green after the audit fixes, including
  no-match context prompt coverage.
- auditor: FINDING — empty context still injected the static glossary.
- builder: empty context now returns no prompt; expanded no-evidence coverage.
- tester: TranscriptFidelityTests 12/12 green after empty-context fix.
- auditor: FINDING — contextual term budget omitted the fixed prompt wrapper,
  so total initial prompt could reach 412 characters.
- builder: glossary budget now accounts for context and wrapper; added a
  maximum-prompt regression test.
- tester: TranscriptFidelityTests 13/13 green, including 400-character total
  prompt bound.
- auditor: CLEAR — full contextual prompt is ≤400 including wrapper; all
  no-evidence and corpus/collision safeguards hold.
- status: DONE

## T-07 — Correct the decoder defaults for devotional content
- rev: uncommitted
- builder: Prefs now selects full-precision `large-v3-turbo` for devotional
  defaults; VocabularyGate promotes an unset profile to devotional only when
  its evidence threshold opens, preserving an explicit user profile choice.
- tester: PrefsProfileTests 2/2 green: gate-open uses fp16 + beam, explicit
  general/profile selection wins.
- auditor: FINDING — gate-selected profile needed provenance so it would not
  become a permanent implicit user choice.
- builder: added a gate-selection marker; each new auto gate clears only a
  prior gate-selected profile, leaving a user-set profile intact.
- tester: PrefsProfileTests 3/3 green, including reset of a prior automatic
  profile selection at the next auto gate.
- auditor: FINDING — a Settings picker choice did not clear the automatic
  provenance marker, so it could later be erased.
- builder: SettingsView now marks picker changes explicit; added an explicit
  devotional-after-auto regression case.
- tester: PrefsProfileTests 4/4 green, including explicit profile provenance
  after an automatic selection.
- auditor: FINDING — live RecorderController bypassed effective devotional
  model/gate settings, and generic Settings observation could mark automatic
  selection as explicit.
- builder: RecorderController now uses effective model/vocab settings; the
  Settings Picker marks provenance only in its user-selection binding setter.
- tester: PrefsProfileTests 4/4 green after the live-path and Settings binding
  fix; build clean.
- auditor: FINDING — automatic devotional selection could leak into the next
  meeting before its gate mode was resolved.
- builder: both new-meeting entry points clear only gate-selected provenance
  before resolving effective profile/model/vocabulary settings.
- tester: PrefsProfileTests 4/4 green after new-meeting reset; build clean.
- auditor: FINDING — file import/retranscription resolved engine before stale
  automatic profile provenance was cleared.
- builder: moved the clear before `resolveEngineSource()` in both file entry
  paths and removed the now-late inner clear.
- tester: PrefsProfileTests 4/4 green after file-entry ordering fix; build
  clean.
- auditor: CLEAR — reset precedes live/file effective-setting resolution;
  explicit selection and general behavior remain protected; diff check clean.
- status: DONE

## T-02 — Acceptance corpus + accuracy gate
- rev: uncommitted
- builder: Tests/WfflTests/AcceptanceCorpusTests.swift added (3 unconditional
  span tests against isolated clips via `WhisperFileTranscriber.transcribe` +
  1 WFFL_ACCEPTANCE=1-gated full-file metrics report). Deleted
  BilingualComparisonTests.swift (asserted nothing, bypassed the gate/vocab
  layers — superseded per the plan's own framing of it as "the skip-by-default
  manual benchmark this task replaces").
- tester: ran narrow filter. Span B (RanAway) is RED as expected. Spans A
  (TracedBack) and C (TyagisTyagi) are GREEN on isolated ~30-37s clips run
  through the production path — NOT the expected all-red state.
- **BLOCKED — see live message to human.** Verified independently: running
  the FULL 20:34 recording through `WhisperFileTranscriber.transcribe` (the
  exact function T-01's `--transcribe` CLI calls, which the plan itself names
  "the production path") preserves all three spans intact — none are deleted.
  This contradicts the DB-observed transcript in measurements.md, and
  corroborates §10's unresolved open question: the DB transcript's 74
  contiguous ≤20s segments match `AudioChunker`/live-path granularity, not
  `WhisperFileTranscriber`'s 5-minute chunking. Strong evidence the deletion
  happened on the **live** path (`WhisperLiveTranscriber` + `AudioChunker`),
  not the offline file path. This is the §2 open-question answer the plan
  said would change scope — surfacing to the human per explicit instruction
  rather than proceeding.
- status: BLOCKED

## T-06 — resumed by human authorization
- rev: uncommitted
- builder: replaced the split set-based shrink checks with occurrence-paired
  raw-token LCS validation; each removed span is independently filler/stutter
  allowed or paired with its own phonetically supported replacement.
- tester: TranscriptCorrectorTests 16/16 green, including repeated phrase,
  repeated filler, shared-word, repeated phonetic deletion, and insertion cases.
- auditor: CLEAR — paired alignment preserves I1/I3 and the N→1 collapse.
- status: DONE
- human: authorized a fourth T-06 loop to resolve the final occurrence-aware
  raw-token alignment finding.
- builder: replaced raw-token set membership with occurrence-aware LCS matching;
  added repeated multi-word filler coverage.
- tester: TranscriptCorrectorTests 13/13 green, including repeated multi-word
  filler deletion and repeated real-phrase rejection.
- auditor: FINDING — a filler token stored in an authorization set could
  authorize deletion of a different real occurrence of that same word.
- builder: fixed — authorization is now per content-token occurrence, mapped
  from the occurrence-aware raw-token alignment; added the shared-word case.
- tester: TranscriptCorrectorTests 14/14 green, including repeated filler and
  shared-word real-deletion coverage.
- auditor: FINDING — phonetic additions remain pooled across occurrences, and
  raw/content LCS alignments are independent. A single occurrence-paired
  alignment is required before this task can be accepted.
- builder: replaced the split raw/content checks with one raw-token LCS that
  pairs every removed span only with reply tokens between its same anchors;
  filler, stutter, and phonetic replacement are checked per span.
- tester: TranscriptCorrectorTests 15/15 green after replacement, including
  the repeated phonetic-deletion regression case.
- auditor: FINDING — reply-only gaps bypassed no-invention validation.
- builder: fixed — reply-only tokens now require known spelling plus phonetic
  support in the original; added an unsupported-insertion regression case.
- tester: TranscriptCorrectorTests 16/16 green, including unsupported
  reply-only insertion rejection.
- auditor: CLEAR — occurrence-paired validation enforces I1/I3, retains the
  shared filler/stutter exceptions, and keeps N→1 phonetic collapse bounded.
- status: DONE
- status: IN REVIEW

- human decision: target the live path (WhisperLiveTranscriber + AudioChunker,
  driven via feed48k/finish like RecorderController does), not
  WhisperFileTranscriber. Rewrote AcceptanceCorpusTests.swift accordingly:
  one testLiveSpansSurviveProductionPath() feeding the full recording through
  the live transcriber once (1s slices, upsampled 16k->48k losslessly since
  Resampler.to16k averages triplets), asserting all 3 spans against the
  single shared run. Kept testFullFileCorpusMetrics on the offline path
  (unaffected by the path decision — it's a general accuracy report, not an
  incident reproduction) and deleted BilingualComparisonTests.swift.
- builder/tester: ran twice (62s each). Consistent across both runs: span B
  RED (content genuinely missing, matches "He's like, I'm gone" non-sequitur
  from measurements.md), span C RED (but for a DIFFERENT reason than
  deletion — cross-checked docs/fidelity-v3/observed-app-raw.txt line 46/56/58:
  even the original historical bug output never rendered the possessive
  "Tyagi's Tyagi", only "Tyagi Tyagi"/"the Tyagi is Tyagi" — so this is an
  ASR spelling/grammar accuracy gap, not an I5 silent-deletion; T-04 (which
  only touches the delete-vs-placeholder decision, not word-level spelling)
  may never turn this green). Span A is GREEN on this harness both times —
  cross-checked observed-app-raw.txt line 55, which shows the exact damage
  signature quoted in measurements.md §3 ("It's a good question. as he
  becomes a Tyagi...", "traced back" spliced out) — so span A's deletion is
  historically real, but this harness's feed pattern (uniform 1s slices from
  a clean file decode) doesn't reproduce the exact live AudioChunker
  boundaries the original recording session had, and consistently doesn't
  trigger the gate for that specific borderline segment. 2 runs, same result
  both times — not flaky, just a structurally different chunk boundary than
  whatever produced the original recording's grouping.
- **Escalated to human directly** rather than force a fix: current state is
  2 of 3 span assertions reliably RED (B, C) via the correct code path; A is
  reliably GREEN despite being a real historical defect, because this harness
  cannot exactly replay the original live recording's chunk timing.
- human decision: accept as-is, proceed to T-03. Noted: T-04's fix (removing
  the run.count>=2 shortcut, adding corroboration beyond noSpeechProb) is a
  general code change, not tuned to this harness, so it should still flip B
  (and possibly A, opportunistically) regardless of A's non-reproduction here.
  C may never go green via T-04 alone since its failure mode is ASR spelling
  drift, not silent deletion — flagged for the T-04 checkpoint, not a T-02
  blocker.
- tester: full `swift test` — 90 tests total (was 89; net +1: 3 new
  AcceptanceCorpusTests methods − 1 removed BilingualComparisonTests test).
  88 passed / 1 skipped (testFullFileCorpusMetrics, WFFL_ACCEPTANCE-gated) /
  2 failures (both XCTAssertTrue failures inside the single
  testLiveSpansSurviveProductionPath — spans B and C, by design). No
  previously-passing test regressed. This test now costs ~62s on every
  default `swift test` run until T-04 lands and it goes green — flagging for
  awareness, not treating as a defect (it's the cost of testing the real
  live path with real audio).
- auditor: 2 minor findings, both doc-only (stale line citation for
  `finish()`; "losslessly" overstated — the 3x-repeat/average round-trip is
  within ~1 ULP of Float32, not bit-exact). Everything else CLEAR: harness
  calls real `WhisperLiveTranscriber` via public API only, no re-implemented
  gate/vocab logic; reference correctly labeled UNVERIFIED; span assertions
  depend only on literal substring presence; WFFL_ACCEPTANCE gate correct;
  BilingualComparisonTests deletion loses no real coverage (it only had two
  XCTFails on missing fixtures); Collected's locking is safe; no Sources/
  changes (WfflApp.swift diff belongs to already-audited T-01, sitting
  uncommitted in the same tree).
- builder: fixed both comments (WfflApp.swift-line-range citation split into
  the correct feed48k/finish lines; "round-trips losslessly" → "round-trips
  within ~1 ULP"). Build clean, comment-only change.
- status: DONE

## T-03 — Preserve genuine decoder output
- rev: uncommitted
- builder: added `let decoderText: String` (required, no default) to
  `WhisperSegment` (WhisperContext.swift:4-13). Set at all 4 production
  construction sites: WhisperContext.swift:181 (raw decode — decoderText ==
  text, this IS the raw output), :210 (HallucinationGate placeholder —
  decoderText == placeholderText, it's synthetic, no separate raw form
  exists), ParakeetLiveTranscriber.swift:89 and :131 (decoderText = the
  pre-correction `text` var, captured before `Vocabulary.shared.correct`).
  Extended `TranscriptSegment.new(...)` with an optional `rawText: String? =
  nil` param (Models.swift:60-61, defaults to `text` — Swift can't default a
  param to another param's value, so this keeps every existing call site,
  including ~13 test sites, compiling unchanged). Wired the two real
  production call sites to pass it explicitly: AppState.swift:576
  (`rawText: $0.decoderText`) and RecorderController.swift:215 (`rawText:
  s.decoderText`) — both the file-import and live-recording paths, matching
  the auditor check that both must change together. Scope note: Parakeet
  wasn't in the plan's named read range, but shares the same `WhisperSegment`
  type and the same two `TranscriptSegment.new` call sites — leaving its 2
  construction sites unset would have left `decoderText` silently wrong for
  Parakeet-transcribed meetings, so fixed those too as the minimum needed to
  keep I4 consistent app-wide (not new scope, just not leaving a hole next to
  the fix).
- tester: extended TranscriptProvenanceTests with
  testDecoderTextSurvivesIntoRawText — constructs a WhisperSegment with
  decoderText "gun curtain swami" / text "Gunkirtan Swami" (the codebase's
  standard near-miss fixture), threads it through the exact
  `TranscriptSegment.new(rawText:)` shape AppState.swift/RecorderController
  use, asserts rawText holds the uncorrected spelling. Narrow filter: 7/7
  pass. Full suite: 91 tests (was 90), 88 passed / 1 skipped / 2 failures —
  same 2 failures as the T-02 checkpoint (span B, span C; expected, unrelated
  to this change), no regression.
- auditor: CLEAR. All 4 WhisperSegment construction sites correct;
  decoderText is `let` and never reassigned by either mutation loop;
  HallucinationGate's pass-through branch needs no change (value semantics);
  both production call sites (file + live, both engines) pass .decoderText
  as rawText:; Parakeet extension confirmed as a required consequence of the
  non-optional field shape, not independent scope creep; new test is
  non-redundant with the pre-existing one. Build clean.
- status: DONE

## T-04 — Hallucination gate must never delete silently
- rev: uncommitted
- builder: WhisperContext.swift — HallucinationGate.apply (~line 200-240).
  (1) `guard run.count >= 2` → `guard !run.isEmpty`: every flagged run,
  including a run of 1, now emits a placeholder; the empty-run guard
  prevents a `run[0]` crash on the common no-op flushRun() call before a
  normal kept segment. (2) Added corroboration: a segment is only flagged
  when noSpeechProb > 0.6 AND Vocabulary.shared.outOfDictionaryFraction(text)
  > 0.7 — reused CleanupScanner.gibberishThreshold's calibrated value (same
  signal, same number) rather than referencing the symbol directly (would
  create a Transcription→LLM layer dependency). (3) Added a
  droppedSegmentCount static counter (NSLock-guarded — static var, Swift 5
  language mode, not enforced Sendable but real code, worth the lock) exposed
  for metrics. apply()'s signature is unchanged ([WhisperSegment] in/out), so
  no call site beyond WhisperContext.swift itself needed touching.
- tester: new HallucinationGateTests.swift, 9 cases — lone-flagged-survives,
  run-of-3 collapse unchanged, coverage-never-shrinks (3 variants),
  corroboration-keeps-fluent-text-despite-high-noSpeechProb, below-threshold-
  keeps-even-gibberish, run-of-1-adjacent-to-run-of-2 (no merge/duplicate),
  drop-counter-increments. All 9 pass.
- **CHECKPOINT (per human's explicit request): re-ran T-02's
  testLiveSpansSurviveProductionPath after this fix. Span B is STILL RED —
  same failure, same garbled substitute text ("the Mahant was made of the
  Mahant. He's like, I'm gone.") as before T-04, byte-for-byte the same
  defect shape across 3 runs now (2 pre-T-04, 1 post-T-04).** Investigated:
  no `[unclear audio / non-English — not transcribed]` placeholder appears
  anywhere near the lost content, in any of the 3 runs. Since the OLD gate's
  only failure modes were "drop with no trace" (run of 1) or "collapse to
  placeholder" (run of 2+) — and neither artifact is present, before or
  after — this segment's noSpeechProb was very likely never above 0.6 in the
  first place. **HallucinationGate was never involved in span B's loss.**
  The actual defect looks like a raw Whisper mis-decode/hallucination on
  that specific audio span (the model producing fluent, confidently-repeated
  wrong text — "the Mahant was made of the Mahant" — not flagged as
  low-confidence at all). T-04 as specified (gate corroboration + always-
  placeholder) cannot fix a defect the gate was never applying to.
  Escalating to human per their explicit T-04 checkpoint instruction rather
  than looping further on gate tuning, which would not address this.
- human decision: accept T-04 as done. The fix correctly addresses the
  mechanism the plan specified (silent gate deletion — I5) and remains
  independently valuable (protects against real gate-caused losses
  elsewhere, e.g. whatever gate behavior produced span C's context, and any
  future recording where noSpeechProb-driven deletion actually is the
  cause). Span B's real root cause (a raw ASR mis-decode/hallucination, not
  a gate action) is a different defect outside T-04's mechanism — noted here
  for future investigation, not blocking the plan. Span A remains
  unreproduced on this harness (T-02 finding, unrelated to T-04). Span C
  remains a spelling/grammar gap (T-02 finding, unrelated to T-04). None of
  the 3 span assertions flip fully green from T-04 alone, but T-04's own
  unit tests (9/9) correctly prove the specified mechanism now holds.
- tester: full `swift test` — 100 tests (was 91, +9 HallucinationGateTests).
  97 passed / 1 skipped / 2 failures — same 2 as before (span B, span C),
  no regression.
- auditor: 1 low-severity finding — `>` vs CleanupScanner's `>=` at exactly
  0.7 (the comment claims shared calibration; true for the value, not the
  operator). Everything else CLEAR: empty-run guard prevents the crash;
  corroboration is a strict AND with correct keep-on-failure; droppedSegment
  Count's lock covers both read and write; adjacency test is meaningful;
  placeholderText special-casing downstream (CleanupPipeline.swift:96/432/
  453/484, WhisperLiveTranscriber.swift:82-86) unaffected; .general profile
  structurally unaffected (no profile parameter exists); new tests are real,
  not tautological.
- builder: fixed — `>` → `>=` at WhisperContext.swift:235, matching
  CleanupScanner.gibberishThreshold's operator exactly. Narrow filter: 9/9
  still pass. Build clean.
- status: DONE

## T-05 — Live tail drain completeness
- rev: uncommitted
- builder: AudioChunker.swift — `pop(force:)` now returns a 3-case enum
  `PopResult { .ready(samples,offset), .droppedSilence, .empty }` instead of
  an optional tuple, so callers can distinguish "nothing ready" from
  "consumed and dropped as silence, but more may be pending" — the two cases
  the old single `nil` collapsed together. `silenceRMS`/`containsSpeech`
  logic untouched, only the pop/take return type and the 4 caller sites'
  drain control-flow changed, per §1.2. Traced the actual failure mode:
  when >20s of silence sits ahead of real speech in `pending` (a backlog —
  e.g. right before `finish()`, or after a `bestCutPoint()` cut leaves a
  remainder), a single non-looping force-pop finds/drops the silent portion
  and returns, leaving the real speech behind it never popped. Fixed all 4
  call sites: WhisperLiveTranscriber.swift `maybeProcess` (recursive →
  iterative `while` loop over the 3 cases, no unbounded-recursion risk since
  `pending` strictly shrinks each `.droppedSilence` step) + its
  `processChunk`'s trailing continuation changed from hardcoded
  `force: false` to `force: finished` (this was the other half of the bug:
  even with a looping `maybeProcess`, `finish()` only calls it once from
  outside — the continuation itself must keep forcing once `finished`, or a
  `bestCutPoint()` remainder from the very first forced chunk never gets a
  second forced attempt). ParakeetLiveTranscriber.swift `drain` (already a
  `while let` loop, but same premature-stop bug — a single `.droppedSilence`
  mid-loop used to end it since it doesn't `continue` on the old nil) and
  `ParakeetFileTranscriber.transcribe`'s local `transcribeReady` (same
  fix; this one didn't need a "finished" propagation fix since it's a
  synchronous per-call loop, not a recursive async continuation).
- tester: extended AudioChunkerTests — updated the shared `drain` test
  helper to a `.droppedSilence`-continuing loop (`drainReady`), confirmed
  the 3 pre-existing tests still pass unchanged. Added
  testForcedDrainFindsTailSpeechBehindADroppedSilentChunk (25s silence + 1.5s
  tail speech, single forced drain — this exact shape would have returned
  zero speech chunks pre-fix) and testSinglePopCallDistinguishesDroppedSilenceFromEmpty
  (asserts the literal 3-call sequence: droppedSilence → ready → empty).
  Narrow filter: 5/5 pass. Full suite: 102 tests (was 100, +2), 99 passed /
  1 skipped / 2 failures — same 2 as before (span B, span C; both mid-file,
  not tail-of-stream, so unaffected by this task as expected), no
  regression.
- auditor: CLEAR. RMS/speech-detection logic byte-for-byte untouched;
  termination proven (every .droppedSilence branch strictly shrinks
  pending); isProcessing re-entrancy unchanged; force:finished ≡ old
  force:false for the non-finished path (verified finished only flips in
  finish()); Parakeet's while-let loops confirmed to have had the identical
  premature-stop bug (nil was ambiguous there too), not just a compile-
  driven mechanical edit; both new tests hand-traced to genuinely exercise
  the bug shape. One non-blocking observation: processChunk's continuation
  recurses through the call stack once per drained chunk, now also under
  force — bounded by realistic backlog size (tens of chunks), not flagged as
  a finding. Build clean, 5/5 narrow tests pass against the real diff.
- status: DONE

## T-06 — Corrector shrink floor
- rev: uncommitted
- builder: deviated from the plan's literal "~0.6x ratio" mechanism —
  verified by hand against the real ledger evidence before implementing,
  documented here rather than asked about (no explicit checkpoint requested
  for T-06). Queried the app's actual wffl.sqlite transcript_edits table for
  the real "Appreciating that." row (meeting D82C86DC) — measurements.md §8
  summarizes it, the DB has the literal old/new text. Computed content-word
  counts by hand: the real deletion drops 1 of 31 content words in its
  segment (ratio ~0.97); the legitimate Gunkirtan collapse (existing
  testSanitizeAcceptsMinorSpellingFix) has ratio ~0.67. No single ratio
  threshold can accept 0.67 and reject 0.97 — a whole-segment ratio floor is
  mathematically incapable of distinguishing the plan's own two named
  calibration cases. Implemented instead: walk original's content words in
  order (TextFidelity.contentWords, already function-word-filtered); every
  maximal contiguous run absent from the reply must be either (a) entirely
  CleanupEditGuard.fillerSpans words (exposed non-private for this reuse,
  per the plan's explicit instruction) or (b) phonetically explained by one
  of the same-call's validated glossary additions (reusing
  TextFidelity.isPhoneticallySupported in reverse: checking the dropped
  run's joined text against the added word(s)) — else reject. Hand-verified
  against phoneticKey: "gun curtain" and "gunkirtan" both reduce to
  "gnkrtn" (exact match), so the Gunkirtan collapse is explained;
  "appreciating" vs "vachanamrut" (the only real addition in that row)
  reduce to unrelated keys ("aprktng" vs "vknmrt"), so it is not — matches
  the required outcome for both. No new magic thresholds; reuses only
  already-calibrated primitives. TranscriptCorrector.swift's sanitize doc
  comment updated to describe the actual 4 rules (was: growth-only +
  invention + context-echo).
- tester: extended TranscriptCorrectorTests — the real ledger row (rejects),
  the same Vachnamurats->Vachanamrut fix in isolation (accepts), a dropped
  filler word alone (accepts), a dropped real clause with no bundled
  glossary fix (rejects, the general case). Existing
  testSanitizeAcceptsMinorSpellingFix (Gunkirtan) reconfirmed passing,
  unchanged. 9/9 narrow. Full suite: 106 tests (was 102, +4), 103 passed /
  1 skipped / 2 failures — same 2 as before, no regression.
- auditor: FINDING — the shrink floor checked content words individually, so it
  did not fully reuse CleanupEditGuard's multi-word filler and stutter grammar.
- builder: fixed — exposed `CleanupEditGuard.isFillerDeletion` and derive
  permitted removals from raw-token filler spans before content-word filtering;
  immediate repeated-token stutters are also accounted for by token counts.
- tester: TranscriptCorrectorTests 11/11 green after the fix, including new
  multi-word filler and immediate-stutter cases.
- auditor: FINDING — set-based content matching still permits deletion of a
  repeated real phrase when an earlier occurrence survives.
- builder: fixed — content-word retention now uses occurrence-aware LCS
  matching; added the repeated-phrase regression case.
- tester: TranscriptCorrectorTests 12/12 green after the second fix, including
  the repeated real-phrase rejection case.
- auditor: FINDING — raw multi-word filler deletion still uses set membership,
  so a repeated phrase (for example, a second `you know`) is rejected when its
  earlier occurrence survives. It must use occurrence-aware raw-token
  alignment, matching the content-word LCS.
- status: SUPERSEDED (2026-07-27) — `PLAN-engine-and-pack-v1.md` T-05 deleted
  `TranscriptCorrector.swift` (and this shrink-floor logic with it) entirely.
  The finding above was never wrong, just overtaken: there's no more corrector
  to fix it in. See `docs/engine-pack-ledger.md` T-05.
