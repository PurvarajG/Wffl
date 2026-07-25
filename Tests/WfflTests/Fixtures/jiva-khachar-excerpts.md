# Fixture excerpts — *Jiva Khachar was forgiven* import

Verbatim excerpts from the 2026-07-25 import used as regression evidence in
[PLAN-transcript-fidelity.md](../../../PLAN-transcript-fidelity.md) task 1.7.
Copy these strings into `TranscriptFidelityTests.swift` as constants.

RAW = post-ASR, post-`Vocabulary.correct`, post-`TranscriptCorrector`.
CLEAN = after `TranscriptCleanupService`.

---

## A. Cleanup fabrication (I3 — `.expansion`)

The cleaned line is ~40 words where the raw line was 15. Nothing in the raw
line supports the added material.

**RAW [29:04]**
```
So I don't want to take a whole diversion there because I know you're getting to a bigger point. But I think it's good to just stay here and reflect on what we are talking about.
```

**CLEAN [29:04]**
```
So I don't want to take a whole diversion there because I know you're getting to a bigger point. But I think it's I like this topic a lot too. And so I'm not upset you're taking me there. I'm just thinking that it will go for a while 'cause I have a lot of thoughts on this. I thought a lot about this.
```

**Test edit** — `old` is the raw tail, `new` is the cleaned tail:
```
old: "But I think it's good to just stay here and reflect on what we are talking about."
new: "But I think it's I like this topic a lot too. And so I'm not upset you're taking me there. I'm just thinking that it will go for a while 'cause I have a lot of thoughts on this. I thought a lot about this."
```
Expected: `.expansion` (14 content words → 33).

---

## B. Cleanup duplication (I2 — `.duplicate`)

The 24:59 span is re-emitted inside 25:19. **It is not in RAW 25:19** — cleanup
generated it, and inserted `Pujya Gunkirtan Swami` at the splice point.

**RAW [24:59]**
```
So I yeah, I and I think that Jiva Kachar, I I think that because he was that close to Maharaj, hundred percent he's an Akshar-devotee right now, right? So I want to be Jiva Kachar. Yeah,. Right. You know I want to be in Akshradan now. And the reason we know that is because.
```

**RAW [25:19]** — ends here, no duplicate:
```
you know the last pressing of jivakacher's life despite all of this i mean he man jiva kaccher he was taken to the limits of uh of what can happen and you know i think there's also context to that you know we look at some of the pressings like when he hired the assassin to wait for Maharaj in that in the outhouse. You know,
```

**CLEAN [25:19]** — the appended span is the defect:
```
you know the last pressing of jivakacher's life despite all of this i mean he man jiva kaccher he was taken to the limits of of what can happen and you know i think there's also context to that you know we look at some of the pressings like when he hired the assassin to wait for Maharaj in that in the outhouse. You know, Pujya Gunkirtan Swami because he was that close to Maharaj hundred percent he's an Akshadan right now right So I want to be Jiva Kachar Yeah Right you know i want to be in Akshardham now And the reason we know that is because
```

**Test setup** — build `transcriptNGrams` from a lines array containing the
24:59 text, then guard this edit:
```
old: "You know,"
new: "You know, Pujya Gunkirtan Swami because he was that close to Maharaj hundred percent he's an Akshadan right now right So I want to be Jiva Kachar Yeah Right you know i want to be in Akshardham now And the reason we know that is because"
```
Expected: `.expansion` fires first on ordering; assert `.duplicate` separately
with an `old` of comparable length so the duplicate rule is the one under test.

---

## C. Unsupported glossary name (I1 — `.invention`)

`Grod` is `krodh` (anger). It is not a person. This is the clearest instance of
the exemplar-attractor failure.

**RAW [43:11]**
```
And he is beyond reason in anger, right? You know we say like Grod is a sample of Mo, right? So he gets so upset and he's telling Ram.
```

**CLEAN [43:11]**
```
And he is beyond reason in anger, right? You know we say like Gunkirtan Swami is a sample of Mo, right? So he gets so upset and he's telling Ram.
```

**Test edit**
```
old: "Grod is a sample of Mo"
new: "Gunkirtan Swami is a sample of Mo"
```
Expected: `.invention` — `gunkirtan` is a known spelling but
`phoneticKey("Gunkirtan") = gnkrtn` vs `phoneticKey("Grod") = grd` is far
outside threshold.

---

## D. Legitimate collapse that must be ACCEPTED

Both guards must accept this. It is the repair the whole vocabulary layer
exists to make, and the current `sanitize` rejects it on a short segment.

```
original: "gun curtain swami"
corrected: "Gunkirtan Swami"
```
`phoneticKey("gun curtain") = gnkrtn` == `phoneticKey("Gunkirtan")`.

Longer form, already covered by `TranscriptCorrectorTests.testSanitizeAcceptsMinorSpellingFix`:
```
original: "gun curtain swami was talking about kirtan today"
corrected: "Gunkirtan Swami was talking about kirtan today"
```

---

## E. Context echo (task 1.3 rule 3)

RAW itself contains duplicated spans that the disjoint `AudioChunker` cannot
produce — evidence of `TranscriptCorrector` echoing its 400-char context.

**RAW [16:56]** ends:
```
And one of those five is "rushirun". So the debt to the rushis and the Yagna is shastra – study of the scriptures.
```

**RAW [17:13]** — same clause appended to an unrelated sentence:
```
Right. So basically what it says is that all these people, these Rushis, they did the hard work of churning inside of themselves and sacrificing so many of these bodily and kind of worldly comforts to come up with knowledge, both of the world and above the world. And one of those five debts is "rushirun". So the debt to the rushis and the Yagna is shastra – study of the scriptures.
```

**Test setup**
```
context:  "And one of those five is \"rushirun\". So the debt to the rushis and the Yagna is shastra – study of the scriptures."
original: "Right. So basically what it says is that all these people, these Rushis, they did the hard work of churning inside of themselves."
raw:      original + " And one of those five debts is \"rushirun\". So the debt to the rushis and the Yagna is shastra."
```
Expected: `sanitize` returns nil — a 5-gram of the reply appears in `context`.

Further instances at RAW 14:28, 32:27, 33:27, 41:55, 42:11 if more cases are wanted.

---

## F. Phrase-substitution stutter (task 2.2)

Not a Phase 1 test, recorded here so the Phase 2 fixture is verbatim.

RAW rendered the guru's name as `Mansoy Maharaj` / `Manhai Maharaj` /
`Man Swami Maharaj`. CLEAN produced, in different places:
```
Mahant Swami Maharaj Maharaj Maharaj
Brahman Mahant Swami Maharaj Maharaj
```
And, where RAW was already correct (`Jiva Kachar`), CLEAN produced:
```
Jiva Jiva Kachar
Jiva Jiva Jiva Kachar
```

Expected after 2.2: no canonical token repeats immediately after its own
substitution.

---

## G. Entity spelling instability (task 2.4)

Same entity, one document:

- **Gadhada** — `Garda`, `Garada`, `Garida`, `Gadara`, `Gadira`, `Khatra`, `Garba`
- **Akshardham** — `Akshadan`, `Akshradan`, `Akshaydan`, `Akshay`, `Akshyamukta`, `Ashwadi`, `Akshar-devotee`
- **dradh nishchay** — `Dhruva Nishchay`, `Drodnishche`, `Dharad Nishchay` (all within four lines, at 22:05)
- **Prapti no vichar** — `Prajñācār`, `Prop Tinovichar`, `Prapti Novicha`, `pragat novicha`, `Praktinovichar`, `Prap T V chair`, and twice corrupted to `Pratyahar`
- **Jiva Khachar** — `Kachar`, `Katar`, `Kachha`, `Katcher`, `Kaccher`, `Jiuakatra`, `Giuka`, `Jiu Akshar`

---

## H. English-word mishears (task 2.3)

The fuzzy corrector structurally cannot catch these — they are valid English.

| Heard | Meant | Context |
|---|---|---|
| `Jesus` | `Jai Swaminarayan` | 30:39 "just say Jesus on that" |
| `Jesus` | `jivas` | 39:19 "for the sake of Kalyan and of Mumukshus and Jesus" |
| `Grod` | `krodh` | 43:11 |
| `Shushma` | `Shishupal` | 36:57 |
| `Khand` | `Kans` | 36:57 |
| `Bratham 70` | `Gadhada Pratham 70` | 40:06, also `Brethome`, `Fritham` |
| `suburb`-class already seeded | — | see `Vocabulary.seedMishears()` |
