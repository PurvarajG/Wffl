# Rubric eval: scoring notes against answer keys

Status: **design approved 2026-11-01, not built yet.** It replaces step 2's
word-overlap agreement and becomes the scoreboard for every model from here
on: the base-model shortlist now, the fine-tuned student at step 5.
Companions: [notes-spec.md](notes-spec.md) (the rules),
[step2-results.md](step2-results.md) (what this fixes), and, in a local
checkout, `docs/superpowers/specs/2026-10-28-small-model.md` (methodology)
and `2026-10-31-model-candidates.md` (the models).

The gate rule in §8 is set here, before any candidate is scored, and isn't
changed after scores are seen.

## Why step 2's scoreboard isn't enough

- **Grounding only looks for invented names, numbers and dates.** A note
  that says almost nothing passes. Under reinforcement learning, that would
  be the winning strategy.
- **Nothing scores meaning.** An invented decision, a wrong owner or a
  decision filed under Key Points is only read by eye (G4, M3, A1).
- **Agreement with AMI is word overlap with AMI's wording** (Dice ≥ 0.4).
  It ranks models; it doesn't measure accuracy. The best score was 0.27.
- **No error margin.** One sample on 20 meetings, no intervals, so 0.17
  against 0.15 is noise.
- **The checks are untested.** Nothing shows each check catches what it
  claims, and G1 and M5 have known gaps.

## Decisions

| Question | Decision |
|---|---|
| Who scores meaning? | **Code, against answer keys.** Rule 4 holds: no model grades another. Keys come from AMI's human annotations; the matcher's accuracy is measured against your labels |
| Satsang? | **Meetings now, satsang in phase 2** (§13) with the same machinery |
| Decoding | **Temperature 0.** The app is pinned to 0 for summaries (§10), so the eval scores what ships |
| Matching | **Through the transcript.** A bullet and a key item match when they point at the same transcript turns |
| Test size | **40 meetings.** AMI's 20 test meetings plus 20 reserved from training now, before step 3 |

## 1. Splits

| Split | Meetings | Use |
|---|---|---|
| Training | AMI's training split minus the reserve: 78 meetings, including the six sample meetings | Step 3 training data, the samples |
| Dev | ES2003, ES2011, IS1008, TS3004, TS3006, phases a to d | Calibration only: your labels, the thresholds |
| Test | ES2004, ES2014, IS1009, TS3003, TS3007, phases a to d | Reported scores |
| Reserve | ES2002, ES2005, IS1000, TS3009, TS3010, phases a to d | Reported scores, with Test |

- **How the reserve was picked.** Per scenario, the lowest-numbered training
  series that has abstractive summaries, summlinks and topics for all four
  phases and isn't a sample series. Two ES, one IS and two TS, the same mix
  as Test.
- **The reserve is never trained on.** `ami_samples.training_meetings()`
  leaves it out, and step 3 builds data from that function only.
- **Test and Reserve are never used to tune anything.** Every threshold comes
  from Dev.

## 2. The rubric

Meeting shape. **Check** means plain string code, as in `checks.py`.
**Anchored** means code that uses transcript turns and the thresholds from §5.

| ID | Group | Criterion | What it measures | Kind |
|---|---|---|---|---|
| R1 | Gate | Format | F1–F6 and A2 pass | check |
| R2 | Gate | Safety | T3, N1, N2 and N4 pass | check |
| R3 | Gate | No loops | No bullet or sentence appears twice after normalising, and no 6-word run appears three or more times | check, **new** |
| R4 | Precision | Surface grounding | G1–G3, T1, A4 and A5 pass | check |
| R5 | Precision | Support | Share of bullets (Key Points, Decisions, Action Items, Open Questions) that anchor to a supporting turn. An unanchored bullet is an invention candidate (G4) | anchored, **new** |
| R6 | Recall | Decisions | Precision, recall and F1 of Decisions bullets against the key's decision items | anchored |
| R7 | Recall | Actions | The same for Action Items against action items | anchored |
| R8 | Recall | Owners | Of matched action items whose key item names a role, the share whose owner names that role | anchored |
| R9 | Recall | Open questions | The same as R6 for Open Questions against problem items | anchored |
| R10 | Recall | Topic coverage | Share of the key's topics touched by a Key Point or Summary sentence | anchored, **new** |
| R11 | Placement | Misplacement | Of decision and action items matched by any bullet, the share matched only outside their own section | anchored, **new** |
| R12 | Reported | Length | L1–L3, Summary ÷ AMI abstract, notes ÷ AMI summary | check |
| R13 | Reported | Cost | Wall time, prompt and generation tokens per second, first-call and peak memory, download | measured |

- **Item F1** is the mean of the R6, R7 and R9 F1s. It's the headline recall
  number, and it's always shown next to R5, so an empty note can't look good.
- **No blended score.** The gate in §8 reads each criterion on its own.
- **Thinking leak.** A reply that starts with `<think>` fails R1 and is also
  counted in its own column, so it isn't read as model quality: training
  removes it.
- **Still by eye:** A3 (task starts with a verb), T2 rewording without
  brackets, T4, judgements beyond N3's list, and whether the user's extra
  instruction was followed.
- **Known gaps:** R11 catches M5's reworded decisions. G1's sentence-initial
  name that's also an English word ("Raj") stays a gap.

## 3. Answer keys

One per meeting, built by `answer_keys.py` from AMI, never written or edited
by a person or a model. Rebuilt into the gitignored `out/keys/`, like the
transcripts.

- **Items.** Every AMI sentence under DECISIONS, ACTIONS and PROBLEMS:
  - type (decision, action, problem) and text
  - owner roles, for actions, parsed as `convert()` already does
  - its supporting dialogue acts from `extractive/<id>.summlink.xml`, each
    with speaker, start and end time
- **Topics.** The segments in `topics/<id>.topic.xml` with their time spans.
  The four topics AMI files under "Functional" in `default-topics.xml`
  (opening, closing, agenda/equipment issues, chitchat) are dropped, and so
  is any segment under 60 seconds.
- **Items with no summlink** are matched on their own words only (§4, word
  score). The report counts them.

## 4. Anchoring

`anchor.py`, standard library only.

1. **Index.** The meeting's dialogue acts, with text from AMI's words files,
   indexed with BM25 (k1 1.2, b 0.75). Words are normalised with
   `checks.norm_words`, and `checks.STOP` and the scoreboard's `BOILERPLATE`
   are removed.
2. **Query.** A bullet's content words. An action item queries its task
   only, not the owner or due date.
3. **Score.** A dialogue act's BM25 score is divided by the summed IDF of the
   query's words. That puts short and long bullets on one scale, roughly 0
   to 1.
4. **Support (R5).** A bullet is supported when its best dialogue act scores
   at least **τ_support**.
5. **Match (R6–R9, R11).** For bullet *b* and key item *k*:
   - *turn score*: the best score among *b*'s top 5 dialogue acts that clear
     τ_support and start within **w** seconds of a dialogue act linked to *k*
   - *word score*: Dice overlap of content words between *b* and *k*'s text
   - *match score*: the larger of the two. They match at or above **τ_match**
6. **Assignment.** One to one, best match score first:
   - Decisions bullets with decision items, Action Items with action items,
     Open Questions with problem items.
   - Then unmatched decision and action items are tried against every other
     section's bullets. A match there counts as misplaced (R11), not as a hit
     for R6 or R7.
7. **Topic coverage (R10).** A topic is covered when a Key Point or Summary
   sentence has a dialogue act above τ_support inside the topic's span.

The model's input transcript doesn't change. Anchoring uses its own index,
built from the same AMI words.

## 5. Calibration: your labels

About an hour, once.

- **Notes to label.** `scoreboard.py run` on Dev for `gemma4:12b-mlx` and
  `qwen3.5:4b` (teacher prompt, §9 settings).
- **`rubric.py label`** runs in the terminal. You answer `y`, `n` or `s`
  (skip) to two kinds of question:
  - **Same item?** A bullet and a key item, each shown with its top turns.
    60 of these.
  - **Supported?** A bullet and its top three turns. "Do these turns say
    what the bullet says?" 60 of these.
- **Sampling.** Half random, for an honest accuracy figure. Half near the
  threshold, by an untuned starting guess (τ 0.3, w 20 s), where labels teach
  the most. Seed 0.
- **Labels** go to `labels/dev.jsonl`, committed: your judgements on CC BY
  data, so the calibration can be rerun.
- **`rubric.py calibrate`:**
  - Searches τ_support from 0.10 to 0.60, τ_match from 0.10 to 0.70 (steps of
    0.05), and w in {0, 5, 10, 20, 30, 60} seconds.
  - τ_support is chosen on the support labels. τ_match and w are chosen on
    the match labels. Each maximises F1 against your answers.
  - **Accuracy is measured by 5-fold cross-validation:** tune on four
    folds, score the fifth, pool the five. Precision and recall are reported
    with bootstrap intervals.
  - The final thresholds are tuned on all labels and frozen in the committed
    `rubric-thresholds.json`.

## 6. Proving the eval

Three layers. All of them must pass before any score is read (§11, eval
health).

### 6.1 Matcher accuracy

From §5's cross-validation, for both questions: **precision ≥ 0.85 and
recall ≥ 0.85.** If either misses, the anchored criteria (R5–R11) are
reported but don't gate until the matcher is fixed and recalibrated.

### 6.2 Mutation tests

`rubric.py mutate` and `test_rubric.py` (standard library `unittest`).
Code plants one known fault in a good note and checks that the target
criterion gets strictly worse. Good notes: the six samples and the 12B's Dev
notes. Seed 0.

| Fault | Target |
|---|---|
| Swap an action's owner to another role in the transcript | R8 |
| Insert a decision bullet taken from the key of a meeting in another scenario and phase | R6 precision |
| Move a decision bullet into Key Points | R11 |
| Delete a decision, action or open question bullet | R6, R7 or R9 recall |
| Change a number; add a name not in the transcript | R4 |
| Add bold, parentheses, a preamble line, or a gloss ("seva (service)") | R1 |
| Repeat a bullet three times | R3 |
| Replace every optional section with "None recorded." | R6, R7, R9 recall → 0 |

**Catch rate:** check criteria (R1–R4) catch **100%** of their mutations,
anchored criteria **≥ 95%**. These tests also cover step 1's checks, which
have none today.

### 6.3 Baselines

Scored as rows in every table.

| Row | What it is | Must show |
|---|---|---|
| Empty | "None recorded." in every optional section, plus three generic Key Points | Item F1 ≤ 0.05 |
| Wrong meeting | The 12B's notes for a meeting in another scenario and phase, scored against this meeting | R5 at least 0.3 lower, and Item F1 at most a third, of what the same notes score on their own meeting |
| AMI itself | AMI's converted sections scored against their own key **with the word score off**, so only anchoring can match them | R6, R7 and R9 recall ≥ 0.95 |

- **Why the wrong-meeting bar is relative.** Every AMI meeting is the same
  remote-control design task, so another meeting's notes can find real word
  support ("an LCD screen"). The test is that they score far worse than on
  their own meeting, not that they score zero.
- **Why the word score is off for AMI itself.** AMI's items are the key's
  own text, so the word score would match them trivially. With it off, the
  row tests that anchoring lands each item on its own linked turns.
- Every real model must beat Empty and Wrong meeting on Item F1. If AMI
  itself doesn't reach 0.95, the anchoring is broken.

## 7. Statistics

- **Unit:** the meeting. Test plus Reserve, 40 meetings.
- **Bootstrap:** 10,000 resamples of meetings, seed 0. Item counts are pooled
  within each resample before F1 is computed. Percentile 95% intervals.
- **Paired:** the vs-12B comparison resamples the same meetings for both
  models.
- **Every score carries an interval.** When an interval on a difference
  crosses zero, the table says "no difference".

## 8. Gate rule

Set 2026-11-01, before any candidate is scored.

On Test plus Reserve, at temperature 0, a candidate **matches the 12B**
(`gemma4:12b-mlx`, teacher prompt) when every line clears its margin on the
95% interval of (candidate − 12B):

| Criterion | Rule |
|---|---|
| R1 Format, R2 Safety, R3 No loops (meeting pass rates) | lower end ≥ −0.10 (four meetings in 40) |
| R4 Surface grounding, R5 Support | lower end ≥ −0.05 |
| Item F1, R10 Topic coverage | lower end ≥ −0.05 |
| R11 Misplacement | upper end ≤ +0.05 |

- Each line's verdict is **match**, **worse** (the whole interval is past the
  margin) or **undecided** (the interval straddles it).
- **Undecided never counts as a pass.**
- Download ≤ 3 GB and first-call memory ≤ 5 GB stay the step 6 ship gate,
  not part of "matches".
- This rule is used both for the off-the-shelf shortlist now and for the
  fine-tuned student at step 5 (the methodology's "matches or beats the 12B
  on format and grounding, close on action items").

## 9. The run

- **Models:** the 11 in the candidates doc's `MODELS` list (the 12B, Gemma 4
  E2B and E4B as reference rows, `qwen3.5:4b` as control, and the seven new
  candidates), plus the 12B on today's prompt and the three baselines.
- **Prep (candidates doc §6):**
  - `ollama cp` each `hf.co/…` tag to a name without slashes (for example
    `minicpm5-2b:q4_K_M`), and list that name in `MODELS`.
  - Read `ollama show <tag>` for "thinking" in Capabilities. Log each.
- **Settings, as step 2:** the teacher prompt (spec plus six samples),
  `num_ctx` 32,768, temperature 0, seed 0, `think: false`, first reply only.
- **Reuse:** step 2's cached Test notes for its four models were made with
  these settings and are rescored, not rerun. Reserve and Dev are new runs.

## 10. App change

`SummaryService` passes `temperature: 0` on every summary call, as clean-up
already does (`CleanupPipeline.swift:859`). It's a separate small commit.
Today it sends no temperature, so each model uses its own default.

## 11. Report

`rubric-results.md`, committed, in the style of `step2-results.md`. Scores
and per-meeting results go to the gitignored `out/rubric/`.

1. **Eval health, first.** Matcher accuracy with intervals, mutation catch
   rates by fault, baseline rows, count of keyless items. If health fails,
   the rest isn't read.
2. **Scores:** every criterion per model, with intervals.
3. **Against the 12B:** the §8 table, one verdict per line per model.
4. **Failing rules per model,** as in step 2.

## 12. Files

| File | Job | Depends on |
|---|---|---|
| `answer_keys.py` | AMI → key JSON (§3) | `ami_samples.py` |
| `anchor.py` | Dialogue-act index, BM25, `anchor(bullet)` (§4) | nothing |
| `rubric.py` | `score(notes, transcript, key, index, thresholds)` → per-criterion results; `label`, `calibrate`, `mutate` commands | `checks.py`, `anchor.py` |
| `test_rubric.py` | Mutation tests (§6.2) | `rubric.py` |
| `scoreboard.py` | Keeps run and caching; scores with `rubric.score`; Dev, Test and Reserve splits; bootstrap; report | all of the above |
| `ami_samples.py` | Adds `dev_meetings()` and `reserve_meetings()`; `training_meetings()` drops the reserve | — |
| `labels/dev.jsonl` | Your labels (§5) | — |
| `rubric-thresholds.json` | Frozen τ_support, τ_match, w | — |

## 13. Build order

Each step ends at a gate.

| Step | What | Gate |
|---|---|---|
| 1 | Splits in `ami_samples.py`; `answer_keys.py`; `anchor.py`; `rubric.score`; check mutations in `test_rubric.py` | Check mutations 100%; AMI itself (word score off) scores R6/R7/R9 recall ≥ 0.95 at the starting guess |
| 2 | Dev runs for the 12B and `qwen3.5:4b`; you label; `calibrate`; freeze thresholds | Matcher precision and recall ≥ 0.85 (§6.1) |
| 3 | Anchored mutations; baseline rows | Eval health passes (§6) |
| 4 | Prep and run every model on Test and Reserve; `rubric-results.md` | — the report gives the §8 verdicts |
| 5 | App: summaries at temperature 0 | App builds; one meeting summarises |

## 14. Phase 2: satsang

The same anchoring and statistics, with a satsang key in place of AMI's:
teachings, stories, references and practices, each tied to transcript
times. There's no human reference in the allowed data, so phase 2 needs a
source of keys: your own written keys for a few local recordings (never
committed or trained on), or Atlas transcripts used for testing only. S4
already checks References. Designed when phase 1's report is in.

## 15. Risks

- **Generic bullets anchor weakly.** "The team discussed the budget" may
  find no strong turn and count as unsupported. The support labels measure
  this; if it's common, it shows up in 6.1.
- **One annotator per key.** Recall is against one person's view of what was
  decided. It ranks models fairly, since every model faces the same key.
- **AMI is role-play.** The eval says nothing about Gujarati terms beyond
  T1, or about real Wffl input. Your meetings stay read by eye.
- **Shared scenario wording.** The samples and the test meetings use the
  same AMI scenario phrases (step 2's N1 finding). This affects every model
  the same way.
