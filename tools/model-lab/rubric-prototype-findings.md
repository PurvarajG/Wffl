# Rubric eval: prototype findings before the build

2026-11-01, Dev split only. Nothing from Test or Reserve was read or
scored, so the gate rule in [rubric-spec.md](rubric-spec.md) §8 is untouched.

Before writing the build plan, the answer keys (§3) and anchoring (§4) were
prototyped on the 20 Dev meetings (176 key items, 171 with summlinks), and
`gemma4:12b-mlx` wrote notes for four Dev meetings (ES2003b, IS1008c,
TS3004c, ES2011d) with the teacher prompt. The prototype code is in this
session's scratchpad, `proto/`, and isn't part of the build.

## What holds

- **Keys build cleanly.** Summlinks cover 499 of 523 decision, action and
  problem items (95%) across Dev, Test and Reserve.
- **Concrete decisions anchor well.** The 12B's Decisions bullets score 0.6
  to 0.9 on support and land on the right key item: "scroll wheel for
  volume" → "scroll button for volume control", "rechargeable batteries" →
  its item.
- **Local scoring separates items.** Scoring a text against only the
  passages around an item's linked turns tells an item's own turns from
  other items' turns with AUC 0.89 (w = 0) to 0.85 (w = 20 s).

## What doesn't hold as written

| Spec part | As written | Measured |
|---|---|---|
| §4 step 5: turn score from the bullet's global top 5 passages | AMI items should land on their own turns | 44% at τ 0.3, w 20 s; 68% at best (τ 0.2, w 60 s). Words like remote, button and LCD recur all meeting |
| §6.3 and §13 step 1: AMI itself, word score off, recall ≥ 0.95 | — | 0.71 recall, 0.78 precision at best, even with local scoring and one-to-one assignment. AMI's summary wording ("the group decided to incorporate…") isn't what was said in the room |
| §4 step 4, R5 Support: BM25 ÷ the query's summed IDF | Invented bullets score low | Long bullets score low too. The 12B's Key Points score 0.1 to 0.3 though they aren't invented, so at τ 0.3 most Key Points count as unsupported |
| Alternative for R5: share of the bullet's words, weighted by IDF, said within one 30–60 s stretch | — | Fairer to long bullets (own-meeting median 0.46–0.50, wrong meeting 0.24–0.26), but still overlaps: AUC 0.79 own against wrong meeting |

## Decisions for you

These change eval health and anchoring, not the gate rule. Dev is the
calibration split, so setting them from Dev numbers is within the spec.

1. **Matching.** Replace §4 step 5's global top 5 with local scoring: the
   bullet against the passages within w of the item's linked turns.
   Recommended: it's clearly better on every measure above.
2. **Support for Key Points.** Either report R5 separately for Key Points
   and for Decisions, Actions and Open Questions, with its own threshold,
   or take Key Points out of R5 and rely on R4 and R10 for them.
3. **The AMI-itself bar.** 0.95 with the word score off can't be met.
   Either set it from Dev (about 0.70) or keep the word score on and treat
   the row as a plumbing check only.
4. **Expect the matcher's accuracy gate (§6.1, ≥ 0.85 against your labels)
   may fail.** If it does, anchored scores are reported but don't gate, and
   gating falls back to the checks (R1 to R4). Your labels are what tell us;
   these numbers only say it's at risk.

## State of the build

Another session ("Model evaluation and testing") is building the spec as
committed and running every candidate overnight, with anchored scores at
the starting guess marked uncalibrated. These findings were sent to it at
01:42 UTC. No build plan was written here, so the two sessions don't edit
the same files.
