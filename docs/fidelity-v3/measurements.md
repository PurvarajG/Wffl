# Measured evidence — fidelity v3

> ## ⚠️ CORRECTION (2026-07-27) — READ BEFORE USING ANY NUMBER BELOW
>
> **The `APP full pipeline` row in §1 was produced by Parakeet, not Whisper.**
> The app's own database records for this meeting:
>
> ```
> profile: general · engine: parakeet · model: parakeet-tdt · language: en · decode: greedy
> ```
>
> No `transcriptionProfile` key existed, so `Prefs.effectiveEngine` routed to
> `.parakeet`. Every other row in §1 is a Whisper config. **The matrix compares
> Whisper configs against a Parakeet output row**, so its attribution of the
> error gap to Whisper decoder settings is void.
>
> Still valid: the app's output *was* that bad (§1 APP row), the three spans
> were really lost (§3), the glossary really does destabilise proper nouns (§5),
> and the corrector economics (§8) are real.
>
> Void or superseded: §1's attribution, §2's framing (those hypotheses were
> tested against the wrong path), §6, §7, and §10 — see
> [`PLAN-engine-and-pack-v1.md`](../../PLAN-engine-and-pack-v1.md) §1 for the
> corrected evidence, including measured `-l en` vs `-l gu` results.

**Every number here was measured on 2026-07-26 against commit `7745bf6` (v1.4.0).
Do NOT re-derive any of it. Re-running these experiments costs ~15 minutes of
compute and tens of thousands of tokens for facts already established.**

Test case: `Diversity in Satsang   Part 1.m4a`, 1234.84 s (20:34.84), 2 speakers,
English with heavy Gujarati/Sanskrit code-switching. Devotional profile content.

Meeting row in the app DB: `D82C86DC-AFE2-4BE2-8523-12EF643526B6`.

---

## 1. Attribution matrix

Reference: `large-v3-turbo` **fp16**, beam 5, `-l en`, no VAD, no prompt.
3327 content words (fillers dropped). Runtime **40 s** (~30× realtime, Metal).

All rows below: `large-v3-turbo-q5_0`, greedy, `-l en`.

| config | words | del | ins | sub | err% |
|---|---:|---:|---:|---:|---:|
| C  greedy baseline | 3396 | 36 | 110 | 222 | 11.1% |
| D  +`no_context` | 3288 | 60 | 45 | 246 | 10.6% |
| E  +VAD | 3320 | 39 | 68 | 192 | **9.0%** ← best |
| F  +`no_ctx` +VAD | 3237 | 76 | 32 | 237 | 10.4% |
| **APP full pipeline** ⚠️ | 3256 | **108** | **120** | **426** | **19.7%** |

⚠️ **This row is NOT the same model as rows C–F.** It is `parakeet-tdt`, greedy —
see the correction banner at the top of this file. The correct reading is
"Parakeet plus the app's post-correction layers scores 19.7%, where plain
Whisper turbo + VAD scores 9.0%", which is an argument about the *engine*, not
about Whisper's decoder settings.

Runtime: q5_0+greedy **33 s**; fp16+beam5 **40 s**. Seven seconds buys ~half the
error. There is no speed argument for q5_0 on this hardware.

## 2. Causes RULED OUT by measurement — do not re-investigate

| Hypothesis | Verdict | Evidence |
|---|---|---|
| q5_0 quantization causes the deletions | **NO** | q5_0 retains all lost spans (configs C–F) |
| `language = "auto"` | **NO** | auto-detects `en` at p=0.999 |
| VAD (`whisper_vad_default_params`) | **NO** | VAD is the *best* config, 9.0% |
| `params.no_context = true` | **NO** | −0.5 pt, negligible. Leave it alone. |
| `AudioChunker.containsSpeech` silence gate | **NO** | lost regions measure −17 to −13 dBFS; threshold is −42 dBFS |
| `TranscriptCorrector` deleted the big spans | **NO** | `transcript_edits.old` shows text **already truncated** on arrival |

## 3. The three deleted spans — CONFIRMED REAL

Decoded from **isolated audio clips** with fp16 **and** q5_0 independently.
Both models produce all three. They are in the audio; the app removes them.

| # | Clip | Content the app lost |
|---|---|---|
| A | 893–930 s | "Nothing that can be traced back… There's no attributed book or this or that to him from before." — **the entire answer** to "did he write before he became a sadhu?" |
| B | 995–1020 s | "We want to make you the Mahant of Dhola**(Dholera)**. He ran away." — without it the surviving "He's like, I'm gone" is a non-sequitur |
| C | 745–775 s | "he becomes a Tyagi's Tyagi… A Tyagi's Tyagi." — the phrase the speaker then explains |

Regenerate the clips (audio is at `~/Library/Application Support/Wffl/recordings/D82C86DC-AFE2-4BE2-8523-12EF643526B6.m4a`):

```bash
ffmpeg -y -i INPUT.m4a -ar 16000 -ac 1 -c:a pcm_s16le audio16k.wav
ffmpeg -y -i audio16k.wav -ss 893 -to 930  -c copy clip_A.wav
ffmpeg -y -i audio16k.wav -ss 995 -to 1020 -c copy clip_B.wav
ffmpeg -y -i audio16k.wav -ss 745 -to 775  -c copy clip_C.wav
```

Damage signature in the stored transcript — a lowercase mid-sentence splice
where the deleted span used to be:

```
898.0 → 916.3 | "It's a good question. as he becomes a Tyagi and is joining all this…"
```

## 4. Both machine references are lossy — neither is ground truth

| | mine (fp16, beam5, no prompt) | gpt5.6 audit (q5_0, beam5, **+prompt**) |
|---|---|---|
| words | 3327 | 3208 |
| keeps span A / B / C | yes / yes / yes | **no / no / no** |

The two independent references agree on only **91.8%** of tokens
(del 151, ins 68, sub 202). The prompted reference drops real content — which is
itself evidence that a glossary prompt can *cause* deletion.

**Consequence:** the gpt5.6 audit's headline figures (22.8% → 19.2% error,
87.3% recall, "recall unchanged") are measured against a lossy reference and
**understate** the deletion problem. Do not adopt either file as the CI gate
without human audio verification.

Artifacts: `reference-fp16-beam5.txt` / `.vtt`, `reference-gpt-q5-beam5.txt`,
`observed-app-raw.txt` (the 74 stored segments, this directory).

## 5. Proper-noun instability

The glossary is supposed to stabilise names. It makes them worse.

| term | fp16 reference | app output |
|---|---:|---:|
| Nishkulanand Swami | 5 spellings | **8** (`Nishkam and`, `Nishwan Sui`, `Nishkon Swami`, `Nishkudan Swami`, …) |

**Root cause:** the 639-term glossary contains **zero** entries for `muktan`,
`nishkul`, `dholera`, `shakta`, or `pad`. The glossary string actually injected
into decoding is the modern guru lineage:

```
Glossary: Pujya, Swaminarayan, Bhagwan Swaminarayan, Gunkirtan Swami,
Mahant Swami Maharaj, Pramukh Swami Maharaj, Yogiji Maharaj, Shastriji Maharaj,
Bhagatji Maharaj, Gunatitanand Swami, Gopalanand Swami, Akshardham,
Purushottam, bhakti, katha, kirtan.
```

For a talk about the 19th-century Paramhansa poets this biases decoding toward
the **wrong** names. Likely why `Gunatitanand` bleeds in as "Gunatya and Swami".

**Latent collision:** `brahmand` (cosmos) is a term at `Vocabulary.swift:513`.
`Brahmanand` (the poet) → `brahmand` is edit distance 1, length delta 2,
similarity 0.9 — it passes every filter in `correctWord`. The poet's name will be
silently rewritten to a cosmology term whenever Whisper spells it correctly.

## 6. `pad` → `bud` is quantization, NOT a correction gap

| | `pads` | `buds` |
|---|---:|---:|
| fp16 reference | **8** | 0 |
| q5_0 | 0 | 5 |

The gpt5.6 audit attributes this to "no sufficiently grounded contextual
correction". That is wrong. It is a model-precision effect and a one-line config
fix. `pad` is the central technical term of the recording's subject matter.

## 7. Hallucination gate is net-negative on this file

- Deletes real speech (§3).
- **Keeps** the classic YouTube artifact "Thank you for watching" at 0:00, which
  appears in **neither** raw whisper run.

## 8. LLM corrector economics

From the app's own `transcript_edits` ledger, 74 segments → 74 `gemma3:4b` calls:

| | |
|---|---:|
| accepted | 16 |
| …pure `'` → `’` swaps | 8 |
| …genuinely useful | **1** (`Vachnamurats` → `Vachanamrut`) |
| …accepted **deletions** of real words | several (`Appreciating that.`, `you`, `going`, `in`) |
| rejected | 58 — of which 44 say `"LLM unavailable or output rejected by sanitize"` |
| prompt tokens | **~153,000** (all 639 terms resent per segment) |

`sanitize` bounds growth (`ratio < 1.7`) but has **no floor on shrinkage** — a
truncating model passes trivially, because a truncation introduces no new
content words.

## 9. Structural observations

- **`--transcribe` deadlocks.** `WfflApp.init()` is `@MainActor`; `Task { }`
  inherits main-actor isolation and cannot run while `sema.wait()` blocks main.
  Measured: **0.01 s CPU after 15 minutes**. `AppState.swift:553` uses
  `Task.detached` correctly; this path does not.
- **Timestamp granularity destroyed.** Whisper natively emits **382 segments
  averaging 2.9 s**. The DB holds **74 segments averaging 16.6 s**, perfectly
  contiguous. `CleanupAssembler` then keeps only the first timecode per
  paragraph → a single `**[4:05]**` heads 65 s of speech.
- **`duration = 0.0`** on the meetings row while segments span 1231 s.
- **Zero `###` headings** in the stored cleaned markdown across 60 paragraphs,
  despite the README advertising topic headings.
- **Profile trap.** Prefs carry no `transcriptionProfile` key, so this ran as
  `general` — **beam search off** — on maximally devotional content.

## 10. ~~UNRESOLVED~~ — RESOLVED 2026-07-27

**Answer: the transcript came from `ParakeetFileTranscriber`.** It drives
`AudioChunker` (4–20 s silence-aligned cuts), which is why the segments cross
every 5-minute boundary and why they are contiguous ≤20 s blocks. Verified
against the DB: 74 segments, avg 16.6 s, min 4.0, max 20.7 — exactly the
chunker's bounds. This also explains T-02's BLOCKED finding (`WhisperFileTranscriber`
preserved all three spans because Whisper never deleted them). Do **not**
implement overlap-stitching on the basis of the original text below.

The original open question, kept for the record:

## ~~10. UNRESOLVED — investigate before touching offline chunking~~

The gpt5.6 audit's finding #15 assumes hard 5-minute offline cuts. But the stored
segments show **no boundary at 300/600/900/1200 s** — they cross all four
(e.g. `290.6 → 309.9`). The 74 contiguous ≤20 s blocks match `AudioChunker`
(live path), not `WhisperFileTranscriber` (5-min chunks). `duration = 0.0` also
suggests the import path's `updateDuration` never ran.

**This transcript did not come from the path either audit assumed.** Resolve
this (T-01 unblocks it) before implementing overlap-stitching in the wrong place.
