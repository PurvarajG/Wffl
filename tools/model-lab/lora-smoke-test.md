# LoRA smoke test: can the finalists be trained?

Run 2026-11-01 on this Mac (M5 Pro, 24 GB, macOS 27.0.1) with mlx-lm 0.32.2
(mlx 0.32.4, transformers 5.22.1) in an isolated uv environment. This is next
step 3 of [rubric-results.md](rubric-results.md): before step 3 commits to
Spark and Nemotron, check that each can be LoRA-trained at all.

## Verdict: both finalists train; the Qwen3.5 control doesn't at meeting length

| Model | Architecture | Loads | Loss falls | s/iter | MLX peak | Fuse + generate |
|---|---|---|---|---|---|---|
| **Spark-X2.6-4B** | `spark2_5` | yes | **yes**, 2.10 → 0.28 | **4.3** | **6.2 GB** | **works** |
| **Nemotron 3 Nano 4B** | `nemotron_h` | yes | **yes**, 2.18 → 0.26 | 7.9 | 11.2 GB, only with an 11 GB cap | **works** |
| Qwen3.5-4B (control) | `qwen3_5` | yes | **not at 2k tokens** (killed); yes at 400 tokens, 2.32 → 0.10 | 4.6 at 400 tokens | 9.0 GB at 400 tokens | works at 400 tokens |

- **Spark is the easy one.** It's a plain transformer and trained with
  stock `mlx_lm.lora` and no workarounds. Memory never fell below 39% free
  in training.
- **Nemotron trains, but only with an MLX memory cap.** Uncapped, its first
  training step took the Mac to 8% free and the watchdog killed it. With
  `mx.set_memory_limit(11 GB)` it ran all 20 steps at an 11.2 GB peak
  (34% free at worst). The `mlx_lm.lora` CLI has no flag for this, so step 3
  needs a three-line wrapper.
- **Qwen3.5 isn't a working control at these lengths.** Its training path is
  a Python loop over every token (Findings). One step at 512 tokens used
  10.6 GB, and 1,024 tokens took the Mac to 13% free. It does train end to end
  at about 400 tokens, so the pipeline itself is sound.

**For the shortlist:** both finalists are trainable here, so step 3 can go
ahead on them. Spark is the lower-risk bet on memory and speed. Qwen3.5-4B
(control) and Qwen3.5-9B (reference) can't be LoRA-trained at meeting
length with mlx-lm 0.32.2 on this Mac.

## How it was run

- **Models.** `mlx-community/Spark-X2.6-4B-OptiQ-4bit` (revision
  `6d83e911abef`, 3.05 GB, 4-bit and 8-bit layers mixed),
  `mlx-community/NVIDIA-Nemotron-3-Nano-4B-4bit` (`c4d79ba1901d`, 2.25 GB) and
  `mlx-community/Qwen3.5-4B-MLX-4bit` (`32f3e8ecf654`, 3.06 GB). Each went
  into its own folder, without the repos' `*.py` remote code. mlx-lm uses its
  own model classes, and nothing ran with `trust_remote_code`.
- **Data.** The six AMI samples as chat examples: a one-line system prompt
  ("Write Wffl meeting notes for this transcript."), the transcript cut at
  the last line boundary before 7,000 characters (about 1.8k tokens), and the
  sample's notes as the reply. That makes 2.1k to 2.6k tokens per example, of
  which 267 to 531 are trained (`--mask-prompt`, notes only).
  `valid.jsonl` is the first two training examples, so validation loss shows
  fitting, not generalisation.
- **Training.** `mlx_lm.lora --train --iters 20 --batch-size 1
  --grad-checkpoint --num-layers -1 --learning-rate 1e-4 --max-seq-length 3072
  --mask-prompt --seed 0`, LoRA rank 8, scale 20. `--num-layers -1` puts
  adapters on every layer, so the backward pass goes through every layer type
  (Mamba, attention, MLP).
- **Measurement.**
  - s/iter and MLX peak come from mlx-lm's own per-step numbers. The CLI
    computes them but doesn't print them, so a small wrapper logged them
    through the training callback. s/iter is the median of steps 2 to 20.
  - Peak footprint comes from `/usr/bin/time -l`. Max RSS misses Metal
    buffers (Spark reads 3.5 GB), so footprint is the number to read.
  - A watchdog polled `memory_pressure` every 1 to 2 seconds and killed any
    run below 20% free. `ollama ps` was empty before each run, and one model
    ran at a time.
- **Fuse and generate.** `mlx_lm.fuse` with defaults, which re-quantises to
  the base model's bits (Spark's 4/8-bit layout came through unchanged).
  Generation used the held-out test meeting ES2004a, cut the same way,
  temperature 0, 500 tokens max and `enable_thinking: false`. It ran three
  ways: fused, base plus adapter, and base.
- **Fuse check.** Mean trained-token loss on the six training examples for
  base, base plus adapter, and fused.
- **Reproducible.** Rerunning Spark gave bit-identical adapter weights and
  identical generations.

## Training

| Model | Tokens per example | Trainable | Train loss, step 1 → 20 | Val loss, start → end | s/iter, median (first) | MLX peak | Peak footprint | Lowest free | Wall |
|---|---|---|---|---|---|---|---|---|---|
| Spark-X2.6-4B | 2,228–2,557 | 16.2M (0.40%) | 2.10 → 0.28 | 2.30 → 0.31 | 4.26 (4.66) | 6.16 GB | 9.5 GB | 39% | 100 s |
| Nemotron 3 Nano 4B, 11 GB cap | 2,123–2,417 | 10.3M (0.26%) | 2.18 → 0.26 | 2.42 → 0.19 | 7.90 (8.88) | 11.15 GB | 12.6 GB | 34% | 169 s |
| Nemotron 3 Nano 4B, no cap | 2,123–2,417 | 10.3M | killed in step 1 | 2.42 → n/a | n/a | n/a | n/a | **8%** | n/a |
| Qwen3.5-4B, 2k tokens | 2,163–2,483 | 16.2M (0.39%) | killed in training | 2.04 → n/a | n/a | n/a | n/a | **18%** | n/a |
| Qwen3.5-4B, 400 tokens | 359–416 | 16.2M | 2.32 → 0.10 | 2.63 → 0.31 | 4.61 (14.55) | 9.01 GB | 15.9 GB | 29% | 126 s |

The 400-token Qwen run used the three samples with the shortest notes, each
with a 132- to 267-character transcript, and the same flags with
`--max-seq-length 512` and the 11 GB cap.

## Memory against sequence length

One forward and backward step on the first sample, set up the way
`mlx_lm.lora` does it (all layers, checkpointing, 11 GB cap):

| Tokens | Spark | Nemotron | Qwen3.5-4B |
|---|---|---|---|
| 512 | 4.4 GB, 1.3 s | 4.8 GB, 4.6 s | 10.6 GB, 12.6 s |
| 1,024 | 4.8 GB, 2.5 s | 7.4 GB, 4.4 s | killed, 13% free |
| 2,048 | 5.5 GB, 5.0 s | 12.0 GB (at the cap), 8.6 s | n/a |
| 2,560 | 6.0 GB, 6.0 s | 12.0 GB (at the cap), 10.8 s | n/a |

Spark grows about 0.8 GB per 1k tokens. Nemotron grew 2.6 GB from 512 to
1,024 tokens and then sat at the cap, so its uncapped need can't be read
from this table.

## Fuse check: loss on the six training examples

| Model | Base | Base + adapter | Fused |
|---|---|---|---|
| Spark-X2.6-4B | 2.300 | 0.253 | 0.305 |
| Nemotron 3 Nano 4B | 2.356 | 0.173 | 0.160 |
| Qwen3.5-4B, 400 tokens | 2.484 | 0.157 | 0.143 |

Fusing keeps what the adapter learned. Re-quantising costs Spark 0.05 and
the others nothing.

## Generation from the fused model (held-out ES2004a)

| Model | Prompt tokens | Generation tok/s | Peak memory | What it wrote |
|---|---|---|---|---|
| Spark-X2.6-4B | 2,163 | 77 | 4.1 GB | `## Summary` only, repeating one pair of sentences up to the 500-token cap |
| Nemotron 3 Nano 4B | 2,082 | 107 | 6.9 GB | All five sections. Key Points loop, and the Decisions are memorised ("sold for 25 Euros") |
| Qwen3.5-4B, 400 tokens | 2,130 | 96 | 4.1 GB | All five sections, a few repeats, and it stopped on its own at 359 tokens |

- **The adapters do teach the shape.** All three base models write their
  own format: bold titles, attendee blocks, "Date: [Insert Date]". After 20
  steps every adapter writes `## Summary` and `## Key Points`.
- **Spark's fused and unfused outputs differ.** Base plus adapter writes a
  Summary and Key Points, then loops. The fused model loops inside the
  Summary. The fuse check shows the training survived fusing, so this is
  0.05 of re-quantisation noise tipping a heavily overfit model into a
  different greedy loop.
- **The loops and invented facts are what 20 steps on six examples gives.**
  Training loss ended at 0.1 to 0.3. "25 Euro" is in two of the samples and
  not in the held-out transcript. None of this says anything about how good
  a trained student will be.
- **No doubled spaces** in any MLX output, Nemotron's included (compare the
  GGUF finding in rubric-results.md).

## Findings for step 3

- **Qwen3.5 trains through a per-token loop.** `qwen3_5.py` passes
  `use_kernel=not self.training`, so in training the Gated DeltaNet layers
  fall back to `gated_delta_ops`. That's a Python loop over every token,
  which keeps a 2 MB float32 state per token per layer for the backward
  pass. Memory and time grow with length far faster than for the other two.
  This hits the 9B too, since it's the same architecture.
- **Nemotron needs the cap because MLX's default limit is above physical
  RAM.** MLX's default limit is 1.5 times the recommended working set, about
  28 GB here. With 11 GB set, the same step fits in 11.2 GB. The wrapper is
  `mx.set_memory_limit(...)` before `mlx_lm.lora.main()`. Nemotron's Mamba2
  layers train through `ssm_attn`, in 256-token chunks of plain MLX ops. The
  custom Metal kernel is only used for one-token decoding.
- **Real meetings are longer than this test.** Step 2's test meetings run
  4k to 15k tokens of transcript, and this test used about 2k. Spark's slope
  suggests whole meetings fit. Nemotron's is unknown above 2.5k tokens.
  Probe 4k, 8k and 15k before fixing step 3's sequence length or deciding to
  split meetings.
- **Spark's tokenizer asks to run remote code.** Its `config.json` names
  `configuration_spark.py`, so transformers prompts "Do you wish to run the
  custom code? [y/N]" on every load. With stdin closed it falls back and
  loads fine. Run step 3 with stdin closed, or a prompt will stall an
  unattended run.
- **Render training data the way the app will prompt.** mlx-lm applies each
  chat template with its defaults. For Qwen that splits an empty think block
  across the prompt and the reply, so the first trained tokens are
  `</think>`. Spark and Nemotron end the prompt part with the closing think
  tag, so their replies start at `## Summary`.
  Step 3 should set `enable_thinking: false` both in training and at runtime.
- **Getting to Ollama is a separate problem.** `mlx_lm.fuse --export-gguf`
  supports only llama, mistral and mixtral, so none of these three. The route
  to a GGUF is `fuse --dequantize`, then llama.cpp's converter. That's part
  of step 4's Nemotron GGUF question in rubric-results.md.
- **Nemotron's MLX build is heavy at inference too:** 6.9 GB peak on a
  2.1k-token prompt, against 4.1 GB for Spark. That's above the 5 GB ship
  gate, as the rubric found for its NVFP4 build (6.7 GB).
