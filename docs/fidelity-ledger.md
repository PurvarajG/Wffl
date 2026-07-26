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
| T-02 | Transactional segment replacement | W0 | DONE |
| T-03 | Typed write failures | W0 | DONE |
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

## T-02 — Transactional segment replacement
- rev: uncommitted
- builder: Database.swift — added top-level `DatabaseError` enum (`.sqlite(String)`, `.emptyReplacement`) and `Database.replaceSegments(meetingId:with:)` (added after `deleteSegments`, ~line 300): refuses an empty array by throwing `.emptyReplacement`; otherwise runs `BEGIN IMMEDIATE`, a `DELETE FROM transcript_segments WHERE meeting_id = ?`, an `INSERT OR REPLACE` per segment, then `COMMIT`, all inside one `queue.sync`; any prepare/step/exec failure throws `.sqlite(errmsg)` and the catch issues `ROLLBACK` before rethrowing. The delete is inlined as raw SQL rather than calling the existing `deleteSegments(meetingId:)` function deliberately — `deleteSegments` itself calls `run(...)`, which does its own `queue.sync`, and nesting a `sync` call on the same serial `DispatchQueue` from inside another `sync` block on that same queue deadlocks. AppState.swift:592-598 — replaced the `if replaceExisting, !out.isEmpty { deleteSegments }` + `for s in out { insert(s) }` pair with `if !out.isEmpty { try Database.shared.replaceSegments(meetingId: meetingId, with: out) }`; the throw propagates to the existing outer `catch` (AppState.swift:644-649), which already shows a toast and touches no segment state, so a failed replace now leaves prior segments untouched with no new error handling needed. `replaceExisting` param is unchanged elsewhere (still gates the post-save toast wording at :632).
- builder note: `grep -rn "deleteSegments" Sources/Wffl/` now returns only the `Database.swift:310` definition — zero callers anywhere. T-01's own Auditor check assumed T-02 would still call this function ("the T-02 transactional call site"); instead `replaceSegments` reimplements the delete inline for the deadlock reason above, so `deleteSegments(meetingId:)` is genuinely dead code as of this revision. Left it in place rather than deleting it — removal isn't named by T-02's "Change" section and this is a judgment call, flagged here for the Auditor rather than made unilaterally.
- tester: updated `Tests/WfflTests/AppStateTranscriptSafetyTests.swift`'s `testDeleteSegmentsHasOnlyTheExpectedCallSites` (my own T-01 test) — its "exactly one call site in AppState.swift" assumption went stale the moment T-02 moved that call site into `Database.replaceSegments`; it now asserts zero `deleteSegments` references in AppState.swift and exactly one guarded `replaceSegments(meetingId:` call instead. This is a test-only fix to my own prior assertion, not a production change. Added `Tests/WfflTests/DatabaseTransactionTests.swift` with the plan's three named cases, all against real `Database.shared` scoped to throwaway meeting ids (cascade-deleted in each test's `defer`): (a) `testSuccessfulReplaceSwapsTheWholeSet` — two sequential replaces, asserts the second fully supersedes the first; (b) `testFailedInsertMidBatchLeavesOriginalSetIntact` — forces a real mid-batch failure via an actual FK violation (`transcript_segments.meeting_id REFERENCES meetings(id)` with `PRAGMA foreign_keys=ON`, confirmed at Database.swift:95-120) by pointing the second segment in the batch at a meeting id that was never inserted, then asserts `DatabaseError.sqlite` is thrown and the original two segments are untouched; (c) `testEmptyReplacementThrowsAndChangesNothing` — asserts `DatabaseError.emptyReplacement` and no change. All 3 new tests passed on first run. Full suite: `swift test --filter WfflTests` → 72 executed, 1 skipped, 0 failed (71 passed = 68 after T-01 + 3 new). No regression. Also reran the plan's grep check: `grep -rn "deleteSegments" Sources/Wffl/` → exactly one hit, the definition (see builder note above on why this differs from the plan's literal expectation).
- auditor: FINDING — `DatabaseError` (Database.swift:4-14) conformed to `CustomStringConvertible`, not `LocalizedError`. `error.localizedDescription`, which is what the toast at AppState.swift:649 actually reads, bridges a plain `CustomStringConvertible` `Error` to a generic NSError string ("The operation couldn't be completed...") instead of the real message — the toast would show up but carry no diagnostic value. Codebase convention is `LLMError: LocalizedError` (LLMProvider.swift:54). Everything else (transaction correctness, AppState call site, dead-code judgment call on `deleteSegments`, test legitimacy) verified CLEAR; independently reran `swift build` (clean) and `swift test --filter WfflTests` (72/1 skipped/0 failed) before finding this.
- builder: fixed — changed `enum DatabaseError: Error, CustomStringConvertible` to `enum DatabaseError: LocalizedError`, renamed `description` to `errorDescription: String?`, matching the `LLMError` convention.
- tester: re-ran `swift build` (clean) and `swift test --filter WfflTests` → 72 executed, 1 skipped, 0 failed. No regression from the fix.
- auditor: CLEAR — confirmed `DatabaseError: LocalizedError` with `errorDescription` returns the right string for both cases, confirmed via `LocalizedError` bridging rules that `localizedDescription` now surfaces the real message, grepped for any other `CustomStringConvertible`/`.description` reliance (none), independently reran `swift build` (clean) and `swift test --filter WfflTests` (72/1 skipped/0 failed), and confirmed the only diff since the prior finding was the `DatabaseError` protocol/property rename. No further findings.
- status: DONE

## T-03 — Typed write failures
- rev: uncommitted
- builder: Database.swift — split the old `run(_:_:)` into a thin locking wrapper and a new `private func runThrowing(_ sql: String, _ params: [SQLValue]) throws`. `runThrowing` does the prepare/bind/step itself, does NOT call `queue.sync` (callers must already be on `queue`), and on failure both `NSLog`s the same "Wffl prepare failed:"/"Wffl step failed:" messages `run` always emitted AND throws `DatabaseError.sqlite(message)` — so the ~30 existing `run`-based call sites see identical behavior (same Void return, same NSLog side effect), while new throwing callers get the typed error too. `run` is now `queue.sync { try? runThrowing(sql, params) }`. Migrated only `replaceSegments`'s internal `step` closure to call the shared `runThrowing` directly (removed the duplicated local `step` function; it's already inside `replaceSegments`'s own `queue.sync`, so calling the unlocked `runThrowing` from there doesn't nest a lock). Left the local `exec(_:)` closure (BEGIN/COMMIT/ROLLBACK, no bind params, uses `sqlite3_exec` directly) untouched — not part of "the segment-write path" the task names, and unifying it isn't required. No other call site touched.
- tester: per the plan, T-03 is covered by T-02's case (b) (`testFailedInsertMidBatchLeavesOriginalSetIntact`, the real FK-violation mid-batch rollback test) — re-ran it plus the full suite to confirm the refactor didn't change behavior. `swift test --filter DatabaseTransactionTests` → 3/3 passed (test output now shows "Wffl step failed: FOREIGN KEY constraint failed" via NSLog, confirming the path flows through `runThrowing`). `swift test --filter WfflTests` → 72 executed, 1 skipped, 0 failed. No regression, no new tests needed (task names none).
- auditor: CLEAR — confirmed `runThrowing` doesn't self-lock (no nested queue.sync/deadlock), confirmed `run`'s NSLog messages are byte-identical to the pre-T-03 version on both failure paths (no behavioural change for existing callers), confirmed `replaceSegments` now calls `runThrowing` for its DELETE/INSERT while `exec` stays local for BEGIN/COMMIT/ROLLBACK, grepped all `run(`/`runThrowing(` call sites and confirmed no opportunistic migration (only `replaceSegments`'s two statements changed), and independently reran `swift build` (clean), `swift test --filter WfflTests` (72/1 skipped/0 failed), and `swift test --filter DatabaseTransactionTests` (3/3, saw the NSLog line). No findings.
- status: DONE
