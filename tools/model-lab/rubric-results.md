# Rubric results: the base-model shortlist

Run 2026-11-01, overnight and unattended, with `rubric.py` on 40 meetings
(AMI's 20 Test meetings plus the 20 Reserve meetings): every model on the
shortlist in `2026-10-31-model-candidates.md` against `gemma4:12b-mlx`. Design:
[rubric-spec.md](rubric-spec.md). Scores, intervals and per-meeting results
are in the gitignored `out/rubric/` (`report.md`, `scores.json`).

## Verdict

**No candidate matches the 12B under the §8 gate rule.** Every one is "worse"
or "undecided" on at least one check line, and undecided never passes. That
was expected: step 2 found the same, and closing the gap is what training is
for.

**Take two candidates into training (step 3), with one reference row:**

| Role | Model | Why |
|---|---|---|
| Lead | **Spark-X2.6-4B** (`hf.co/bartowski/Spark-X2.6-4B-GGUF:Q4_K_M`) | The best small model on content. On Item F1 it's the top model after the 12B's two rows in 156 of 162 matcher configs, and ahead of Qwen3.5-4B in both scored configs (+0.08 [+0.03, +0.13] and +0.06 [+0.01, +0.12]). Level with the 12B on support (R5), within 0.05 on surface grounding (R4). Already inside the ship gate: 2.6 GB download, 3.7 GB first call |
| Second | **Nemotron 3 Nano 4B** (`nemotron-3-nano:4b`, NVFP4) | Level with Spark on Item F1 (no difference in either config), the best owners (R8) at the starting guess, and the fastest (14 s a meeting). A different architecture (hybrid Mamba), so the two aren't the same bet. **Its route to shipping is unproven:** this build needs 6.7 GB on its first call, and the 3.6 GB GGUF build degrades badly on Ollama's llama.cpp (Findings) |
| Reference | **Qwen3.5-9B** (`qwen3.5:9b`) | The only candidate with no check line "worse" than the 12B; close to Spark on Item F1. But 7.6 GB to download and 10.5 GB on its first call, so it's outside the ship gate unless quantised to about 4 GB. Tells you what a bigger student buys |

**Qwen3.5-4B**, step 2's pick, drops to control. Spark, Nemotron and the 9B
all beat it on Item F1 in 160 to 162 of the 162 configs.

**Drop four.** Each failed on something training doesn't obviously fix:

- **Granite 4.2 3B:** format in 2 of 40 meetings, copying from the prompt in 35, surface grounding in 8.
- **MiniCPM5-2B:** the best format (0.93), but weak content (Item F1 9th to 12th of 13), the most misplaced items (R11 about half), and greedy loops in 3 meetings.
- **LFM2.5-2.6B:** it reasons even with `think: false`. Sixteen of 40 replies were empty, every token spent on hidden reasoning, and 22 were cut off at the token cap.
- **Jamba2 3B:** it ignores the spec's shape (numbered sections, bold, no `##` headings) in all 40 meetings, so its content can't even be scored.

## Read this first: what the scores can and can't say

- **Your labels (§5) haven't been made.** The anchored criteria (R5 to R11)
  are scored at two uncalibrated configs: §5's starting guess, and the config
  a label-free check on Dev picked (below). Both fail parts of eval health
  (§6). By the spec's own rule, the anchored lines are reported but don't gate.
- **So the verdicts rest on the check criteria (R1 to R4).** Their mutation
  tests catch 100% of planted faults.
- **The anchored numbers still rank.** Across a sweep of 162 configs
  (global and local matching, 1-act, 3-act and 60-second units, τ_support,
  τ_match and w), the order of models by Item F1 barely moves. That's the
  evidence behind the shortlist; the absolute values aren't.

## How it was run

- **Prompt and decoding as step 2:** the teacher prompt (spec plus six
  samples), `num_ctx` 32,768, temperature 0, seed 0, `think: false`, first
  reply scored. Step 2's cached Test notes were rescored, not rerun.
- **Models:** pulled as the candidates doc lists them. Two library tags
  aren't what the doc assumed: `nemotron-3-nano:4b` and `qwen3.5:9b` default
  to **NVFP4 on Ollama's MLX runner**, not Q4_K_M GGUF. Nemotron was also run
  from its `4b-q4_K_M` GGUF tag, after the main run; see Findings.
- **Thinking (§9 prep), from `ollama show`:** Granite, Spark, MiniCPM5,
  Nemotron, LFM2.5 and both Qwens list "thinking"; Jamba2 doesn't. No reply
  started with `<think>`. LFM2.5 reasons anyway, out of sight: its non-empty
  replies generate 2.9 tokens per visible word of notes, against 1.2 for the
  others.
- **RAM:** one model at a time. The runner waited whenever another model
  was loaded, and reset Ollama's runner whenever it passed 13 GB. It reset 34
  times: 23 on the 12B, 9 on the 9B and 2 on Nemotron's NVFP4 build, so their
  "highest" memory below is capped by the guard, not measured free.
- **Statistics (§7):** 10,000 bootstrap resamples of the 40 meetings, seed
  0, item counts pooled within each resample, paired against the 12B.

## Eval health (§6)

| Check | Bar | Starting guess | Dev proxy's config |
|---|---|---|---|
| Check-criteria mutations (R1, R3, R4) | 100% | **100%** (168 of 168) | **100%** (168 of 168) |
| Anchored mutations (R6–R9, R11, owners) | ≥ 95% | 86.7% (130 of 150) | 73.5% (119 of 162) |
| Empty: Item F1 | ≤ 0.05 | **0.00** | **0.00** |
| Wrong meeting: R5 drop from own | ≥ 0.30 | 0.26 | **0.52** |
| Wrong meeting: Item F1 | ≤ a third of own | **0.06** (bar 0.13) | 0.27 (bar 0.19) |
| AMI itself, word score off: R6 / R7 / R9 recall | ≥ 0.95 | 0.45 / 0.57 / 0.25 | 0.82 / 0.85 / 0.70 |
| Keyless items (no summlink) | counted | 19 of 347 | 19 of 347 |

What fails, and why:

- **The starting guess barely anchors.** On the Dev check it ranks 121st
  of 162 configs. A single dialogue act is too short to hold a bullet's
  words, so long bullets look unsupported: the 12B's Key Points come out 5%
  supported against 59% for its Decisions, Actions and Open Questions. The
  rubric session's prototype found the same.
- **The anchored mutations fail on matcher precision, not on the mutations.**
  When a matched bullet is deleted, another bullet often takes its item on
  shared scenario words ("remote", "feature"), so recall doesn't drop. At
  τ_match 0.3, "The team will investigate the financial…" matched "the
  remote would feature…". Your labels measure exactly this.
- **R10 (topic coverage) doesn't separate notes from generic text.** The
  Empty note's three generic Key Points and two Summary sentences cover 63%
  to 71% of topics, since "The project was discussed" anchors somewhere
  inside nearly every topic. R10 needs a redesign, not just a threshold.
- **The label-free check on Dev** (`rubric.py proxy`): matcher recall is
  AMI's own sections against their own key with the word score off.
  Precision is that against matches to another scenario's sections. Its
  best config is local matching over 60-second units, τ_match 0.2, w 60 s:
  recall 0.79, precision 0.73. Better, still short of 0.85.

## Against the 12B (§8)

Candidate − 12B, point and 95% interval of the paired difference, and the
line's verdict. Only R1 to R4 gate tonight.

### Check lines (same in every config)

| Model | R1 Format | R2 Safety | R3 No loops | R4 Surface grounding | R2 without N1 (info) |
|---|---|---|---|---|---|
| Spark-X2.6-4B | -0.10 [-0.28, 0.07] **undecided** | -0.45 [-0.62, -0.27] **worse** | -0.42 [-0.57, -0.28] **worse** | -0.05 [-0.22, 0.12] **undecided** | -0.05 [-0.12, 0.00] undecided |
| Nemotron 3 Nano 4B (NVFP4) | -0.12 [-0.27, 0.02] **undecided** | -0.42 [-0.62, -0.20] **worse** | -0.52 [-0.70, -0.35] **worse** | -0.20 [-0.38, 0.00] **undecided** | 0.00 [0.00, 0.00] match |
| Nemotron 3 Nano 4B (Q4_K_M) | -0.85 [-0.95, -0.72] **worse** | -0.62 [-0.80, -0.43] **worse** | -0.50 [-0.68, -0.32] **worse** | -0.48 [-0.65, -0.30] **worse** | 0.00 [0.00, 0.00] match |
| Qwen3.5-9B | -0.07 [-0.25, 0.10] **undecided** | -0.03 [-0.22, 0.17] **undecided** | -0.12 [-0.25, 0.00] **undecided** | -0.03 [-0.18, 0.12] **undecided** | -0.03 [-0.07, 0.00] match |
| Qwen3.5-4B (control) | -0.22 [-0.40, -0.03] **undecided** | -0.30 [-0.47, -0.12] **worse** | -0.15 [-0.28, -0.05] **undecided** | -0.12 [-0.30, 0.05] **undecided** | -0.03 [-0.07, 0.00] match |
| MiniCPM5-2B | 0.08 [0.00, 0.17] **match** | -0.72 [-0.85, -0.57] **worse** | -0.28 [-0.43, -0.12] **worse** | -0.15 [-0.35, 0.05] **undecided** | -0.03 [-0.07, 0.00] match |
| Granite 4.2 3B | -0.80 [-0.93, -0.65] **worse** | -0.62 [-0.78, -0.47] **worse** | -0.25 [-0.40, -0.10] **undecided** | -0.57 [-0.75, -0.40] **worse** | 0.00 [0.00, 0.00] match |
| LFM2.5-2.6B | -0.80 [-0.92, -0.67] **worse** | -0.30 [-0.53, -0.05] **undecided** | -0.20 [-0.35, -0.05] **undecided** | -0.33 [-0.52, -0.12] **worse** | 0.00 [0.00, 0.00] match |
| Jamba2 3B | -0.85 [-0.95, -0.72] **worse** | -0.10 [-0.30, 0.10] **undecided** | -0.05 [-0.12, 0.00] **undecided** | -0.78 [-0.90, -0.65] **worse** | 0.00 [0.00, 0.00] match |
| Gemma 4 E2B | -0.85 [-0.95, -0.72] **worse** | -0.05 [-0.22, 0.12] **undecided** | -0.28 [-0.42, -0.15] **worse** | -0.55 [-0.70, -0.40] **worse** | 0.00 [0.00, 0.00] match |
| Gemma 4 E4B | -0.82 [-0.93, -0.70] **worse** | 0.07 [-0.10, 0.25] **match** | -0.07 [-0.18, 0.03] **undecided** | -0.10 [-0.28, 0.08] **undecided** | 0.00 [0.00, 0.00] match |
| 12B, today's prompt | -0.85 [-0.95, -0.72] **worse** | 0.18 [0.03, 0.33] **match** | -0.03 [-0.12, 0.05] **undecided** | -0.78 [-0.90, -0.65] **worse** | -0.03 [-0.07, 0.00] match |

### Anchored lines, at both configs (don't gate)

At the starting guess (`global/win1/τs0.3/τm0.3/w20`):

| Model | R5 Support | Item F1 | R10 Topics | R11 Misplaced |
|---|---|---|---|---|
| Spark-X2.6-4B | 0.00 [-0.05, 0.05] **undecided** | -0.07 [-0.12, -0.01] **undecided** | 0.01 [-0.02, 0.05] **match** | 0.09 [-0.01, 0.19] **undecided** |
| Nemotron 3 Nano 4B (NVFP4) | 0.04 [-0.02, 0.09] **match** | -0.10 [-0.14, -0.06] **worse** | 0.07 [0.02, 0.12] **match** | 0.10 [0.02, 0.18] **undecided** |
| Nemotron 3 Nano 4B (Q4_K_M) | 0.10 [-0.11, 0.28] **undecided** | -0.18 [-0.23, -0.12] **worse** | 0.09 [0.04, 0.13] **match** | 0.17 [0.07, 0.26] **worse** |
| Qwen3.5-9B | -0.16 [-0.20, -0.12] **worse** | -0.12 [-0.17, -0.07] **worse** | 0.00 [-0.04, 0.05] **match** | 0.11 [0.01, 0.22] **undecided** |
| Qwen3.5-4B (control) | -0.21 [-0.25, -0.17] **worse** | -0.14 [-0.19, -0.09] **worse** | -0.02 [-0.06, 0.03] **undecided** | 0.09 [0.01, 0.18] **undecided** |
| MiniCPM5-2B | -0.06 [-0.21, 0.11] **undecided** | -0.24 [-0.31, -0.18] **worse** | 0.06 [0.01, 0.13] **match** | 0.31 [0.18, 0.46] **worse** |
| Granite 4.2 3B | -0.16 [-0.21, -0.10] **worse** | -0.21 [-0.27, -0.15] **worse** | -0.02 [-0.05, 0.00] **undecided** | 0.14 [0.02, 0.25] **undecided** |
| LFM2.5-2.6B | 0.01 [-0.05, 0.07] **undecided** | -0.24 [-0.31, -0.18] **worse** | 0.07 [0.02, 0.13] **match** | 0.07 [-0.06, 0.19] **undecided** |
| Jamba2 3B | -0.36 [-0.41, -0.32] **worse** | -0.39 [-0.45, -0.33] **worse** | 0.23 [0.12, 0.34] **match** | — [—, —] **n/a** |
| Gemma 4 E2B | -0.18 [-0.22, -0.13] **worse** | -0.17 [-0.22, -0.11] **worse** | 0.01 [-0.04, 0.07] **match** | 0.03 [-0.08, 0.15] **undecided** |
| Gemma 4 E4B | -0.25 [-0.29, -0.21] **worse** | -0.13 [-0.18, -0.09] **worse** | -0.02 [-0.06, 0.03] **undecided** | 0.04 [-0.05, 0.14] **undecided** |
| 12B, today's prompt | -0.03 [-0.08, 0.03] **undecided** | -0.04 [-0.09, 0.00] **undecided** | 0.26 [0.16, 0.37] **match** | 0.06 [-0.00, 0.13] **undecided** |

At the Dev proxy's best config (`local/win60s/τs0.2/τm0.2/w60`):

| Model | R5 Support | Item F1 | R10 Topics | R11 Misplaced |
|---|---|---|---|---|
| Spark-X2.6-4B | 0.01 [-0.02, 0.04] **match** | -0.03 [-0.09, 0.03] **undecided** | -0.05 [-0.11, 0.00] **undecided** | 0.11 [0.03, 0.18] **undecided** |
| Nemotron 3 Nano 4B (NVFP4) | -0.05 [-0.10, -0.00] **undecided** | -0.07 [-0.12, -0.03] **undecided** | -0.05 [-0.11, -0.01] **undecided** | 0.06 [-0.00, 0.12] **undecided** |
| Nemotron 3 Nano 4B (Q4_K_M) | -0.07 [-0.16, -0.00] **undecided** | -0.21 [-0.28, -0.12] **worse** | -0.03 [-0.08, 0.01] **undecided** | 0.13 [0.05, 0.22] **undecided** |
| Qwen3.5-9B | -0.03 [-0.06, -0.00] **undecided** | -0.05 [-0.11, 0.00] **undecided** | -0.05 [-0.09, 0.00] **undecided** | 0.07 [0.00, 0.14] **undecided** |
| Qwen3.5-4B (control) | -0.08 [-0.12, -0.04] **undecided** | -0.09 [-0.15, -0.04] **undecided** | -0.07 [-0.12, -0.01] **undecided** | 0.09 [0.02, 0.17] **undecided** |
| MiniCPM5-2B | -0.18 [-0.28, -0.11] **worse** | -0.18 [-0.25, -0.11] **worse** | -0.15 [-0.23, -0.07] **worse** | 0.28 [0.18, 0.37] **worse** |
| Granite 4.2 3B | -0.33 [-0.39, -0.26] **worse** | -0.20 [-0.25, -0.14] **worse** | -0.32 [-0.42, -0.22] **worse** | 0.10 [0.03, 0.16] **undecided** |
| LFM2.5-2.6B | -0.20 [-0.27, -0.13] **worse** | -0.27 [-0.35, -0.19] **worse** | -0.41 [-0.56, -0.27] **worse** | -0.05 [-0.15, 0.05] **match** |
| Jamba2 3B | -0.92 [-0.94, -0.89] **worse** | -0.57 [-0.62, -0.52] **worse** | -0.13 [-0.27, -0.00] **undecided** | — [—, —] **n/a** |
| Gemma 4 E2B | -0.11 [-0.15, -0.07] **worse** | -0.15 [-0.22, -0.09] **worse** | -0.17 [-0.27, -0.08] **worse** | 0.02 [-0.06, 0.12] **undecided** |
| Gemma 4 E4B | -0.10 [-0.15, -0.06] **worse** | -0.11 [-0.15, -0.05] **worse** | -0.16 [-0.21, -0.10] **worse** | 0.11 [0.04, 0.17] **undecided** |
| 12B, today's prompt | -0.06 [-0.09, -0.03] **undecided** | -0.03 [-0.07, 0.02] **undecided** | -0.12 [-0.18, -0.06] **worse** | 0.02 [-0.04, 0.08] **undecided** |

## Scores

### Check criteria

Share of the 40 meetings passing. R2 without N1 is reported, not gated (see
Findings).

| Model | R1 Format | R2 Safety | R2 without N1 | R3 No loops | R4 Surface grounding |
|---|---|---|---|---|---|
| Gemma 4 12B (teacher, baseline) | 0.85 [0.72, 0.95] | 0.75 [0.60, 0.88] | 1.00 [1.00, 1.00] | 0.97 [0.93, 1.00] | 0.78 [0.65, 0.90] |
| Spark-X2.6-4B | 0.75 [0.60, 0.88] | 0.30 [0.17, 0.45] | 0.95 [0.88, 1.00] | 0.55 [0.40, 0.70] | 0.72 [0.57, 0.85] |
| Nemotron 3 Nano 4B (NVFP4) | 0.72 [0.57, 0.85] | 0.33 [0.17, 0.47] | 1.00 [1.00, 1.00] | 0.45 [0.30, 0.60] | 0.57 [0.42, 0.72] |
| Nemotron 3 Nano 4B (Q4_K_M) | 0.00 [0.00, 0.00] | 0.12 [0.03, 0.23] | 1.00 [1.00, 1.00] | 0.47 [0.33, 0.62] | 0.30 [0.17, 0.45] |
| Qwen3.5-9B | 0.78 [0.65, 0.90] | 0.72 [0.57, 0.85] | 0.97 [0.93, 1.00] | 0.85 [0.72, 0.95] | 0.75 [0.62, 0.88] |
| Qwen3.5-4B (control) | 0.62 [0.47, 0.78] | 0.45 [0.30, 0.60] | 0.97 [0.93, 1.00] | 0.82 [0.70, 0.93] | 0.65 [0.50, 0.80] |
| MiniCPM5-2B | 0.93 [0.82, 1.00] | 0.03 [0.00, 0.07] | 0.97 [0.93, 1.00] | 0.70 [0.55, 0.85] | 0.62 [0.47, 0.78] |
| Granite 4.2 3B | 0.05 [0.00, 0.12] | 0.12 [0.03, 0.23] | 1.00 [1.00, 1.00] | 0.72 [0.57, 0.85] | 0.20 [0.07, 0.33] |
| LFM2.5-2.6B | 0.05 [0.00, 0.12] | 0.45 [0.30, 0.60] | 1.00 [1.00, 1.00] | 0.78 [0.65, 0.90] | 0.45 [0.30, 0.60] |
| Jamba2 3B | 0.00 [0.00, 0.00] | 0.65 [0.50, 0.80] | 1.00 [1.00, 1.00] | 0.93 [0.82, 1.00] | 0.00 [0.00, 0.00] |
| Gemma 4 E2B | 0.00 [0.00, 0.00] | 0.70 [0.55, 0.82] | 1.00 [1.00, 1.00] | 0.70 [0.55, 0.82] | 0.23 [0.10, 0.35] |
| Gemma 4 E4B | 0.03 [0.00, 0.07] | 0.82 [0.70, 0.93] | 1.00 [1.00, 1.00] | 0.90 [0.80, 0.97] | 0.68 [0.53, 0.82] |
| 12B, today's prompt | 0.00 [0.00, 0.00] | 0.93 [0.82, 1.00] | 0.97 [0.93, 1.00] | 0.95 [0.88, 1.00] | 0.00 [0.00, 0.00] |
| Baseline: empty | 1.00 [1.00, 1.00] | 1.00 [1.00, 1.00] | 1.00 [1.00, 1.00] | 1.00 [1.00, 1.00] | 1.00 [1.00, 1.00] |
| Baseline: wrong meeting | 0.78 [0.65, 0.90] | 0.88 [0.78, 0.97] | 1.00 [1.00, 1.00] | 1.00 [1.00, 1.00] | 0.25 [0.12, 0.40] |
| Baseline: AMI itself, word score off | 0.00 [0.00, 0.00] | 0.80 [0.68, 0.93] | 0.97 [0.93, 1.00] | 0.97 [0.93, 1.00] | 0.28 [0.15, 0.42] |

### Anchored criteria at the Dev proxy's config

| Model | R5 Support | R5 Key Points | R5 items | Item F1 | R8 Owners | R10 Topics | R11 Misplaced |
|---|---|---|---|---|---|---|---|
| Gemma 4 12B (teacher, baseline) | 0.92 [0.89, 0.94] | 0.88 [0.83, 0.92] | 0.94 [0.91, 0.97] | 0.57 [0.52, 0.62] | 0.39 [0.24, 0.54] | 0.93 [0.89, 0.96] | 0.26 [0.19, 0.32] |
| Spark-X2.6-4B | 0.93 [0.89, 0.96] | 0.92 [0.87, 0.97] | 0.93 [0.90, 0.96] | 0.54 [0.48, 0.60] | 0.46 [0.24, 0.70] | 0.88 [0.83, 0.93] | 0.36 [0.28, 0.44] |
| Nemotron 3 Nano 4B (NVFP4) | 0.87 [0.81, 0.92] | 0.89 [0.82, 0.94] | 0.85 [0.79, 0.91] | 0.50 [0.43, 0.56] | 0.52 [0.30, 0.72] | 0.88 [0.82, 0.92] | 0.32 [0.25, 0.39] |
| Nemotron 3 Nano 4B (Q4_K_M) | 0.84 [0.76, 0.91] | 0.80 [0.73, 0.91] | 0.86 [0.75, 0.92] | 0.36 [0.28, 0.47] | 0.00 [0.00, 0.00] | 0.90 [0.86, 0.93] | 0.38 [0.29, 0.48] |
| Qwen3.5-9B | 0.88 [0.85, 0.91] | 0.86 [0.82, 0.91] | 0.90 [0.87, 0.93] | 0.52 [0.47, 0.58] | 0.52 [0.31, 0.74] | 0.88 [0.84, 0.92] | 0.32 [0.25, 0.41] |
| Qwen3.5-4B (control) | 0.84 [0.79, 0.87] | 0.83 [0.78, 0.88] | 0.84 [0.79, 0.88] | 0.48 [0.42, 0.53] | 0.45 [0.28, 0.63] | 0.86 [0.82, 0.91] | 0.35 [0.27, 0.43] |
| MiniCPM5-2B | 0.73 [0.63, 0.81] | 0.71 [0.51, 0.82] | 0.77 [0.72, 0.82] | 0.39 [0.33, 0.45] | 0.48 [0.23, 0.70] | 0.78 [0.71, 0.84] | 0.53 [0.42, 0.64] |
| Granite 4.2 3B | 0.59 [0.52, 0.65] | 0.50 [0.43, 0.58] | 0.63 [0.55, 0.69] | 0.38 [0.32, 0.44] | 0.26 [0.11, 0.40] | 0.61 [0.52, 0.70] | 0.36 [0.29, 0.41] |
| LFM2.5-2.6B | 0.72 [0.64, 0.79] | 0.69 [0.59, 0.78] | 0.73 [0.66, 0.80] | 0.31 [0.24, 0.37] | 0.27 [0.00, 0.60] | 0.52 [0.36, 0.67] | 0.20 [0.11, 0.29] |
| Jamba2 3B | 0.00 [0.00, 0.00] | — | — | 0.00 [0.00, 0.00] | — | 0.80 [0.68, 0.91] | — |
| Gemma 4 E2B | 0.81 [0.76, 0.85] | 0.76 [0.70, 0.81] | 0.84 [0.79, 0.89] | 0.43 [0.35, 0.49] | 0.00 [0.00, 0.00] | 0.76 [0.67, 0.85] | 0.28 [0.19, 0.37] |
| Gemma 4 E4B | 0.81 [0.77, 0.85] | 0.78 [0.73, 0.83] | 0.84 [0.80, 0.89] | 0.47 [0.40, 0.53] | 0.08 [0.00, 0.25] | 0.77 [0.72, 0.82] | 0.36 [0.30, 0.43] |
| 12B, today's prompt | 0.86 [0.82, 0.89] | 0.80 [0.73, 0.86] | 0.89 [0.86, 0.93] | 0.55 [0.50, 0.59] | 0.23 [0.04, 0.45] | 0.81 [0.75, 0.86] | 0.28 [0.21, 0.35] |
| Baseline: empty | 0.83 [0.77, 0.90] | 0.83 [0.77, 0.90] | — | 0.00 [0.00, 0.00] | — | 0.71 [0.65, 0.77] | 1.00 [1.00, 1.00] |
| Baseline: wrong meeting | 0.39 [0.33, 0.46] | 0.20 [0.14, 0.26] | 0.54 [0.47, 0.62] | 0.27 [0.23, 0.32] | 0.15 [0.00, 0.36] | 0.31 [0.23, 0.40] | 0.39 [0.32, 0.46] |
| Baseline: AMI itself, word score off | 0.89 [0.85, 0.93] | — | 0.89 [0.85, 0.93] | 0.79 [0.72, 0.84] | 0.43 [0.21, 0.67] | 0.87 [0.81, 0.92] | 0.03 [0.01, 0.05] |

At the starting guess, the order of the top four is the same (Spark 0.32,
Nemotron 0.29, 9B 0.27, Qwen3.5-4B 0.25 against the 12B's 0.39). Both
configs are in `out/rubric/report.md`.

### Item F1 across the 162-config sweep

Rank among the 13 model rows under each config (baselines left out).

| Model | Median Item F1 | Range | Median rank | Rank range | Beats Qwen3.5-4B | Within 0.05 of the 12B |
|---|---|---|---|---|---|---|
| Gemma 4 12B (teacher, baseline) | 0.42 | 0.28–0.57 | 1 | 1–2 | 162/162 | 162/162 |
| Spark-X2.6-4B | 0.37 | 0.22–0.54 | 3 | 2–4 | 162/162 | 50/162 |
| Nemotron 3 Nano 4B (NVFP4) | 0.35 | 0.21–0.50 | 4 | 3–7 | 160/162 | 16/162 |
| Nemotron 3 Nano 4B (Q4_K_M) | 0.22 | 0.15–0.36 | 9 | 7–11 | 3/162 | 0/162 |
| Qwen3.5-9B | 0.33 | 0.17–0.52 | 5 | 3–6 | 162/162 | 7/162 |
| Qwen3.5-4B (control) | 0.28 | 0.15–0.48 | 7 | 6–8 | 0/162 | 0/162 |
| MiniCPM5-2B | 0.19 | 0.08–0.39 | 11 | 9–12 | 0/162 | 0/162 |
| Granite 4.2 3B | 0.18 | 0.11–0.38 | 10 | 9–12 | 0/162 | 0/162 |
| LFM2.5-2.6B | 0.18 | 0.08–0.31 | 12 | 10–12 | 0/162 | 0/162 |
| Jamba2 3B | 0.00 | 0.00–0.00 | 13 | 13–13 | 0/162 | 0/162 |
| Gemma 4 E2B | 0.24 | 0.15–0.43 | 8 | 6–9 | 21/162 | 0/162 |
| Gemma 4 E4B | 0.27 | 0.14–0.47 | 7 | 5–9 | 74/162 | 2/162 |
| 12B, today's prompt | 0.38 | 0.23–0.55 | 2 | 1–4 | 162/162 | 88/162 |

## Head to head among the finalists

Paired differences on the 40 meetings, 95% intervals. "Clear" is an interval
that leaves out zero. Nemotron here is the NVFP4 build.

| Pair | Item F1, starting guess | Item F1, proxy | R5 Support, proxy | R3 No loops | R4 Grounding | R8 Owners, start |
|---|---|---|---|---|---|---|
| Spark − Qwen3.5-4B | +0.08 [+0.03, +0.13] clear | +0.06 [+0.01, +0.12] clear | +0.09 [+0.05, +0.14] clear | −0.27 [−0.43, −0.10] clear | +0.07 [−0.10, +0.25] | −0.04 [−0.35, +0.23] |
| Spark − Nemotron | +0.03 [−0.03, +0.09] | +0.04 [−0.01, +0.10] | +0.06 [+0.01, +0.11] clear | +0.10 [−0.12, +0.33] | +0.15 [−0.05, +0.35] | −0.26 [−0.54, −0.03] clear |
| Spark − Qwen3.5-9B | +0.05 [+0.00, +0.10] | +0.02 [−0.03, +0.07] | +0.04 [+0.01, +0.08] clear | −0.30 [−0.48, −0.12] clear | −0.03 [−0.20, +0.15] | +0.10 [−0.35, +0.48] |
| Nemotron − Qwen3.5-4B | +0.05 [+0.00, +0.09] | +0.02 [−0.03, +0.07] | +0.03 [−0.03, +0.09] | −0.37 [−0.57, −0.17] clear | −0.08 [−0.25, +0.12] | +0.22 [+0.02, +0.45] clear |

## Cost (R13)

| Model | Download | Median s per meeting | Gen tok/s | Memory, first call | Memory, highest | Cut off | Empty |
|---|---|---|---|---|---|---|---|
| Gemma 4 12B (teacher, baseline) | 7.7 GB | 33 | 41 | 10.6 GB | 21.0 GB | 0 | 0 |
| Spark-X2.6-4B | 2.6 GB | 19 | 52 | 3.7 GB | 10.3 GB | 0 | 0 |
| Nemotron 3 Nano 4B (NVFP4) | 2.9 GB | 14 | 68 | 6.7 GB | 13.2 GB | 0 | 0 |
| Nemotron 3 Nano 4B (Q4_K_M) | 2.8 GB | 30 | 52 | 3.6 GB | 9.4 GB | 3 | 0 |
| Qwen3.5-9B | 7.6 GB | 30 | 47 | 10.5 GB | 13.9 GB | 0 | 0 |
| Qwen3.5-4B (control) | 3.4 GB | 28 | 50 | 5.6 GB | 12.3 GB | 0 | 0 |
| MiniCPM5-2B | 1.6 GB | 16 | 67 | 2.6 GB | 8.5 GB | 3 | 0 |
| Granite 4.2 3B | 2.2 GB | 28 | 46 | 3.9 GB | 11.3 GB | 0 | 0 |
| LFM2.5-2.6B | 1.7 GB | 27 | 93 | 2.2 GB | 4.8 GB | 22 | 16 |
| Jamba2 3B | 1.9 GB | 18 | 86 | 2.2 GB | 2.8 GB | 0 | 0 |
| Gemma 4 E2B | 4.3 GB | 16 | 65 | 4.8 GB | 5.9 GB | 0 | 0 |
| Gemma 4 E4B | 6.1 GB | 26 | 46 | 6.9 GB | 9.8 GB | 0 | 0 |
| 12B, today's prompt | 7.7 GB | 34 | 38 | 11.2 GB | 19.5 GB | 0 | 0 |

The ship gate (step 6) is a download of 3 GB or less and a first call of 5 GB
or less. Spark is inside it untrained. Nemotron is inside it only as the
Q4_K_M GGUF, which scores far worse than its NVFP4 build (Findings). The 9B is
outside it by more than double on both.

## Meetings failing each check rule

| Model | Meetings failing each rule |
|---|---|
| Gemma 4 12B (teacher, baseline) | M5 29, N1 10, F6 6, G1 3, N3 3, A4 3, T1 3, L2 3, F1 1, L1 1, G2 1 |
| Spark-X2.6-4B | N1 27, M5 26, L1 22, L2 12, T1 11, F2 9, G1 5, G2 2, N2 1, N4 1, A2 1, F5 1 |
| Nemotron 3 Nano 4B (NVFP4) | M5 29, N1 27, T1 15, G1 14, L1 13, F6 10, L2 3, F1 2, G2 1, A2 1, L3 1, A5 1 |
| Nemotron 3 Nano 4B (Q4_K_M) | N1 35, A2 34, F5 34, M5 28, T1 25, G1 23, L1 13, F6 8, F1 6, G2 4, L3 2, G3 1 |
| Qwen3.5-9B | L1 33, M5 30, N1 10, F6 8, T1 7, L2 5, G1 3, A4 2, F5 2, N3 2, A5 1, N4 1 |
| Qwen3.5-4B (control) | M5 33, L1 23, N1 21, F6 13, T1 9, G1 7, L2 6, G2 4, A4 3, N3 2, F1 2, L3 2, N4 1 |
| MiniCPM5-2B | N1 39, L3 14, M5 13, G1 10, T1 8, G2 6, L1 4, F1 3, N2 1 |
| Granite 4.2 3B | F6 38, N1 35, T1 32, L2 31, M5 28, G1 27, F1 15, L1 5, A2 5, F5 4, G2 3, N3 3, A4 1 |
| LFM2.5-2.6B | L1 30, N1 22, G1 21, T1 21, F6 20, F1 20, L3 19, M5 18, F3 16, G2 8, F2 2, F5 1, G3 1 |
| Jamba2 3B | F1 40, F6 40, G1 40, L1 40, L3 40, T1 27, G2 26, N1 14, N3 2, G3 1, F4 1 |
| Gemma 4 E2B | F6 39, A2 36, F5 34, G1 28, L1 28, L2 26, M5 22, F1 19, N1 12, T1 11, N3 9, G2 3, L3 3, G3 2 |
| Gemma 4 E4B | A2 33, F6 33, M5 28, L2 23, L1 18, G1 10, N3 8, N1 7, T1 5, G2 3 |
| 12B, today's prompt | F6 40, G1 40, A4 31, F5 30, L2 27, M5 27, T1 19, N3 5, F1 4, G2 3, N1 2, A2 1, N4 1 |

## Findings

- **Spark's and Nemotron's (NVFP4) weak spot is R3, phrases repeated across
  sections.** A Decision gets restated word for word in a Key Point and in
  the Summary ("voice recognition for locating the remote" three times).
  It's the same habit M5 counts, and the kind of thing step 3's revise loop
  and training target. The 9B and Qwen3.5-4B do it far less (R3 0.85 and
  0.82, against 0.55 and 0.45).
- **Nemotron's GGUF build isn't the same model in practice.** On the same
  prompt, `nemotron-3-nano:4b-q4_K_M` (llama.cpp, 3.6 GB first call) passes
  format in 0 of 40 meetings against 29 for the NVFP4 build (MLX, 6.7 GB), and
  its Item F1 falls from 4th to 9th. 127 of its 1,160 lines have doubled
  spaces (`-  [  ]` for `- [ ]`), against none for the NVFP4 build or Spark's
  GGUF. The chat templates are identical, so it's the runtime's decoding or
  the quantised Mamba layers, not the prompt. Until a GGUF of our own (after
  training) is shown to keep the NVFP4 build's quality, Nemotron has no build
  that's both good and inside the memory gate.
- **R2 is almost entirely N1:** 8-word runs copied from the prompt's spec
  or samples ("a fruit and vegetable theme into the remote"). Without N1,
  every model but Spark passes R2 in 39 or 40 meetings, and Spark in 38. A
  trained student runs on a one-line prompt with no samples to copy, so N1
  ranks base models badly for training. It stays in the gate as the spec
  says; R2 without N1 is shown beside it.
- **Greedy decoding loops on MiniCPM5,** as its card warned. In 3 meetings
  it repeated one bullet until the 2,048-token cap.
- **LFM2.5 can't be stopped from reasoning through Ollama.** Its template
  "always thinks". Hidden reasoning used the whole budget in 16 of 40 replies,
  which came back empty. The app would show an empty summary.
- **Memory climbs over a session on every runner,** as step 2 found.
  Spark went from 3.7 GB on its first call to 10.3 GB, and Nemotron's NVFP4
  build from 6.7 to 13.2 GB. The model choice doesn't fix this; the app's
  runner settings do.
- **On the starting guess, R5 punishes long bullets.** The 12B on today's
  shorter prompt has better-supported Key Points (0.26) than on the spec
  (0.05). Read R5 per section (Key Points against items) until calibration.

## Changes to the rubric made while running

Each is in the code with a comment; none touches the §8 gate rule.

1. **Local matching** (`mode: "local"`) beside §4 as written (`"global"`),
   and 3-act and 60-second units beside single acts. This follows the rubric
   session's Dev prototype (`rubric-prototype-findings.md`). Both are in the
   sweep, and calibration chooses between them.
2. **R3 counts an action's task once however many owners share it.** A4
   caps an item at two owners, so a task for three people has to be split,
   and the first version of R3 read that as a loop (4 of the 12B's notes).
   Runs are counted within lines, as step 2 did for N1 and N2.
3. **A closed `<think>` block is cut before scoring R2 to R12.** R1 still
   fails the reply, as §2 says.
4. **An empty reply is a failed note,** scored, not skipped. The runner
   used to retry it and then drop the meeting.
5. **R5 is also reported per section**, Key Points against Decisions,
   Actions and Open Questions, as the prototype suggested.
6. **The mutation tests' "good notes"** are the six samples and the 12B's
   Dev notes. A mutation must plant a new fault: "change a number" changes
   one that's grounded now, and "all None recorded" skips a note that had no
   matches to lose.

## Next steps

1. **Your labels, about an hour:** `python3 -I tools/model-lab/rubric.py label`,
   then `calibrate`. The Dev notes it asks about are ready. `report` then
   reruns everything in under a minute with your thresholds, and the
   anchored lines gate if §6.1 passes.
2. **R10:** redesign before it gates. One option is to anchor each Key Point
   and Summary sentence to its single best turn, so a generic sentence covers
   one topic at most.
3. **Trainability check before step 3:** load Spark (`spark2_5`) and Nemotron
   (`nemotron_h`) in mlx-lm 0.32.2 and run a few LoRA steps on a 4-bit base.
   Spark is two weeks old and its numbers are vendor-reported.
4. **Nemotron's shipping build:** quantise it to GGUF ourselves (imatrix on
   our own notes) and rescore. If it still double-spaces, it can only ship on
   MLX, at 6.7 GB.
5. **Step 3** on the two finalists, Qwen3.5-4B as control, and the 9B if
   the ship gate is open to a 4 GB build.
6. **App (§10):** summaries at temperature 0. Not done; a separate commit.
