"""The notes spec's "check" rules in code (tools/model-lab/notes-spec.md).

`run_checks(notes, transcript, shape, refs)` returns a list of (rule, message)
failures; an empty list means the notes pass. Rules marked "by eye" in the
spec are not here. Python standard library only, so the scoreboard and the
training filter can both import it.
"""
import itertools
import re
from pathlib import Path

SHAPES = {
    "meeting": ["Summary", "Key Points", "Decisions", "Action Items", "Open Questions"],
    "satsang": ["Summary", "Key Points", "Stories", "References", "Practices"],
}
MAY_BE_EMPTY = {
    "meeting": {"Decisions", "Action Items", "Open Questions"},
    "satsang": {"Stories", "References", "Practices"},
}
NONE = "None recorded."
NO_OWNER = "owner not stated"
ACTION_ITEM = re.compile(r"^- \[ \] (.+?) — (.+?)(?: — due (.+))?$")
SENTENCE_END = re.compile(r"[.!?](?=\s|$)")
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9'’_-]*")
EVALUATIVE = ["productive", "fruitful", "successful", "inspiring", "insightful", "engaging",
              "valuable", "great", "excellent", "wonderful", "powerful", "moving"]
STOP = set("a an the and or but of to in on at for with by from as is are was were be been "
           "will would should could can may might this that these those it its they them "
           "their there we our you your he she his her not no whether what how which who".split())
WEEKDAYS = "Monday Tuesday Wednesday Thursday Friday Saturday Sunday"
MONTHS = "January February March April May June July August September October November December"
DATE_LIKE = re.compile(r"\b(?:%s|%s)\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}/\d{1,2}\b|\b\d{1,2}:\d{2}\b"
                       % ("|".join(WEEKDAYS.split()), "|".join(MONTHS.split())))
RELATIVE = {"next", "last", "this", "on", "by", "coming", "before", "after", "until"}
SPEAKER_PREFIX = re.compile(r"^\[\d{1,2}:\d{2}(?::\d{2})?\] [^:]{1,40}: ")
ATTENDANCE = re.compile(r"\b(?:\d+|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|"
                        r"dozens?|hundreds?) (?:people|participants|attendees|members)\b|\battended by\b",
                        re.I)

_ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen " \
        "fifteen sixteen seventeen eighteen nineteen".split()
_TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()
_DICT = None


def dictionary():
    """/usr/share/dict/words plus extra-words.txt, a short reviewed list of
    current English the old macOS list lacks ("brainstormed", "customization")."""
    global _DICT
    if _DICT is None:
        extra = Path(__file__).resolve().parent / "extra-words.txt"
        lines = Path("/usr/share/dict/words").read_text().splitlines()
        lines += [l for l in extra.read_text().splitlines() if not l.startswith("#")]
        _DICT = {w.strip().lower() for w in lines if w.strip()}
    return _DICT


def is_dictionary_word(word):
    """In /usr/share/dict/words, allowing for common inflections the list leaves out."""
    words = dictionary()
    w = word.lower().replace("’", "'")
    if w.endswith("'s"):
        w = w[:-2]
    for part in w.split("-"):
        if not part or part.isdigit() or part in words:
            continue
        # British spellings: favour → favor, customise → customize.
        variants = {part, part.replace("our", "or"), part.replace("is", "iz")}
        stems = set()
        for v in variants:
            stems.add(v)
            for suf in ("ies", "ied", "ier", "iest", "es", "s", "ed", "d", "ing", "ly", "er", "ers", "est",
                        "ness", "ment", "ally"):
                if v.endswith(suf):
                    stem = v[:-len(suf)]
                    stems |= {stem, stem + "e", stem + "y"}
                    if len(stem) > 2 and stem[-1] == stem[-2]:  # recapped → recap
                        stems.add(stem[:-1])
        stems |= {s[:-len(z)] for s in list(stems) for z in ("ize", "iz") if s.endswith(z)}  # customize
        if not any(len(s) > 2 and s in words for s in stems):
            return False
    return True


def number_words(n):
    """English spellings of 0..999, with and without hyphens."""
    if n < 20:
        return {_ONES[n]}
    if n < 100:
        tens, ones = divmod(n, 10)
        return {_TENS[tens]} if ones == 0 else {f"{_TENS[tens]} {_ONES[ones]}", f"{_TENS[tens]}-{_ONES[ones]}"}
    hundreds, rest = divmod(n, 100)
    head = f"{_ONES[hundreds]} hundred"
    if rest == 0:
        return {head}
    return {f"{head} {r}" for r in number_words(rest)} | {f"{head} and {r}" for r in number_words(rest)}


def has(transcript, phrase, ignore_case=False, endings=False):
    """`phrase` is in `transcript` as whole words. With `endings`, a plural or
    possessive ending on either side doesn't count as a different spelling."""
    if endings:
        for suffix in ("'s", "’s", "es", "s"):
            if phrase.endswith(suffix) and len(phrase) > len(suffix) + 1:
                phrase = phrase[:-len(suffix)]
                break
    tail = r"(?:'s|’s|es|s)?" if endings else ""
    pattern = r"(?<![A-Za-z0-9])" + re.escape(phrase) + tail + r"(?![A-Za-z0-9])"
    return re.search(pattern, transcript, re.I if ignore_case else 0) is not None


def parse(notes):
    """[(heading, [body lines])] in order, plus any lines before the first heading."""
    sections, before = [], []
    for line in notes.splitlines():
        if line.startswith("## "):
            sections.append((line[3:].strip(), []))
        elif sections:
            if line.strip():
                sections[-1][1].append(line.rstrip())
        elif line.strip():
            before.append(line)
    return sections, before


def sentences(text):
    return [s for s in SENTENCE_END.split(text) if s.strip()]


def norm_words(text):
    return re.findall(r"[a-z0-9']+", text.lower().replace("’", "'"))


def ngrams(words, n):
    return {tuple(words[i:i + n]) for i in range(len(words) - n + 1)}


def spoken_word_count(transcript):
    return sum(len(SPEAKER_PREFIX.sub("", line).split()) for line in transcript.splitlines())


def key_point_band(word_count):
    if word_count < 4500:
        return 3, 6
    if word_count <= 13500:
        return 3, 10
    return 3, 14


def content_lines(sections):
    """(heading, text) for every Summary line and bullet, markers stripped."""
    out = []
    for heading, body in sections:
        for line in body:
            if line == NONE:
                continue
            text = re.sub(r"^- (?:\[ \] )?", "", line)
            out.append((heading, text))
    return out


def capitalised_runs(text):
    """Runs of capitalised words, minus a sentence-initial first word."""
    runs, current, start_of_sentence = [], [], True
    prev_end = 0
    for m in WORD.finditer(text):
        gap = text[prev_end:m.start()]
        if current and gap != " ":
            runs.append(current)
            current = []
        if re.search(r"[.!?]\s*$|—\s*$", gap) or prev_end == 0:
            start_of_sentence = True
        word = m.group()
        if word[0].isupper():
            if start_of_sentence and not current:
                current = [None]  # placeholder for the exempt first word
            else:
                current.append(word)
        elif current:
            runs.append(current)
            current = []
        start_of_sentence = False
        prev_end = m.end()
    if current:
        runs.append(current)
    return [" ".join(w for w in run if w) for run in runs if any(run)]


def check_line_grounding(text, transcript, exempt):
    """G1, G2 and T1 for one line of notes."""
    failures = []
    for run in capitalised_runs(text):
        words = run.split()
        if run in exempt or words == ["I"]:
            continue
        # A run can join a name to the sentence-initial word after the exempt one,
        # so a run passes if every maximal piece of it is in the transcript.
        if has(transcript, run, endings=True) or all(has(transcript, w, endings=True) for w in words):
            continue
        # In a hyphenated word only the capitalised parts can be a name: "TV-only"
        # checks "TV"; a lone capital letter ("T-shaped") is a shape, not a name.
        pieces = [p for w in words for p in w.split("-") if len(p) > 1 and p[0].isupper()]
        if any("-" in w for w in words) and all(has(transcript, p, endings=True) for p in pieces):
            continue
        failures.append(("G1", f"name not in transcript: {run!r}"))
    for m in re.finditer(r"\d+(?:[.,]\d+)*", text):
        number = m.group()
        if has(transcript, number):
            continue
        parts = [int(p) for p in re.split(r"[.,]", number) if p]
        if all(p < 1000 and any(has(transcript, w, ignore_case=True) for w in number_words(p))
               for p in parts):
            continue
        failures.append(("G2", f"number not in transcript: {number}"))
    for m in WORD.finditer(text):
        word = m.group().strip("'’-_")
        if not word or word.isdigit() or is_dictionary_word(word) or word in exempt:
            continue
        if not has(transcript, word, endings=True):
            failures.append(("T1", f"non-dictionary word not in transcript: {word!r}"))
    return failures


def run_checks(notes, transcript, shape="meeting", refs=()):
    failures = []
    sections, before = parse(notes)
    headings = [h for h, _ in sections]
    body = dict(sections)
    exempt = set(SHAPES[shape]) | {"None", NO_OWNER}

    # Format
    if headings != SHAPES[shape]:
        failures.append(("F1", f"headings {headings} != {SHAPES[shape]}"))
    for heading, lines in sections:
        if not lines:
            failures.append(("F2", f"{heading} is empty; write {NONE!r} or fill it"))
        elif NONE in lines and (lines != [NONE] or heading not in MAY_BE_EMPTY[shape]):
            failures.append(("F2", f"{heading}: {NONE!r} not allowed here or not alone"))
    first = next((l for l in notes.splitlines() if l.strip()), "")
    if before or first != "## Summary":
        failures.append(("F3", "text before the first heading, or it isn't ## Summary"))
    if any(l.startswith("-") for l in body.get("Summary", [])):
        failures.append(("F4", "Summary has bullets"))
    for heading, lines in sections:
        if heading == "Summary":
            continue
        for line in lines:
            if line == NONE:
                continue
            if heading == "Action Items":
                if not line.startswith("- [ ] "):
                    failures.append(("F5", f"Action Items line isn't '- [ ] ': {line[:50]}"))
            elif not line.startswith("- ") or line.startswith("- [ ]"):
                failures.append(("F5", f"{heading} line isn't a '- ' bullet: {line[:50]}"))
    for line in notes.splitlines():
        bad = [p for p in ("**", "__", "|", "`", "(", ")") if p in line]
        if re.match(r"^\s+-", line):
            bad.append("sub-bullet")
        if line.startswith("#") and not line.startswith("## "):
            bad.append("heading level")
        if re.search("[\U0001F000-\U0001FAFF☀-➿]", line):
            bad.append("emoji")
        if bad:
            failures.append(("F6", f"{bad}: {line[:50]}"))

    # Length
    summary = " ".join(body.get("Summary", []))
    n_sent, n_words = len(sentences(summary)), len(summary.split())
    if not 2 <= n_sent <= 4 or n_words > 80:
        failures.append(("L1", f"Summary is {n_sent} sentences, {n_words} words; want 2–4, ≤ 80"))
    for heading, lines in sections:
        for line in lines:
            if line.startswith("- "):
                text = re.sub(r"^- (?:\[ \] )?", "", line)
                if len(sentences(text)) > 1 or len(text.split()) > 30:
                    failures.append(("L2", f"{heading} bullet is {len(sentences(text))} sentences, "
                                           f"{len(text.split())} words: {text[:50]}"))
    lo, hi = key_point_band(spoken_word_count(transcript))
    n_key = len([l for l in body.get("Key Points", []) if l.startswith("- ")])
    if not lo <= n_key <= hi:
        failures.append(("L3", f"{n_key} Key Points; want {lo}–{hi}"))

    # Grounding and terms
    for heading, text in content_lines(sections):
        if heading == "Action Items":
            m = ACTION_ITEM.match("- [ ] " + text)
            text = m.group(1) if m else text  # owner and due are A4 and A5
        failures += check_line_grounding(text, transcript, exempt)
        for m in DATE_LIKE.finditer(text):
            before_word = re.findall(r"([A-Za-z]+)\s+$", text[:m.start()])
            phrase = m.group()
            if before_word and before_word[0].lower() in RELATIVE:
                phrase = f"{before_word[0]} {phrase}"
            if not has(transcript, phrase, ignore_case=True):
                failures.append(("G3", f"date or time not as said: {phrase!r}"))
    for ch in set(re.findall("[ऀ-ॿ઀-૿]+", notes)):
        if ch not in transcript:
            failures.append(("T3", f"Gujarati or Devanagari script added: {ch!r}"))

    # Never allowed
    # Runs are taken within one line: words that only meet across two bullets weren't copied.
    note_lines = [norm_words(t) for _, t in content_lines(sections)]
    transcript_words = norm_words(SPEAKER_PREFIX.sub("", transcript))
    t8, t13 = ngrams(transcript_words, 8), ngrams(transcript_words, 13)
    ref8 = set().union(*(ngrams(norm_words(r), 8) for r in refs)) if refs else set()
    copied = set().union(*(ngrams(w, 8) for w in note_lines)) & ref8 - t8
    if copied:
        failures.append(("N1", f"copied from the prompt or samples: {' '.join(sorted(copied)[0])!r}"))
    quoted = set().union(*(ngrams(w, 13) for w in note_lines)) & t13
    if quoted:
        failures.append(("N2", f"13+ words verbatim from the transcript: {' '.join(sorted(quoted)[0])!r}"))
    for word in EVALUATIVE:
        if has(notes, word, ignore_case=True) and not has(transcript, word, ignore_case=True):
            failures.append(("N3", f"evaluative word not in transcript: {word!r}"))
    if ATTENDANCE.search(notes):
        failures.append(("N4", f"attendance stated: {ATTENDANCE.search(notes).group()!r}"))

    # Shape rules
    if shape == "meeting":
        bullets = [(h, set(norm_words(t)) - STOP) for h, t in content_lines(sections) if h != "Summary"]
        for (h1, a), (h2, b) in itertools.combinations(bullets, 2):
            if h1 != h2 and a and b and len(a & b) / len(a | b) >= 0.6:
                failures.append(("M5", f"same item in {h1} and {h2}: {sorted(a & b)}"))
        # A Key Point that reports a settled choice is a decision in the wrong section.
        for line in body.get("Key Points", []):
            if re.search(r"\b(?:decided|agreed)\b", line, re.I):
                failures.append(("M5", f"Key Point reports a decision: {line[2:60]}"))
        for line in body.get("Action Items", []):
            if line == NONE:
                continue
            m = ACTION_ITEM.match(line)
            if not m:
                failures.append(("A2", f"action item shape: {line[:60]}"))
                continue
            owner, due = m.group(2), m.group(3)
            parts = owner.split(" and ")
            if owner != NO_OWNER and (len(parts) > 2 or not all(has(transcript, p, endings=True) for p in parts)):
                failures.append(("A4", f"owner not in transcript: {owner!r}"))
            if due and not has(transcript, due, ignore_case=True):
                failures.append(("A5", f"due not as said: {due!r}"))
    if shape == "satsang":
        for line in body.get("References", []):
            if line == NONE:
                continue
            text = line[2:]
            if not capitalised_runs(text) and not re.search(r"\d", text):
                failures.append(("S4", f"reference with nothing to check: {text[:50]}"))
    return failures
