# Step 2 results: the scoreboard

Run 2026-10-31 with `scoreboard.py` on AMI's 20 test meetings (ES2004, ES2014,
IS1009, TS3003, TS3007, phases a to d). Step 2 of the small-model methodology.

## Gate: no off-the-shelf small model matches the 12B

So summaries don't switch without training. The gaps below are the training
target for step 3.

## How it was run

- **Prompt.** Every model got the teacher prompt: all of `notes-spec.md` plus
  the six samples, about 7k tokens. The 12B also ran once on today's
  `SummaryService.defaultSystemPrompt`, as a reference row.
- **Context.** One call per meeting at `num_ctx` 32,768, which fits every
  test meeting (4k to 15k tokens of transcript). No map-reduce.
- **Decoding.** Temperature 0 and seed 0, `think: false`, no `format` option.
  The first reply is scored with no retries, since the app doesn't retry
  either.
- **Agreement.** Bullets are matched one to one with AMI's DECISIONS, ACTIONS
  and PROBLEMS when their content words overlap by Dice ≥ 0.4.
- **Owners.** Of the matched action items where AMI names a role, how many
  name the same role.
- **Memory.** The larger of RSS and physical footprint across Ollama's runner.
  "First" is the first call. "Peak" is the highest over 20 calls: both of
  Ollama's runners keep buffers between calls, so memory climbs over a session
  without any one summary needing it.

## Scores

| Model | Prompt | Download | Format | Grounding | All checks | Decisions F1 | Actions F1 | Owners | Open Qs F1 | Summary ÷ abstract | Notes ÷ AMI | Wall s | Prompt tok/s | Gen tok/s | Memory first / peak |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `gemma4:12b-mlx` | teacher | 7.7 GB | **18/20** | **10/20** | **1/20** | **0.27** | **0.32** | **8/10** | **0.10** | 0.33 | 1.28 | 33 | 872 | 38 | 10.6 / 21.0 GB |
| `gemma4:e2b-it-qat` | teacher | 4.3 GB | 0/20 | 1/20 | 0/20 | 0.17 | 0.27 | 0/10 | 0.02 | 0.63 | 1.49 | 17 | 2,336 | 67 | **4.8** / 5.8 GB |
| `gemma4:e4b-it-qat` | teacher | 6.1 GB | 2/20 | **10/20** | 0/20 | 0.15 | 0.26 | 3/8 | 0.05 | 0.51 | 1.55 | 26 | 1,384 | 47 | 6.9 / 8.0 GB |
| `qwen3.5:4b` | teacher | **3.4 GB** | 13/20 | 7/20 | 0/20 | 0.16 | 0.27 | **8/10** | 0.02 | 0.48 | 1.61 | 32 | 1,012 | 44 | 5.6 / 12.0 GB |
| `gemma4:12b-mlx` | today | 7.7 GB | 0/20 | 0/20 | 0/20 | 0.18 | 0.35 | 4/9 | 0.07 | 0.28 | 1.33 | 38 | 527 | 34 | 11.2 / 19.5 GB |

Format, grounding and all checks count meetings that pass. The time, speed and
ratio columns are medians. No reply was cut off by `num_predict`.

Meetings failing each rule:

| Model | Prompt | Failing rules |
|---|---|---|
| `gemma4:12b-mlx` | teacher | M5 15, N1 6, G1 3, N3 3, A4 2, F6 2, T1 1 |
| `gemma4:e2b-it-qat` | teacher | F6 19, A2 18, F5 17, L2 17, G1 15, L1 15, F1 9, M5 9, N1 5, N3 4, T1 4, G2 2, G3 1 |
| `gemma4:e4b-it-qat` | teacher | F6 18, A2 15, M5 15, L1 12, L2 12, G1 5, N1 3, N3 3, G2 2, T1 2 |
| `qwen3.5:4b` | teacher | M5 18, N1 9, L1 9, F6 5, G1 5, T1 5, F1 2, G2 2, A4 1, L2 1 |
| `gemma4:12b-mlx` | today | F6 20, G1 20, A4 18, M5 14, F5 13, L2 12, T1 8, F1 2, N3 2, N1 1 |

## The gap, per score (best small model against the 12B)

| Score | 12B | Best small | Gap |
|---|---|---|---|
| Format | 18/20 | 13/20, qwen3.5 | 5 meetings |
| Grounding | 10/20 | 10/20, e4b | none |
| All checks | 1/20 | 0/20 | 1 meeting |
| Decisions F1 | 0.27 | 0.17, e2b | 0.10 |
| Actions F1 | 0.32 | 0.27, e2b and qwen3.5 | 0.05 |
| Owners | 8/10 | 8/10, qwen3.5 | none |
| Open questions F1 | 0.10 | 0.05, e4b | 0.05 |
| Memory, first call | 10.6 GB | 4.8 GB, e2b | the small models are 2 to 5.8 GB lighter |
| Download | 7.7 GB | 3.4 GB, qwen3.5 | none meets ≤ 3 GB yet |

- **The format problems are small-model habits the spec forbids.**
  - e2b and e4b write action items as `- **Owner:** task`, with bold and
    brackets, so they fail F5, F6 and A2.
  - qwen3.5 keeps the shape best, but its Key Points report decisions (M5,
    18/20).
  - All of this is the kind of thing training on the exact job fixes
    (methodology §2).
- **Base for step 4: `qwen3.5:4b` looks strongest.** It has the best format,
  owners equal to the 12B and the smallest download, and its first call uses
  5.6 GB. e4b is level with the 12B on grounding but is the largest download.
  The final pick is step 4's.

## Findings for step 3

- **The teacher itself passes every check in only 1 of 20 meetings.** Its
  main miss is M5 (15/20): Key Points that say "the team agreed…" or "decided…".
  The training filter therefore needs the revise-with-feedback loop from
  `draft_samples.py`, not single shots, or the yield will be tiny.
- **N1 fires on AMI's stock phrasing** in 6 of 20 meetings: "work on the
  technical functions design — User Interface Designer". The samples and the
  test meetings share the same scenario wording. It's a real 8-word run, so it
  stays a failure. Expect the same with any AMI-trained teacher output.
- **The spec prompt alone moves the 12B a long way.** On today's prompt the 12B
  passes format in 0 of 20 meetings; on the spec, 18 of 20. Decisions F1 goes
  from 0.18 to 0.27 and owners from 4/9 to 8/10. Action-item F1 is slightly
  higher on today's prompt (0.35 against 0.32): it writes more items, with
  free-form owners.
- **Context.** The spec plus samples costs about 7k tokens on every call. Your
  97-minute meeting comes to 34.6k prompt tokens with it, over 32k. A trained
  student with a one-line prompt avoids this. If the 12B is kept on the spec
  prompt meanwhile, the app needs `num_ctx` above 32k or map-reduce.
- **Memory climbs over a session on both runners.** On MLX it went from 10.6
  to 21 GB over 20 calls; on llama.cpp from 5.6 to 12 GB for qwen3.5, about
  0.3 GB a call from saved context checkpoints. The app's long sessions will
  see this too. It's worth a look separately from the model choice.
- **Agreement with AMI is low for every model.** Decisions F1 tops out at 0.27.
  AMI's abstractive items differ in granularity from the spec's bullets, so
  these scores rank models; they aren't accuracy.

## Changes to the checks made for scoring

- **`extra-words.txt`:** 35 ordinary English words the 1934-era macOS list
  lacks ("trendy", "keypad", "began"). Names, brands, abbreviations and terms
  stay out (Bluetooth, UI, IR, LCD), and so does "locateability".
- **T1 inflections:** `-ied`, `-ier`, `-iest` and `-est` now map back to the
  base word ("identified", "earlier", "largest").
- **G1:** in a hyphenated word only the capitalised parts are checked, so
  "TV-only" checks "TV", and a lone capital ("T-shaped") isn't a name.
- **N1 and N2:** runs are counted within one line. Words that only meet across
  two bullets weren't copied.
- All six samples still pass every check.

## Your meetings (read by eye; files on this Mac only)

- Two of the six library meetings still have transcripts: 39 and 97 minutes.
  Neither has speaker labels or the Devotional profile, so both use the
  meeting shape.
- Notes from all four models, side by side, are in
  `tools/model-lab/out/eye/*.side-by-side.md`, which is gitignored. Each model's
  failing check rules are in an HTML comment at the end of its notes.
