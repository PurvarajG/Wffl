"""Pick six AMI training meetings and convert their human summaries into the
notes spec's meeting shape (tools/model-lab/notes-spec.md, section 5).

The conversion is mechanical: headings are mapped, AMI's "The <role> will <task>"
action sentences become "- [ ] <task> — <Role>", and empty (*NA*) sections
become "None recorded.". Nothing is reworded or invented. What AMI doesn't have
(Key Points, owners it doesn't name) is left as a TODO line, and the Summary is
AMI's full abstract; draft_samples.py fills and cuts those with the teacher.
Meetings whose own sections already fail a check are passed over, so AMI's
human text never needs editing. Each sample gets a readable transcript beside
it, labelled by role.

Run from the repo root:  python3 -I tools/model-lab/ami_samples.py
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LAB = Path(__file__).resolve().parent
sys.path.insert(0, str(LAB))  # -I leaves the script's folder off the path
from checks import key_point_band, run_checks, spoken_word_count  # noqa: E402

AMI = LAB / "data" / "ami-manual-1.6.2" / "extracted"
OUT = LAB / "samples" / "ami"

ROLE_NAMES = {"PM": "Project Manager", "ID": "Industrial Designer",
              "UI": "User Interface Designer", "ME": "Marketing Expert"}
# How AMI's summary writers name each role, mapped to the transcript's label.
ROLE_ALIASES = {"project manager": "Project Manager",
                "industrial designer": "Industrial Designer",
                "user interface designer": "User Interface Designer",
                "interface specialist": "User Interface Designer",
                "marketing expert": "Marketing Expert",
                "marketing": "Marketing Expert"}
# One owner, or two joined by "and the" (rule A4).
_ROLE = "|".join(sorted(ROLE_ALIASES, key=len, reverse=True))
ACTION = re.compile(r"^The (%s)(?: and the (%s))? (?:will|is to|is going to|needs to|should) (.+)$"
                    % (_ROLE, _ROLE), re.I)

# Two meetings from each scenario series, so every meeting phase (a kick-off,
# b functional, c conceptual, d detailed design) appears at least once. The
# last slot takes any phase: only TS3005a and TS3008a pass every check in AMI's text.
PLAN = [("ES", "a"), ("ES", "c"), ("IS", "b"), ("IS", "d"), ("TS", "a"), ("TS", "abcd")]

TODO_KEY_POINTS = "- TODO: write {lo}–{hi} Key Points by hand."
TODO_OWNER = "TODO owner"


def sentences(root, tag):
    out = []
    for section in root.iter(tag):
        for s in section.iter("sentence"):
            # Cutting a bracketed aside is a deletion, and F6 bans brackets.
            text = " ".join(re.sub(r"\s*\([^)]*\)", "", s.text or "").split())
            if text and text.strip("*. ") != "NA":  # AMI writes *NA*, NA. or *NA*.
                out.append(text)
    return out


def meetings_where(keep):
    """{meeting: {agent: role name}} for the meetings `keep(element)` accepts."""
    meetings = {}
    for m in ET.parse(AMI / "corpusResources" / "meetings.xml").getroot().iter("meeting"):
        if keep(m):
            roles = {s.get("nxt_agent"): ROLE_NAMES[s.get("role")] for s in m.iter("speaker")}
            meetings[m.get("observation")] = roles
    return meetings


def training_meetings():
    return meetings_where(lambda m: m.get("seen_type") == "training")


# AMI's scenario test set: these series carry no seen_type in meetings.xml.
TEST_SERIES = ("ES2004", "ES2014", "IS1009", "TS3003", "TS3007")


def test_meetings():
    return meetings_where(lambda m: m.get("observation")[:-1] in TEST_SERIES)


def transcript(meeting, roles):
    """One line per speaker turn, from AMI's segments, in start-time order."""
    href = re.compile(r"#id\(([^)]+)\)(?:\.\.id\(([^)]+)\))?")
    segments = []
    for f in sorted((AMI / "segments").glob(f"{meeting}.*.segments.xml")):
        agent = f.name.split(".")[1]
        # Index every element, not just <w>: a segment's range can start or end
        # on a vocalsound, disfmarker or gap.
        words = list(ET.parse(AMI / "words" / f"{meeting}.{agent}.words.xml").getroot())
        index = {w.get("{http://nite.sourceforge.net/}id"): i for i, w in enumerate(words)}
        for seg in ET.parse(f).getroot().iter("segment"):
            toks = []
            for child in seg:
                m = href.search(child.get("href", ""))
                if not m or m.group(1) not in index:
                    continue
                first = index[m.group(1)]
                last = index.get(m.group(2) or m.group(1), first)
                toks += [(w.text, w.get("punc") == "true") for w in words[first:last + 1]
                         if w.tag == "w" and w.text]
            if toks:
                segments.append((float(seg.get("transcriber_start")), agent, toks))
    segments.sort(key=lambda x: x[0])
    turns = []
    for start, agent, toks in segments:
        if turns and turns[-1][1] == agent:
            turns[-1][2].extend(toks)
        else:
            turns.append((start, agent, list(toks)))
    lines = []
    for start, agent, toks in turns:
        body = ""
        for text, punc in toks:
            body += text if punc or not body else " " + text
        # AMI spells acronyms letter by letter (L_C_D_); Wffl transcripts don't.
        body = re.sub(r"\b(?:[A-Za-z]_)+", lambda m: m.group().replace("_", ""), body)
        mm, ss = divmod(int(start), 60)
        lines.append(f"[{mm:02d}:{ss:02d}] {roles[agent]}: {body}")
    return "\n".join(lines) + "\n"


def convert(summary_root, word_count):
    abstract = sentences(summary_root, "abstract")
    decisions = sentences(summary_root, "decisions")
    problems = sentences(summary_root, "problems")
    actions = []
    for s in sentences(summary_root, "actions"):
        m = ACTION.match(s.rstrip("."))
        if m:
            task = m.group(3)
            owner = " and ".join(ROLE_ALIASES[r.lower()] for r in m.group(1, 2) if r)
            actions.append(f"- [ ] {task[0].upper()}{task[1:]} — {owner}")
        else:
            actions.append(f"- [ ] {s.rstrip('.')} — {TODO_OWNER}")
    lo, hi = key_point_band(word_count)

    def bullets(items):
        return "\n".join(f"- {i}" for i in items) if items else "None recorded."

    return "\n\n".join([
        "## Summary\n" + " ".join(abstract),
        "## Key Points\n" + TODO_KEY_POINTS.format(lo=lo, hi=hi),
        "## Decisions\n" + bullets(decisions),
        "## Action Items\n" + ("\n".join(actions) if actions else "None recorded."),
        "## Open Questions\n" + bullets(problems),
    ]) + "\n"


def human_failures(notes, text):
    """Check failures in AMI's own sections (Decisions, Action Items, Open
    Questions). The Summary and Key Points are swapped for neutral stand-ins,
    since those two are drafted later and checked then."""
    sections = notes.split("\n\n")
    sections[0] = "## Summary\nStand in one. Stand in two."
    sections[1] = "## Key Points\n- Stand in one.\n- Stand in two.\n- Stand in three."
    return [f for f in run_checks("\n\n".join(sections) + "\n", text) if f[0] not in ("L1", "L3")]


def main():
    if not AMI.is_dir():
        sys.exit(f"AMI annotations not found at {AMI}")
    meetings = training_meetings()
    candidates = {}
    for meeting in sorted(meetings):
        path = AMI / "abstractive" / f"{meeting}.abssumm.xml"
        if not path.exists():
            continue
        root = ET.parse(path).getroot()
        if not all(sentences(root, t) for t in ("abstract", "actions", "decisions", "problems")):
            continue
        text = transcript(meeting, meetings[meeting])
        notes = convert(root, spoken_word_count(text))
        candidates[meeting] = {"root": root, "text": text, "notes": notes,
                               "failures": human_failures(notes, text)}

    def score(m):
        """Lower is better: AMI's sections pass, fewer TODO owners, shorter abstract."""
        c = candidates[m]
        abstract = " ".join(sentences(c["root"], "abstract"))
        return (len(c["failures"]), c["notes"].count(TODO_OWNER), len(abstract.split()), m)

    chosen, used_series = [], set()
    for series, phase in PLAN:
        pool = sorted((m for m in candidates
                       if m.startswith(series) and m[-1] in phase and m[:-1] not in used_series),
                      key=score)
        chosen.append(pool[0])
        used_series.add(pool[0][:-1])

    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for meeting in chosen:
        c = candidates[meeting]
        (OUT / f"{meeting}.md").write_text(c["notes"])
        (OUT / f"{meeting}.transcript.txt").write_text(c["text"])
        manifest.append({
            "meeting": meeting,
            "transcript_words": spoken_word_count(c["text"]),
            "abstract_sentences": sentences(c["root"], "abstract"),
            "todo_owners": c["notes"].count(TODO_OWNER),
            "human_section_failures": [f"{r} {m}" for r, m in c["failures"]],
        })
    (OUT / "manifest.json").write_text(json.dumps({
        "source": "AMI Meeting Corpus manual annotations 1.6.2, abstractive summaries, training split",
        "licence": "CC BY 4.0, credit the AMI Consortium",
        "samples": manifest,
    }, indent=2, ensure_ascii=False) + "\n")
    for m in manifest:
        print(f"{m['meeting']}: {m['transcript_words']} words, {m['todo_owners']} TODO owners, "
              f"{len(m['human_section_failures'])} failures in AMI's sections")


if __name__ == "__main__":
    main()
