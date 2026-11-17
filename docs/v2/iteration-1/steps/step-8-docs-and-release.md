# Step 8: one architecture document, remove old plans, release

**Rules served:** all five, by making them the documented design.
**Checked in advance:** no.
**Owner approval needed:** **yes**, for part 2 (it deletes files that are not in git, so they
cannot be recovered) and for part 4 (a public release).

## Before you start

- [ ] Steps 1 to 5 are done. Steps 6 and 7 are done, or the owner has decided to skip them.
- [ ] `swift test` passes.

## Part 1: put the rules where the next person will find them

In `docs/architecture.md`, add a section near the top titled "Audio to transcript: the rules".
Copy into it, from this folder:

- the five rules from [../README.md](../README.md), word for word;
- the "pipeline after this iteration" diagram from [../CONTEXT.md](../CONTEXT.md);
- the table "What carries the product, and must not be removed" from the README.

Then correct anything in `docs/architecture.md` that the steps made false. Known cases: it
describes the file decoder's channel averaging as a protection, it describes three engines, and
it says the microphone is always one speaker.

In `CURRENT.md`, add one line under the first heading:
`Pipeline rules and status: docs/architecture.md and docs/v2/iteration-1/STATUS.md`.

If steps 6 and 7 were skipped, describe the pipeline as it is, with whisper.cpp still present.

## Part 2: remove the old plans (**needs the owner's yes**)

These files describe rounds of fixes that this iteration replaces. Two of them told later
readers not to touch the loudness threshold. Leaving them in the repository invites the same
mistake.

Tracked in git (recoverable from history):

```bash
git rm -q PLAN-speed-and-progress.md docs/engine-pack-ledger.md docs/fidelity-ledger.md docs/fidelity-v3-ledger.md
```

```bash
git rm -r -q docs/fidelity-v3
```

Not tracked (deleted for good; confirm the owner's yes in STATUS.md first):

```bash
rm PLAN-engine-and-pack-v1.md PLAN-fidelity-v2.md PLAN-fidelity-v3.md PLAN-real-meeting-hardening.md PLAN-speakers-and-autostart.md PLAN-transcript-fidelity.md FIX-HANDOFF.md
```

If the owner would rather keep them, move them out of the repository instead:

```bash
mkdir -p ~/Documents/wffl-old-plans && mv PLAN-*.md FIX-HANDOFF.md ~/Documents/wffl-old-plans/
```

In `.gitignore`, remove the lines `PLAN*.md` and `FIX-HANDOFF.md`.

**Do not touch** the four `re-fresh-*.md` files at the repository root. They belong to other
work (notes, the opening reveal, the scoreboard).

`scripts/export-corpus.sh` reads cleanup internals. If step 7 was done and the script no
longer runs, delete it and remove the `docs/corpus/` lines from `.gitignore`.

## Part 3: remove stale worktrees

Two agent worktrees sit under `.claude/worktrees/`, each with its own build folder. Their
branches are already merged into the current branch. Check, then remove:

```bash
git worktree list
```

```bash
git -C .claude/worktrees/agent-a8086f6983fadf65f status --short
```

```bash
git -C .claude/worktrees/agent-a840e3ef0aff9e8ff status --short
```

If either shows uncommitted changes, stop and ask the owner. On 2026-11-16 the first showed
two changed files. Otherwise:

```bash
git worktree remove .claude/worktrees/agent-a8086f6983fadf65f
```

```bash
git worktree remove .claude/worktrees/agent-a840e3ef0aff9e8ff
```

## Part 4: release (**Owner**)

A release is public and cannot be withdrawn from people who install it. The owner does this,
following `docs/RELEASING.md`.

Before tagging, one last check that no test can replace:

1. Build and sign the app ("Building the app" in [step-5-measure.md](step-5-measure.md)).
2. Record five minutes of ordinary conversation across a room, with at least two people and
   some Gujarati terms.
3. Open the meeting. Read the transcript against memory.
4. Expand "How it was transcribed" and copy the accounting line.

**Release only when** the line does not begin with "Incomplete", `transcribed` is at least 95%
of `audio`, and the owner is satisfied with what they read. Paste the accounting line into the
release notes and into STATUS.md.

Then bump `CFBundleShortVersionString` in `Support/Info.plist`, merge, and tag as
`docs/RELEASING.md` describes.

## Verify

```bash
swift build 2>&1 | grep -E " error|Build complete"
```

```bash
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3
```

```bash
grep -c "never waits for" docs/architecture.md
```

Expect: `1` or more.

```bash
ls PLAN-*.md FIX-HANDOFF.md 2>/dev/null | wc -l
```

Expect: `0`, if part 2 was approved.

## Done when

- [ ] `docs/architecture.md` holds the five rules and matches the code.
- [ ] Old plans are removed or moved, as the owner chose.
- [ ] STATUS.md records the final accounting line and the released version.

## Commit

For parts 1 to 3:

```
docs(pipeline): the five rules are the architecture; remove superseded plans

docs/architecture.md now states the rules the audio pipeline must keep and
describes the pipeline as built. Removes the plans and ledgers from earlier
fix rounds, two of which instructed readers not to revisit the loudness
threshold that caused the 2026-11-15 failure.
```
