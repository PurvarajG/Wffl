# Fidelity v2 — execution ledger

Handoff channel for the Builder / Tester / Auditor loop defined in
[PLAN-fidelity-v2.md](../PLAN-fidelity-v2.md) §0.

**Rules:** append only. One task in flight. A task reaches `DONE` only when the
Tester reports green *and* the Auditor emits `CLEAR` on the same revision. Three
non-converging loops → `BLOCKED`, stop, surface to the human.

**Entry format:**

```
## T-NN — <title>
- rev: <sha or "uncommitted">
- builder: <what changed, file:line>
- tester: <cases added> ; <N passed / N failed>
- auditor: CLEAR | FINDING — <specific, actionable>
- status: OPEN | IN REVIEW | DONE | BLOCKED
```

---

## Status board

| ID | Task | Wave | Status |
|---|---|---|---|
| T-01 | Stop destructive manual re-transcribe | W0 | DONE |
| T-02 | Transactional segment replacement | W0 | OPEN |
| T-03 | Typed write failures | W0 | OPEN |
| T-04 | Bound deletions, validate headings | W0 | OPEN |
| T-05 | Immutable raw + edit ledger (I4) | W0 | OPEN |
| T-06 | Fix the phonetic threshold | W1 | OPEN |
| T-07 | Load the missing vocabulary | W1 | OPEN |
| T-08 | Validate multiword terms as one span | W1 | OPEN |
| T-09 | Fix the context-echo rule | W1 | OPEN |
| T-10 | Candidate-scoped glossary + skip gate | W1 | OPEN |
| T-11 | Entity canonicalization | W1 | OPEN |
| T-12 | Enforce I2 on the final artifact | W1 | OPEN |
| T-13 | Mono diarization | W1 | OPEN |
| T-14 | Stop discarding timestamps | W1 | OPEN |
| T-15 | Memoize phonetic keys | W2 | OPEN |
| T-16 | Precompute `isKnownSpelling` token set | W2 | OPEN |
| T-17 | Stream 16 kHz decoding | W2 | OPEN |
| T-18 | Honest correction telemetry | W3 | OPEN |
| T-19 | Devotional profile as verifiable recipe | W3 | OPEN |
| T-20 | Ollama endpoint policy | W3 | OPEN |
| T-21 | Verified model downloads | W3 | OPEN |
| T-22 | Naming and API safety | W3 | OPEN |
| T-23 | Real acceptance corpus | W3 | OPEN |

**Baseline at `7bd2c7b`:** build clean, 67 passed / 1 skipped / 0 failed.

---

## Entries

## T-01 — Stop destructive manual re-transcribe
- rev: uncommitted
- builder: AppState.swift:529-534 — removed the `if !quietly { deleteSegments(...); transcriptRefresh += 1 }` pre-delete block from `retranscribe`; `runTranscription` is now called with `replaceExisting: true` unconditionally for both manual and quiet paths, so both go through the stage-then-swap path instead of the manual path deleting first.
- tester: added `Tests/WfflTests/AppStateTranscriptSafetyTests.swift`. Blocker found: `AppState()` cannot be constructed inside the `swift test` process — `init()` → `setUpMeetingSentinel()` → `UNUserNotificationCenter.current()` throws an uncaught `NSInternalInconsistencyException` ("bundleProxyForCurrentProcess is nil") and aborts the whole test binary, because the SPM test host has no app bundle. Confirmed by first writing the plan's literal `testFailedRetranscribeKeepsPriorSegments` (real `AppState`, real `Database.shared` scoped to a throwaway meeting id, forced failure via undecodable audio) — it crashed the entire process, 0 tests able to run. This is pre-existing and unrelated to T-01; out of scope to fix here (would require touching `setUpMeetingSentinel`, not named by this task). Substituted two source-level regression tests instead: `testRetranscribeNoLongerDeletesBeforeTranscribing` (asserts `retranscribe`'s body contains no `deleteSegments` call and does call `replaceExisting: true`) and `testDeleteSegmentsHasOnlyTheExpectedCallSites` (asserts exactly one `deleteSegments` call site remains in AppState.swift, guarded by `replaceExisting` + `!out.isEmpty`). 2 new tests, both passed. Full suite: `swift test --filter WfflTests` → 69 executed, 1 skipped, 0 failed (68 passed = baseline 67 + 2 new − 1 pre-existing skip). No regression.
- note for W1+: full behavioral coverage of `retranscribe`/`runTranscription` at the `AppState` level is blocked until `setUpMeetingSentinel`'s `UNUserNotificationCenter` call is made test-safe (or injectable). T-02's `DatabaseTransactionTests` will cover the real atomic-replace behavior at the `Database` layer directly, which doesn't require `AppState` and isn't affected by this blocker.
- auditor: CLEAR — verified diff scope (AppState.swift + new test file + ledger only), traced runTranscription's success/catch paths confirming deleteSegments only fires post-success guarded by `replaceExisting && !out.isEmpty`, confirmed grep returns exactly the two expected call sites (Database.swift:298 definition, AppState.swift:596 guarded call), judged the UNUserNotificationCenter crash substitution reasonable and the two regression tests non-tautological (would fail if the fix were reverted), and independently reran `swift build` (clean) and `swift test --filter WfflTests` (69 executed / 1 skipped / 0 failed). No findings.
- status: DONE
