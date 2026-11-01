"""Answer keys for the rubric eval (rubric-spec.md §3), built from AMI only.

One key per meeting: every sentence AMI's summary writers put under DECISIONS,
ACTIONS and PROBLEMS, each with the dialogue acts its summlinks point at, plus
the meeting's topic segments. Nothing here is written or edited by a person or
a model. Keys are rebuilt into the gitignored out/keys/.

    python3 -I tools/model-lab/answer_keys.py [MEETING ...]
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from functools import lru_cache
from pathlib import Path

LAB = Path(__file__).resolve().parent
sys.path.insert(0, str(LAB))  # -I leaves the script's folder off the path
from ami_samples import ACTION, AMI, ROLE_ALIASES, SPLITS, training_meetings  # noqa: E402

NITE = "{http://nite.sourceforge.net/}"
HREF = re.compile(r"#id\(([^)]+)\)(?:\.\.id\(([^)]+)\))?")
OUT = LAB / "out" / "keys"
TYPES = {"decisions": "decision", "actions": "action", "problems": "problem"}
# default-topics.xml files opening, closing, agenda/equipment issues and chitchat
# under "Functional" (top.1); they say nothing a note should cover.
FUNCTIONAL = {"top.1", "top.11", "top.12", "top.13", "top.14"}
MIN_TOPIC_S = 60


@lru_cache(maxsize=8)
def words_of(meeting, agent):
    words = list(ET.parse(AMI / "words" / f"{meeting}.{agent}.words.xml").getroot())
    return words, {w.get(NITE + "id"): i for i, w in enumerate(words)}


def span(meeting, href):
    """The word-file elements an href range covers."""
    agent = href.split(".")[1]
    words, index = words_of(meeting, agent)
    m = HREF.search(href or "")
    if not m or m.group(1) not in index:
        return []
    first = index[m.group(1)]
    return words[first:index.get(m.group(2) or m.group(1), first) + 1]


def times(elements):
    starts = [float(e.get("starttime")) for e in elements if e.get("starttime") is not None]
    ends = [float(e.get("endtime")) for e in elements if e.get("endtime") is not None]
    return (min(starts), max(ends)) if starts and ends else (None, None)


def join(elements):
    """Words as the transcript writes them (punctuation attached, L_C_D_ → LCD)."""
    body = ""
    for w in elements:
        if w.tag == "w" and w.text:
            body += w.text if w.get("punc") == "true" or not body else " " + w.text
    return re.sub(r"\b(?:[A-Za-z]_)+", lambda m: m.group().replace("_", ""), body)


def dialogue_acts(meeting, roles):
    """Every dialogue act with speaker, start, end and text, in time order."""
    acts = []
    for f in sorted((AMI / "dialogueActs").glob(f"{meeting}.*.dialog-act.xml")):
        agent = f.name.split(".")[1]
        for d in ET.parse(f).getroot().iter("dact"):
            els = [w for c in d.findall(NITE + "child") for w in span(meeting, c.get("href"))]
            start, end = times(els)
            text = join(els)
            if start is not None and text:
                acts.append({"id": d.get(NITE + "id"), "speaker": roles[agent],
                             "start": start, "end": end, "text": text})
    acts.sort(key=lambda a: (a["start"], a["id"]))
    return acts


def summlinks(meeting):
    """{abstractive sentence id: [dialogue act ids]}."""
    path = AMI / "extractive" / f"{meeting}.summlink.xml"
    links = {}
    if path.exists():
        for link in ET.parse(path).getroot().iter("summlink"):
            ends = {p.get("role"): HREF.search(p.get("href")).group(1) for p in link.findall(NITE + "pointer")}
            links.setdefault(ends["abstractive"], []).append(ends["extractive"])
    return links


def sentence_text(s):
    """As ami_samples.sentences(): bracketed asides cut, *NA* dropped."""
    text = " ".join(re.sub(r"\s*\([^)]*\)", "", s.text or "").split())
    return "" if not text or text.strip("*. ") == "NA" else text


def items(meeting, root, acts):
    by_id = {a["id"]: a for a in acts}
    links = summlinks(meeting)
    out = []
    for tag, kind in TYPES.items():
        for section in root.iter(tag):
            for s in section.iter("sentence"):
                text = sentence_text(s)
                if not text:
                    continue
                m = ACTION.match(text.rstrip(".")) if kind == "action" else None
                linked = [by_id[a] for a in links.get(s.get(NITE + "id"), []) if a in by_id]
                out.append({"id": s.get(NITE + "id"), "type": kind, "text": text,
                            # An action queries its task only, not the owner (§4).
                            "task": m.group(3) if m else text,
                            "owners": [ROLE_ALIASES[r.lower()] for r in m.group(1, 2) if r] if m else [],
                            "acts": [{k: a[k] for k in ("id", "speaker", "start", "end")} for a in linked]})
    return out


def topics(meeting):
    path = AMI / "topics" / f"{meeting}.topic.xml"
    out = []
    if not path.exists():
        return out
    for t in ET.parse(path).getroot().iter("topic"):
        pointer = t.find(NITE + "pointer")
        kind = HREF.search(pointer.get("href")).group(1) if pointer is not None else "top.4"
        start, end = times([w for c in t.findall(NITE + "child") for w in span(meeting, c.get("href"))])
        if kind in FUNCTIONAL or start is None or end - start < MIN_TOPIC_S:
            continue
        out.append({"id": t.get(NITE + "id"), "type": kind,
                    "description": t.get("other_description"), "start": start, "end": end})
    return out


def build(meeting, roles):
    root = ET.parse(AMI / "abstractive" / f"{meeting}.abssumm.xml").getroot()
    acts = dialogue_acts(meeting, roles)
    return {"meeting": meeting, "source": "AMI manual annotations 1.6.2, CC BY 4.0",
            "items": items(meeting, root, acts), "topics": topics(meeting)}, acts


def load(meeting, roles):
    """(key, dialogue acts), cached in out/keys/."""
    path = OUT / f"{meeting}.json"
    if path.exists():
        data = json.loads(path.read_text())
        return data["key"], data["acts"]
    key, acts = build(meeting, roles)
    OUT.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"key": key, "acts": acts}, ensure_ascii=False) + "\n")
    return key, acts


@lru_cache(maxsize=1)
def all_meetings():
    """Test, Reserve and Dev, plus training (the samples' meetings, mutation sources)."""
    out = {m: roles for split in SPLITS.values() for m, roles in split().items()}
    return {**training_meetings(), **out}


def main():
    meetings = all_meetings()
    evaluated = {m for split in SPLITS.values() for m in split()}
    for meeting in sys.argv[1:] or sorted(evaluated):
        key, acts = load(meeting, meetings[meeting])
        keyless = sum(not i["acts"] for i in key["items"])
        print(f"{meeting}: {len(acts)} acts, {len(key['items'])} items ({keyless} without summlinks), "
              f"{len(key['topics'])} topics")


if __name__ == "__main__":
    main()
