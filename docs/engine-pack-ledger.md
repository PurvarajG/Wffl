# Engine and pack — role-handoff ledger

Format per §0.2 of `PLAN-fidelity-v3.md` (Builder → Tester → Auditor, one task
in flight, DONE only when Tester is green and Auditor is CLEAR on the same
revision).

## Baseline

At `d4e8aed` (v1.5.0). Working tree has two pre-existing uncommitted doc-only
changes (correction banners in `docs/fidelity-v3-ledger.md` and
`docs/fidelity-v3/measurements.md` pointing at this plan) — no source files
touched, so the code baseline below is unaffected.

```
swift build 2>&1 | tail -20
```
→ clean. Two pre-existing warnings (unhandled fixture/benchmark.md resource
files), no errors. `Build complete! (1.01s)`.

```
swift test 2>&1
```
→ **123 tests executed, 1 skipped, 2 failures (0 unexpected).**

The 2 failures are both `XCTAssertTrue` in the same test case,
`AcceptanceCorpusTests.testLiveSpansSurviveProductionPath`
(`AcceptanceCorpusTests.swift:87`) — span B loses "ran away" on the live path.
This is §1.4's Whisper-deletion defect, already the subject of v3's `BLOCKED`
T-02 finding and explicitly **not fixed by this plan** (§"What this plan does
not fix"). Recorded here as the true baseline, not as a task to close.

**PLAN-fidelity-v3.md's claimed 89-passed baseline and the v3 ledger's
106-tests/2-failures entry are both stale** — the suite has grown to 123 tests
since. This 123/1-skipped/2-failures count, on `d4e8aed`, is the number every
later task in this ledger is diffed against.

---

## T-01 — Whisper becomes the default engine and model
- rev: uncommitted
- builder: `Prefs.swift:19-27` — `transcriptionEngine` default `"parakeet"` →
  `"whisper"`, comment rewritten to cite §1.2/§1.4 and note Parakeet is kept
  as a selectable adapter, not deleted. `Prefs.swift:53-60` — `whisperModel`
  default `"base.en"` → `"large-v3-turbo"`, comment rewritten (§1.2:
  multilingual `-l en` is both Latin-script and better on code-switched
  terms, so the `.en`-only rationale no longer holds). `effectiveWhisperModel`
  simplified to `{ whisperModel }` (chose "simplify" over "delete + update call
  sites" — 5 call sites across AppState/RecorderController/SettingsView, all
  already correct against a plain alias, so simplifying avoids touching files
  T-01 doesn't need to touch). `effectiveEngine`'s branching, `TranscriptionProfile`,
  `VocabularyGate`, `selectDevotionalProfileFromVocabularyGate` untouched, per
  the task's "do not touch" list.
  Verified before writing any code: `resolveEngineSource()` (AppState.swift:465)
  and the live-record guard (RecorderController.swift:204) both already return
  `nil`/`fail(...)` with a user-facing toast when `ModelManager.path(for:)`
  can't find the model — no hard failure path exists for a missing
  `large-v3-turbo`. No STOP condition triggered; not a T-01 finding.
- tester: extended `PrefsProfileTests.swift` with 5 new cases —
  `testFreshDefaultEngineIsWhisper`, `testFreshDefaultModelIsLargeV3Turbo`,
  `testExplicitParakeetChoiceIsPreserved`, `testExplicitBaseEnModelChoiceIsPreserved`,
  `testDevotionalProfileUnchangedByEngineDefaultFlip`. `swift build`: clean.
  `swift test --filter PrefsProfileTests`: 9/9 green (4 pre-existing + 5 new).
  Full suite: 128 tests, 1 skipped, 2 failures (0 unexpected) — same 2 failures
  as the baseline, both `AcceptanceCorpusTests.testLiveSpansSurviveProductionPath`
  (pre-existing, documented, not in scope for this plan). Count is baseline
  123 + 5 new = 128, exactly. No regression.
- auditor: CLEAR. `git diff` touches only `Sources/Wffl/Support/Prefs.swift`
  and `Tests/WfflTests/PrefsProfileTests.swift` — matches the task's file list
  exactly. All 3 acceptance criteria verified by the new tests. I1–I5
  (no invention/duplication/unbounded-edit/unrecoverable/silent-loss) are
  vacuously satisfied — T-01 touches no transcript content path. I6/I7 do not
  apply — no correction logic touched.
- status: DONE
