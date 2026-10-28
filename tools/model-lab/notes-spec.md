# Notes spec: what a good Wffl summary is

Status: **draft for approval, 2026-10-28.** Step 1 of the
[small-model methodology](../../docs/superpowers/specs/2026-10-28-small-model.md) (§5.1, §6).
Starting point: `SummaryService.defaultSystemPrompt`. The methodology docs
live in `docs/superpowers/`, which is gitignored, so those links work only
in a local checkout that has them.

This spec does two jobs:

1. **Teacher prompt.** The full text, with the samples, goes on every
   `gemma4:12b-mlx` call that makes training data.
2. **Checks.** Every rule marked **check** becomes a function in the
   step 2 scoreboard and the step 3 training filter. A note fails if any
   check fails. Rules marked **by eye** are read side by side on the
   evaluation sets. Some by-eye rules also have a **score** (agreement with
   AMI's human annotations). A score is reported, but it doesn't pass or fail
   a note.

Checks use the Python standard library only. "In the transcript" means the
full input transcript, compared case-sensitively after collapsing whitespace.
"Dictionary word" means a lower-cased word that is in `/usr/share/dict/words`.

## 1. Which shape

The shape is chosen by code, not by the model.

| Recording | Shape |
|---|---|
| Devotional profile | **Satsang talk** (§4) |
| Anything else | **Meeting** (§3) |

- **Templates.** Custom summary templates are removed when the small model
  ships (step 6). This spec covers the only shape there is.
- **The user's extra instruction.** The free-text "additional instructions"
  field stays. It can change emphasis, but not the sections or any rule here,
  and the checks run on the output either way. Whether the model follows it
  is read by eye.
- **Long transcripts.** In map-reduce, these rules apply to the final, merged
  notes. The per-chunk output is internal and isn't checked. Grounding checks
  run against the full transcript.

## 2. Rules for both shapes

### Format

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| F1 | The headings are exactly the shape's headings, as `## Name`, in order, each once | check | Extract every line starting `#`. The list must equal the shape's heading list |
| F2 | Every heading is present. An empty section is exactly the line `None recorded.` Summary and Key Points are never empty | check | Per-section body; `None recorded.` is allowed only in the sections that can be empty (§3, §4) |
| F3 | Nothing comes before the first heading or after the last section's body: no preamble, no sign-off | check | The first non-blank line is `## Summary`. Text after the last section is only bullets or `None recorded.` |
| F4 | Summary is prose: no bullets | check | No Summary line starts with `-` |
| F5 | The other sections are `- ` bullets only. Action Items use `- [ ] ` and appear only in Action Items | check | Each non-blank body line matches the section's bullet pattern |
| F6 | No other formatting: no bold or italics, tables, sub-bullets, code, other heading levels, emoji, or parentheses | check | Reject on `**`, `__`, `\|`, a backtick, a line starting with whitespace then `-`, a line starting `#` but not exactly `## `, `(` or `)`, or a character in the emoji ranges (U+1F000 to U+1FAFF, U+2600 to U+27BF) |

### Length

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| L1 | Summary is 2 to 4 sentences, at most 80 words | check | Split on `.`, `!`, `?` followed by a space or the end; count words on whitespace |
| L2 | Each bullet is one sentence, at most 30 words | check | The same split gives one sentence per bullet; word count ≤ 30 |
| L3 | Key Points count grows with transcript length | check | Transcript word count *w*: *w* < 4,500 → 3 to 6; 4,500 ≤ *w* ≤ 13,500 → 3 to 10; *w* > 13,500 → 3 to 14. About 150 words a minute, so the bands are under 30 min, 30 to 90 min, and over 90 min |

No other section has a cap. Decisions, action items, stories and the rest
are whatever happened.

### Grounding: nothing that isn't in the transcript

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| G1 | Every name in the notes appears in the transcript | check | Every capitalised word that doesn't start a sentence or a bullet must appear in the transcript. Heading words, `None recorded.` and `owner not stated` are exempt. A run of capitalised words is checked as a whole. A plural or possessive ending doesn't count as a different spelling. Known gap: a name that starts a sentence and is also an English word ("Raj") is caught only by A4 |
| G2 | Every number in the notes appears in the transcript | check | Every digit sequence (with `.` or `,` inside) must appear in the transcript as digits, or as words through a fixed map (`3` ↔ `three`, up to `twenty`, plus tens and `hundred`) |
| G3 | Dates and times are copied as said, never worked out. "Next Friday" stays "next Friday" | check | Every weekday, month name, ISO date (`\d{4}-\d{2}-\d{2}`), `\d{1,2}/\d{1,2}` and clock time in the notes must appear in the transcript as a phrase with its neighbouring words |
| G4 | Nothing is invented: no event, claim or attribution the transcript doesn't support | by eye | G1 to G3 catch invented names, numbers and dates. Invented meaning can only be read |

### Names and Gujarati or Sanskrit terms

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| T1 | Names, terms and honorifics (Swami, Bapa, Maharaj) are copied verbatim: same spelling, same case | check | Every word that isn't a dictionary word must appear in the transcript, case-sensitive, a plural or possessive ending aside. Common inflections and British spellings of dictionary words count as dictionary words |
| T2 | No translation and no gloss: never "bhakti (devotion)", never "seva, or service" | check, plus by eye | Parentheses are already banned by F6. An English rewording without brackets ("seva, meaning service") is read by eye |
| T3 | No Gujarati or Devanagari script is added | check | No character in U+0A80 to U+0AFF or U+0900 to U+097F, unless that exact string is in the transcript |
| T4 | If the transcript spells one term two ways, use the more frequent spelling | by eye | Spotting variants needs the phonetic key; T1 already ensures that whichever spelling is used is in the transcript |

The correction table and the review loop
([review-and-learn](../../docs/superpowers/specs/2026-10-28-review-and-learn.md)) run before the
summary. The notes model never corrects a spelling; it copies.

### Never allowed

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| N1 | No copying from the prompt or the samples (the `gemma3:1b` failure) | check | No run of 8 words shared with this spec's text or any sample, unless the same run is also in the transcript. Compare lower-cased, punctuation stripped |
| N2 | No long verbatim quotes from the transcript | check | No run of 13 or more words shared with the transcript, compared the same way |
| N3 | No judgement of the model's own: "a productive meeting", "an inspiring talk", "good progress" | check, plus by eye | A fixed list of evaluative words (`productive`, `fruitful`, `successful`, `inspiring`, `insightful`, `engaging`, `valuable`, `great`, `excellent`, `wonderful`, `powerful`, `moving`) is rejected unless the word is in the transcript. Other judgements are read by eye |
| N4 | No guessing who spoke: never put a name to "Speaker 2" or "Them", never state how many people were there | check, plus by eye | Reject `\d+ (people\|participants\|attendees\|members)`, the same with number words, and `attended by`. Whether a named person is attached to the right speaker is read by eye |

## 3. Meeting

Headings, in order:

```
## Summary
## Key Points
## Decisions
## Action Items
## Open Questions
```

Decisions, Action Items and Open Questions may be `None recorded.`

### What goes where

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| M1 | **Summary:** 2 to 4 sentences on what the meeting was about and how it ended | by eye | Length is L1 |
| M2 | **Key Points:** the main things discussed: information, arguments, status, proposals | by eye | — |
| M3 | **Decision:** a choice the meeting settled. Either the group agreed, or the person who owns the choice said so ("we'll go with X", "I've decided"). A proposal nobody accepted is a Key Point, or an Open Question if it was left hanging | by eye | Score: agreement with AMI DECISIONS on held-out AMI |
| M4 | **Open Question:** something raised and left unsettled, or a follow-up nobody owns yet | by eye | Score: agreement with AMI PROBLEMS/ISSUES |
| M5 | Nothing appears in two sections | check | For every pair of bullets in different sections, the overlap of non-stop-word word sets (Jaccard) must be below 0.6. A Key Point that says "decided" or "agreed" also fails: it is a decision in the wrong section. A Key Point that rewords a decision ("considered rubber" beside "made of rubber") gets past both, so it is also read by eye |

### Action items

Shape:

```
- [ ] <task> — <owner>
- [ ] <task> — <owner> — due <as said>
```

```
- [ ] Send the draft to legal — Priya — due Friday
- [ ] Book the hall for the shibir — owner not stated
- [ ] Fix the export bug — Speaker 2
```

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| A1 | An action item is something a person committed to do after the meeting | by eye | Score: agreement with AMI ACTIONS, or with the 12B where there's no human reference |
| A2 | Every item matches the shape | check | `^- \[ \] (.+?) — (.+?)(?: — due (.+))?$`, with ` — ` being space, em dash, space |
| A3 | The task starts with a verb | by eye | Needs a part-of-speech tagger, which the standard library doesn't have |
| A4 | The owner is always present: a name or speaker label exactly as in the transcript, two of them joined by ` and ` when the task is shared ("Industrial Designer and User Interface Designer"), or `owner not stated` | check | Group 2 equals `owner not stated`, or splits on ` and ` into one or two parts that each appear in the transcript |
| A5 | The due date appears only when one was said, copied as said | check | Group 3, if present, appears in the transcript |

## 4. Satsang talk

Headings, in order:

```
## Summary
## Key Points
## Stories
## References
## Practices
```

Stories, References and Practices may be `None recorded.` No Decisions, no
Action Items, no Open Questions.

| ID | Rule | Kind | How it's tested |
|---|---|---|---|
| S1 | **Summary:** 2 to 4 sentences: the speaker, if the transcript names them, and the theme | by eye | Length is L1; the speaker's name is checked by G1 |
| S2 | **Key Points:** the teachings, one per bullet, as the speaker put them, with no interpretation added | by eye | N3 catches added praise |
| S3 | **Stories:** one bullet per story or prasang told: who, what happened, and the point the speaker drew from it | by eye | — |
| S4 | **References:** scriptures, kirtans or shlokas cited, named as the speaker cited them ("Vachanamrut Gadhada I-1") | check | Every name and number in a References bullet must pass G1, G2 and T1. A bullet with nothing to check fails |
| S5 | **Practices:** only what the speaker explicitly asked listeners to do. Not the model's advice | by eye | — |

## 5. Samples

**Six meeting samples from AMI's human summaries. No satsang samples.**

- **Choosing them.** Six meetings from AMI's training split
  (`seen_type="training"` in `meetings.xml`), chosen by
  `tools/model-lab/ami_samples.py`: two from each scenario series, all four
  meeting phases covered. A meeting is chosen only if AMI's own Decisions,
  Action Items and Open Questions already pass every check, so AMI's human
  text is never edited. Then it prefers owners AMI names, and short abstracts:
  **ES2016a, ES2007c, IS1006b, IS1007d, TS3005a, TS3008a.** The split's
  development meetings and the unmarked test meetings (ES2004, ES2014,
  IS1009, TS3003, TS3007) are never used as samples.
- **Converting them.** The script maps AMI's headings mechanically:
  ABSTRACT → Summary, DECISIONS → Decisions, ACTIONS → Action Items,
  PROBLEMS/ISSUES → Open Questions. "The <role> will <task>." becomes
  `- [ ] <Task> — <Role>`; "The <role> and the <role> will…" becomes
  `— <Role> and <Role>`. AMI's `*NA*` becomes `None recorded.`, and a
  bracketed aside is cut. In the transcript written beside each sample,
  speakers are labelled by role (Project Manager, Industrial Designer, User
  Interface Designer, Marketing Expert) so role owners pass A4, and AMI's
  letter-by-letter acronyms (`L_C_D_`) are joined (`LCD`).
- **Finishing them with the teacher.** `tools/model-lab/draft_samples.py`
  has `gemma4:12b-mlx` do the two parts AMI lacks. No person and no frontier
  model writes sample text; Claude writes only the scripts and checks.
  - **Summary:** the teacher picks 2 to 4 of AMI's abstract sentences by
    number. Code joins them unchanged. Only sentences that pass the checks on
    their own are offered, and the pick must fit L1.
  - **Key Points:** the teacher writes them from the transcript, with this
    spec as its prompt and AMI's other sections shown so it doesn't repeat
    them.
  - **The checks decide.** Each draft goes through `tools/model-lab/checks.py`.
    Failures go back to the teacher for a revision, up to five tries, and the
    first draft that passes is kept. `drafts.json` logs every call.
  - **You** may read the finished samples by eye; nothing waits on it.
- **Files.** `tools/model-lab/samples/ami/<ID>.md` is the sample, and
  `<ID>.transcript.txt` is its transcript (gitignored; the script rebuilds
  it). The downloaded annotations are in `tools/model-lab/data/` (gitignored).
- **Satsang** is taught by §4's text alone. The risk: the teacher has never
  seen a good talk summary. If the teacher's satsang output reads badly by
  eye on your recordings at step 2, this is the first thing to revisit,
  with samples you write by hand.

Satsang has no human reference in the allowed data, so satsang quality is
judged by eye on your recordings (testing only) and by the checks.

**State, 2026-10-28:** all six samples pass every check. They are
waiting only on an optional read by eye.

### Found while making the samples (for step 2)

- **The MLX teacher can't constrain its output.** Ollama's MLX runner
  answers HTTP 501 "structured output is unavailable" to any `format`
  option. The method's third leg (§2 of the methodology) needs another
  route: the GGUF build of the same model, parsing with retries, or
  in-process MLX later.
- **The macOS word list is old.** It lacks words like "brainstormed" and
  "customization", so T1 sometimes fails good English. The teacher reworded
  around it here; before scoring other models, add a small, reviewed list of
  extra English words so T1 doesn't punish them for it.
- **The teacher can't add up.** Given word counts, it still picked sentences
  over the 80-word limit five times running. When it was shown the valid
  choices, it picked one at once.

## 6. Summary of kinds

| Kind | Rules |
|---|---|
| check | F1–F6, L1–L3, G1–G3, T1, T3, N1, N2, M5, A2, A4, A5, S4 |
| check, plus by eye | T2, N3, N4 |
| by eye | G4, T4, M1–M4, A1, A3, S1–S3, S5 |
| score (reported, no pass or fail) | M3, M4, A1 against AMI |
