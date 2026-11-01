"""The rubric eval (rubric-spec.md): scores notes against answer keys built
from AMI, with no model grading another.

`score(notes, meeting, cfg)` returns one meeting's counts for every criterion,
R1 to R12. Counts, not rates, so the report can pool them within each
bootstrap resample (§7). The anchored criteria (R5 to R11) depend on a config:

- mode "global" is §4 as written: a bullet's top 5 units anywhere in the
  meeting, kept when they clear τ_support and sit within w seconds of an act
  the key item links to.
- mode "local" scores the bullet over only the units within w of the item's
  linked acts. The rubric session's Dev prototype found the global top 5 often
  lands elsewhere, since words like "remote" and "button" recur all meeting.

Until the thresholds are calibrated on your labels (§5), every anchored number
is provisional, and `report` shows how the ranking moves across a sweep.

    python3 -I tools/model-lab/rubric.py report       scores, intervals, the §8 table
    python3 -I tools/model-lab/rubric.py proxy        label-free threshold check on Dev
    python3 -I tools/model-lab/rubric.py label        your labels, in the terminal (§5)
    python3 -I tools/model-lab/rubric.py calibrate    thresholds from your labels, frozen
"""
import argparse
import hashlib
import json
import random
import re
import statistics
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from functools import lru_cache
from pathlib import Path

LAB = Path(__file__).resolve().parent
sys.path.insert(0, str(LAB))  # -I leaves the script's folder off the path
import answer_keys  # noqa: E402
from ami_samples import AMI, SPLITS, convert, sentences as ami_sentences, transcript  # noqa: E402
from anchor import Index, dice, terms  # noqa: E402
from checks import ACTION_ITEM, NONE, norm_words, parse, run_checks, sentences, spoken_word_count  # noqa: E402

SPEC = LAB / "notes-spec.md"
SAMPLES = LAB / "samples" / "ami"
NOTES = LAB / "out" / "scoreboard"
OUT = LAB / "out" / "rubric"
THRESHOLDS = LAB / "rubric-thresholds.json"

# §5's untuned starting guess, used until rubric-thresholds.json exists.
START = {"mode": "global", "window": 1, "tau_support": 0.3, "tau_match": 0.3, "w": 20, "word_score": True}
TOP_K = 5
W_ALL = (0, 5, 10, 20, 30, 60)  # every w the sweep and calibration try
W_MAX = max(W_ALL)
SECTION_OF = {"decision": "Decisions", "action": "Action Items", "problem": "Open Questions"}
BULLET_SECTIONS = ("Key Points", "Decisions", "Action Items", "Open Questions")
GROUPS = {"R1": ("F1", "F2", "F3", "F4", "F5", "F6", "A2"), "R2": ("T3", "N1", "N2", "N4"),
          "R4": ("G1", "G2", "G3", "T1", "A4", "A5"), "R12": ("L1", "L2", "L3"),
          # R2 without N1 (copied from the prompt's spec or samples): a trained
          # student runs on a one-line prompt with no samples to copy. Reported, not gated.
          "R2x": ("T3", "N2", "N4")}
THINK = re.compile(r"^\s*<(?:\|)?think(?:ing)?(?:\|)?>", re.I)
THINK_BLOCK = re.compile(r"^\s*<(?:\|)?think(?:ing)?(?:\|)?>.*?</(?:\|)?think(?:ing)?(?:\|)?>\s*", re.I | re.S)


# ---------- meetings ----------

class Meeting:
    """Everything the rubric needs about one AMI meeting, built once."""

    def __init__(self, meeting, roles):
        self.id = meeting
        self.key, self.acts = answer_keys.load(meeting, roles)
        self.transcript = transcript(meeting, roles)
        self.root = ET.parse(AMI / "abstractive" / f"{meeting}.abssumm.xml").getroot()
        self.words = spoken_word_count(self.transcript)
        self._index, self._distance, self._topics = {}, {}, {}

    def index(self, window):
        if window not in self._index:
            self._index[window] = Index(self.acts, window)
        return self._index[window]

    def distance(self, window, i):
        """{unit: seconds from key item i's nearest linked act}, for units within W_MAX."""
        k = (window, i)
        if k not in self._distance:
            units = self.index(window).units
            acts = self.key["items"][i]["acts"]
            out = {}
            for u, unit in enumerate(units):
                gaps = [max(0.0, unit["start"] - a["end"], a["start"] - unit["end"]) for a in acts]
                if gaps and min(gaps) <= W_MAX:
                    out[u] = min(gaps)
            self._distance[k] = out
        return self._distance[k]

    def topics_of(self, window):
        """[topic indices] per unit: the topics whose span holds the unit's start."""
        if window not in self._topics:
            units = self.index(window).units
            spans = [(t["start"], t["end"]) for t in self.key["topics"]]
            self._topics[window] = [[t for t, (a, b) in enumerate(spans) if a <= u["start"] <= b] for u in units]
        return self._topics[window]

    def ami_notes(self):
        """AMI's own sections in the spec's shape (the "AMI itself" row)."""
        return convert(self.root, self.words)


@lru_cache(maxsize=None)
def meeting(m):
    return Meeting(m, answer_keys.all_meetings()[m])


@lru_cache(maxsize=1)
def refs():
    return tuple([SPEC.read_text()] + [p.read_text() for p in sorted(SAMPLES.glob("*.md"))])


# ---------- notes ----------

def strip_thinking(notes):
    """A closed thinking block is cut so the notes after it are scored on their
    merits; R1 has already failed the reply for it."""
    return THINK_BLOCK.sub("", notes, count=1)


def bullets(notes):
    """[{section, text, owner}] for every bullet in the four bullet sections.
    An action's text is its task, without owner or due date (§4)."""
    out = []
    for heading, lines in parse(notes)[0]:
        if heading not in BULLET_SECTIONS:
            continue
        for line in lines:
            if line == NONE or not line.startswith("- "):
                continue
            m = ACTION_ITEM.match(line) if heading == "Action Items" else None
            text = m.group(1) if m else re.sub(r"^- (?:\[ \] )?", "", line)
            out.append({"section": heading, "text": text, "owner": m.group(2) if m else None})
    return out


def summary_sentences(notes):
    return sentences(" ".join(dict(parse(notes)[0]).get("Summary", [])))


def loops(notes):
    """R3: a bullet or sentence twice after normalising, or a 6-word run three
    times within lines. An action's task counts once however many owners share
    it: A4 allows two owners per item, so a task for three people is split."""
    units, owners = [], {}
    for heading, lines in parse(notes)[0]:
        for line in lines:
            if line == NONE:
                continue
            m = ACTION_ITEM.match(line) if heading == "Action Items" else None
            if m:
                owners.setdefault(" ".join(norm_words(m.group(1))), []).append(m.group(2))
                continue
            text = re.sub(r"^- (?:\[ \] )?", "", line)
            units += sentences(text) if heading == "Summary" else [text]
    normalised = [" ".join(norm_words(u)) for u in units]
    found = [f"repeated: {n[:50]}" for i, n in enumerate(normalised) if n and n in normalised[:i]]
    found += [f"repeated action: {t[:50]}" for t, o in owners.items() if len(o) != len(set(o))]
    runs = {}
    for n in normalised + list(owners):
        words = n.split()
        for i in range(len(words) - 5):
            run = tuple(words[i:i + 6])
            runs[run] = runs.get(run, 0) + 1
    found += [f"6-word run x{c}: {' '.join(r)}" for r, c in runs.items() if c >= 3]
    return found


# ---------- scoring one meeting ----------

def check_part(record, mt):
    """The check criteria: rule failures grouped into R1, R2, R4, R12, plus R3."""
    raw = record["notes"]
    think = bool(THINK.match(raw))
    notes = strip_thinking(raw)
    failures = run_checks(notes, mt.transcript, "meeting", refs())
    counts = {g: sum(1 for r, _ in failures if r in rules) for g, rules in GROUPS.items()}
    if think:
        counts["R1"] += 1
    loop = loops(notes)
    out = {"think": think, "truncated": record.get("done_reason") == "length",
           "rules": sorted({r for r, _ in failures}), "fail_counts": counts, "loops": len(loop),
           "R1": counts["R1"] == 0, "R2": counts["R2"] == 0, "R3": not loop, "R4": counts["R4"] == 0,
           "R2x": counts["R2x"] == 0}
    for rule in ("L1", "L2", "L3"):
        out[rule] = not any(r == rule for r, _ in failures)
    summary = " ".join(dict(parse(notes)[0]).get("Summary", []))
    abstract = " ".join(ami_sentences(mt.root, "abstract"))
    ami_words = sum(len(" ".join(ami_sentences(mt.root, t)).split())
                    for t in ("abstract", "decisions", "actions", "problems"))
    out["summary_ratio"] = len(summary.split()) / max(1, len(abstract.split()))
    out["notes_ratio"] = len(notes.split()) / max(1, ami_words)
    return out


class Scored:
    """A note's bullets, anchored once per index window, then scored under any
    thresholds. Only what scoring reads is kept: each bullet's top units, its
    best score near each key item at each w, and, for Key Points and Summary
    sentences, its best score inside each topic."""

    def __init__(self, notes, mt):
        self.mt = mt
        self.notes = strip_thinking(notes)
        self.bullets = bullets(self.notes)
        self.summary = summary_sentences(self.notes)
        self._scores = {}

    def scores(self, window):
        if window not in self._scores:
            idx, mt = self.mt.index(window), self.mt
            dist = [mt.distance(window, ki) for ki in range(len(mt.key["items"]))]
            topics_of = mt.topics_of(window)

            def topic_max(d):
                out = {}
                for u, v in d.items():
                    for t in topics_of[u]:
                        if v > out.get(t, 0.0):
                            out[t] = v
                return out

            tops, local, tmax = [], [], []
            for b in self.bullets:
                d = idx.scores(b["text"])
                tops.append(sorted(d.items(), key=lambda kv: -kv[1])[:TOP_K])
                best = {}
                for ki, near in enumerate(dist):
                    for u, gap in near.items():
                        v = d.get(u)
                        if v:
                            for w in W_ALL:
                                if gap <= w and v > best.get((ki, w), 0.0):
                                    best[(ki, w)] = v
                local.append(best)
                tmax.append(topic_max(d) if b["section"] == "Key Points" else {})
            summary_tmax = [topic_max(idx.scores(x)) for x in self.summary]
            self._scores[window] = (tops, local, tmax + summary_tmax)
        return self._scores[window]


def turn_score(sc, cfg, bi, ki):
    tops, local, _ = sc.scores(cfg["window"])
    if not sc.mt.key["items"][ki]["acts"]:
        return 0.0
    if cfg["mode"] == "global":
        dist = sc.mt.distance(cfg["window"], ki)
        return max((s for u, s in tops[bi] if s >= cfg["tau_support"] and dist.get(u, W_MAX + 1) <= cfg["w"]),
                   default=0.0)
    return local[bi].get((ki, cfg["w"]), 0.0)


def match_score(sc, cfg, bi, ki):
    t = turn_score(sc, cfg, bi, ki)
    if not cfg["word_score"]:
        return t
    return max(t, dice(sc.bullets[bi]["text"], sc.mt.key["items"][ki]["task"]))


def assign(sc, cfg):
    """§4 step 6: one to one, best first, own section; then unmatched decision and
    action items against every other section's bullets (misplaced, R11)."""
    items = sc.mt.key["items"]
    used_b, used_k, hits, misplaced = set(), set(), [], []
    pairs = []
    for ki, item in enumerate(items):
        for bi, b in enumerate(sc.bullets):
            if b["section"] == SECTION_OF[item["type"]]:
                s = match_score(sc, cfg, bi, ki)
                if s >= cfg["tau_match"]:
                    pairs.append((s, bi, ki))
    for s, bi, ki in sorted(pairs, key=lambda p: (-p[0], p[1], p[2])):
        if bi not in used_b and ki not in used_k:
            used_b.add(bi)
            used_k.add(ki)
            hits.append((bi, ki))
    pairs = []
    for ki, item in enumerate(items):
        if ki in used_k or item["type"] == "problem":
            continue
        for bi, b in enumerate(sc.bullets):
            if bi not in used_b and b["section"] != SECTION_OF[item["type"]]:
                s = match_score(sc, cfg, bi, ki)
                if s >= cfg["tau_match"]:
                    pairs.append((s, bi, ki))
    for s, bi, ki in sorted(pairs, key=lambda p: (-p[0], p[1], p[2])):
        if bi not in used_b and ki not in used_k:
            used_b.add(bi)
            used_k.add(ki)
            misplaced.append((bi, ki))
    return hits, misplaced


def anchored_part(sc, cfg):
    tops, _, tmax = sc.scores(cfg["window"])
    items = sc.mt.key["items"]
    out = {}
    # R5, split into Key Points and the item sections: BM25 ÷ summed IDF is
    # harder on long bullets, and Key Points are the long ones.
    for name, sections in (("kp", ("Key Points",)), ("items", ("Decisions", "Action Items", "Open Questions"))):
        idx = [i for i, b in enumerate(sc.bullets) if b["section"] in sections]
        out[f"sup_{name}"] = sum(1 for i in idx if tops[i] and tops[i][0][1] >= cfg["tau_support"])
        out[f"tot_{name}"] = len(idx)
    hits, misplaced = assign(sc, cfg)
    for kind, section in SECTION_OF.items():
        out[f"m_{kind}"] = sum(1 for bi, ki in hits if items[ki]["type"] == kind)
        out[f"b_{kind}"] = sum(1 for b in sc.bullets if b["section"] == section)
        out[f"k_{kind}"] = sum(1 for i in items if i["type"] == kind)
    known = [(sc.bullets[bi]["owner"], items[ki]["owners"]) for bi, ki in hits
             if items[ki]["type"] == "action" and items[ki]["owners"]]
    out["own_known"] = len(known)
    out["own_agree"] = sum(1 for o, k in known if o and set(k) <= set(o.split(" and ")))
    da = sum(1 for bi, ki in hits if items[ki]["type"] in ("decision", "action"))
    out["misplaced"] = len(misplaced)
    out["matched_any"] = da + len(misplaced)
    # R10: a topic is covered when a Key Point or Summary sentence has a unit
    # above τ_support inside the topic's span.
    out["top_tot"] = len(sc.mt.key["topics"])
    out["top_cov"] = sum(1 for t in range(out["top_tot"]) if any(m.get(t, 0) >= cfg["tau_support"] for m in tmax))
    out["keyless"] = sum(1 for i in items if not i["acts"])
    return out


# ---------- pooling ----------

COUNT_KEYS = ["sup_kp", "tot_kp", "sup_items", "tot_items", "m_decision", "b_decision", "k_decision",
              "m_action", "b_action", "k_action", "m_problem", "b_problem", "k_problem",
              "own_agree", "own_known", "misplaced", "matched_any", "top_cov", "top_tot"]
CHECK_KEYS = ["R1", "R2", "R2x", "R3", "R4", "think", "truncated", "L1", "L2", "L3"]


def f1(m, b, k):
    return 2 * m / (b + k) if b + k else 1.0


def metrics(t, n):
    """Criterion values from pooled totals `t` over `n` meetings."""
    def share(a, b):
        return t[a] / t[b] if t[b] else None
    out = {k: t[k] / n for k in CHECK_KEYS}
    out["R5"] = (t["sup_kp"] + t["sup_items"]) / max(1, t["tot_kp"] + t["tot_items"])
    out["R5_kp"], out["R5_items"] = share("sup_kp", "tot_kp"), share("sup_items", "tot_items")
    for kind, r in (("decision", "R6"), ("action", "R7"), ("problem", "R9")):
        m, b, k = t[f"m_{kind}"], t[f"b_{kind}"], t[f"k_{kind}"]
        out[f"{r}_p"] = m / b if b else None
        out[f"{r}_r"] = m / k if k else None
        out[r] = f1(m, b, k)
    out["item_f1"] = (out["R6"] + out["R7"] + out["R9"]) / 3
    out["R8"] = share("own_agree", "own_known")
    out["R10"] = share("top_cov", "top_tot")
    out["R11"] = share("misplaced", "matched_any")
    return out


def pooled(per_meeting, idx=None):
    rows = per_meeting if idx is None else [per_meeting[i] for i in idx]
    t = {k: sum(r[k] for r in rows) for k in COUNT_KEYS + CHECK_KEYS}
    return metrics(t, len(rows))


def config_name(cfg):
    return f"{cfg['mode']}/win{cfg['window']}/τs{cfg['tau_support']}/τm{cfg['tau_match']}/w{cfg['w']}" + \
        ("" if cfg["word_score"] else "/no-words")


def thresholds():
    if THRESHOLDS.exists():
        frozen = json.loads(THRESHOLDS.read_text())
        return {k: frozen.get(k, v) for k, v in START.items()}, True
    return dict(START), False


def stable_hash(text):
    return hashlib.sha1(text.encode()).hexdigest()[:10]


# ---------- rows ----------

EMPTY = ("## Summary\nThe meeting covered the project. Next steps were discussed.\n\n"
         "## Key Points\n- The project was discussed.\n- Ideas were shared.\n- Next steps were considered.\n\n"
         "## Decisions\nNone recorded.\n\n## Action Items\nNone recorded.\n\n## Open Questions\nNone recorded.\n")


def eval_meetings(splits=("test", "reserve")):
    return [m for s in splits for m in sorted(SPLITS[s]())]


def wrong_meeting(m, pool):
    """A meeting in another scenario and another phase, picked deterministically."""
    others = sorted(x for x in pool if x[:2] != m[:2] and x[-1] != m[-1])
    return others[(pool.index(m) * 7) % len(others)]


def note_dir(model, prompt):
    return NOTES / f"{model.replace(':', '_')}__{prompt}"


def records(model, prompt, pool):
    out = {}
    for m in pool:
        p = note_dir(model, prompt) / f"{m}.json"
        if p.exists():
            out[m] = json.loads(p.read_text())
    return out


def baseline_records(kind, pool, teacher):
    if kind == "empty":
        return {m: {"notes": EMPTY, "done_reason": "stop"} for m in pool}
    if kind == "ami":
        return {m: {"notes": re.sub(r"- TODO: .*\n", "", meeting(m).ami_notes()), "done_reason": "stop"}
                for m in pool}
    own = records(teacher, "teacher", pool)
    return {m: own[wrong_meeting(m, pool)] for m in pool if wrong_meeting(m, pool) in own}


_scored = {}


def scored(record, m):
    """Scored() for a note on meeting m, cached by note text."""
    k = (m, stable_hash(record["notes"]))
    if k not in _scored:
        _scored[k] = Scored(record["notes"], meeting(m))
    return _scored[k]


_checks = {}


def checked(record, m):
    k = (m, stable_hash(record["notes"]), record.get("done_reason"))
    if k not in _checks:
        _checks[k] = check_part(record, meeting(m))
    return _checks[k]


def score(record, m, cfg):
    """One meeting's counts for every criterion."""
    return {**checked(record, m), **anchored_part(scored(record, m), cfg)}


# ---------- statistics ----------

def resamples(n, count=10_000, seed=0):
    rng = random.Random(seed)
    return [[rng.randrange(n) for _ in range(n)] for _ in range(count)]


def interval(values):
    v = sorted(x for x in values if x is not None)
    if not v:
        return (None, None)
    return (v[int(0.025 * (len(v) - 1))], v[int(0.975 * (len(v) - 1))])


def boot(per_meeting, draws, keys):
    """{criterion: [value per resample]}; per_meeting rows in the shared meeting order."""
    out = {k: [] for k in keys}
    for idx in draws:
        mt = pooled(per_meeting, idx)
        for k in keys:
            out[k].append(mt[k])
    return out


# Gate lines (§8): criterion, margin, which end of the interval must clear it.
GATE = [("R1", -0.10, "lower"), ("R2", -0.10, "lower"), ("R3", -0.10, "lower"),
        ("R4", -0.05, "lower"), ("R5", -0.05, "lower"), ("item_f1", -0.05, "lower"),
        ("R10", -0.05, "lower"), ("R11", +0.05, "upper")]
BOOT_KEYS = ["R1", "R2", "R2x", "R3", "R4", "R5", "R5_kp", "R5_items", "R6", "R7", "R8", "R9",
             "item_f1", "R10", "R11", "think", "L1", "L2", "L3"]


def verdict(lo, hi, margin, end):
    if lo is None:
        return "n/a"
    if end == "lower":
        return "match" if lo >= margin else "worse" if hi < margin else "undecided"
    return "match" if hi <= margin else "worse" if lo > margin else "undecided"


def diff(a, b):
    return [x - y if x is not None and y is not None else None for x, y in zip(a, b)]


# ---------- the sweep and the label-free check on Dev ----------

SWEEP = [{"mode": mode, "window": win, "tau_support": ts, "tau_match": tm, "w": w, "word_score": True}
         for mode in ("global", "local") for win in (1, 3, "60s")
         for ts in (0.2, 0.3, 0.4) for tm in (0.2, 0.3, 0.4) for w in (0, 20, 60)]


def proxy():
    """Label-free threshold check on Dev only, until your labels exist (§5).
    Matcher recall: AMI's own sections against their own key, word score off,
    so only anchoring can match them. False matches: AMI's sections for another
    scenario and phase against this key, word score on. Support separation: AMI's
    abstract sentences supported on their own meeting minus on the wrong one."""
    dev = eval_meetings(("dev",))
    own = baseline_records("ami", dev, None)
    wrong = {m: own[wrong_meeting(m, dev)] for m in dev}
    empty = baseline_records("empty", dev, None)
    results = []
    for cfg in SWEEP:
        off = {**cfg, "word_score": False}
        tp = n = fp = 0
        sup_own = sup_wrong = tot = 0
        e_rows = []
        for m in dev:
            a = anchored_part(scored(own[m], m), off)
            tp += a["m_decision"] + a["m_action"] + a["m_problem"]
            n += a["k_decision"] + a["k_action"] + a["k_problem"]
            b = anchored_part(scored(wrong[m], m), cfg)
            fp += b["m_decision"] + b["m_action"] + b["m_problem"]
            e_rows.append(score(empty[m], m, cfg))
            for text in ami_sentences(meeting(m).root, "abstract"):
                tot += 1
                sup_own += max(meeting(m).index(cfg["window"]).scores(text).values(), default=0) >= cfg["tau_support"]
                sup_wrong += max(meeting(wrong_meeting(m, dev)).index(cfg["window"]).scores(text).values(),
                                 default=0) >= cfg["tau_support"]
        recall, precision = tp / n, tp / max(1, tp + fp)
        results.append({"config": cfg, "name": config_name(cfg), "recall": recall, "precision": precision,
                        "f1": 2 * recall * precision / max(1e-9, recall + precision),
                        "support_separation": (sup_own - sup_wrong) / max(1, tot),
                        "empty_item_f1": pooled(e_rows)["item_f1"], "empty_R10": pooled(e_rows)["R10"]})
    results.sort(key=lambda r: (-(r["empty_item_f1"] <= 0.05), -r["f1"], -r["support_separation"]))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "proxy.json").write_text(json.dumps(results, indent=2, ensure_ascii=False, default=str) + "\n")
    print("| Config | Matcher recall | Precision | F1 | Support separation | Empty item F1 | Empty R10 |")
    print("|---|---|---|---|---|---|---|")
    for r in results[:12]:
        print(f"| {r['name']} | {r['recall']:.2f} | {r['precision']:.2f} | {r['f1']:.2f} | "
              f"{r['support_separation']:.2f} | {r['empty_item_f1']:.2f} | {r['empty_R10']:.2f} |")
    return results


def proxy_best():
    path = OUT / "proxy.json"
    return json.loads(path.read_text())[0]["config"] if path.exists() else None


# ---------- report ----------

def model_rows():
    from scoreboard import MODELS, TEACHER
    return [(m, "teacher") for m in MODELS] + [(TEACHER, "today")], TEACHER


def cost(recs, pool):
    """R13 from the run records: medians, first-call and highest memory."""
    rs = [recs[m] for m in pool if m in recs]
    if not rs:
        return {}
    def med(f):
        v = [f(r) for r in rs if f(r) is not None]
        return statistics.median(v) if v else None
    mem = [max(r.get("peak_rss", 0), r.get("peak_footprint", 0)) for r in rs]
    first = recs.get(pool[0])
    return {"wall_s": med(lambda r: r.get("wall_s")),
            "prompt_tps": med(lambda r: r["prompt_eval_count"] / (r["prompt_eval_duration"] / 1e9)
                              if r.get("prompt_eval_duration") else None),
            "gen_tps": med(lambda r: r["eval_count"] / (r["eval_duration"] / 1e9) if r.get("eval_duration") else None),
            "gen_tokens": med(lambda r: r.get("eval_count")),
            # Hidden reasoning shows as tokens generated per visible word of notes.
            "tokens_per_word": med(lambda r: r["eval_count"] / max(1, len(r["notes"].split()))
                                   if r.get("eval_count") else None),
            "empty": sum(not r["notes"].strip() for r in rs),
            "memory_first": max(first.get("peak_rss", 0), first.get("peak_footprint", 0)) if first else None,
            "memory_max": max(mem), "truncated": sum(r.get("done_reason") == "length" for r in rs)}


def evaluate(cfg, pool, rows, teacher, draws=None):
    """{label: {"per_meeting": [...], "point": metrics, "boot": {...}}} for model and baseline rows."""
    table = {}
    for model, prompt in rows:
        recs = records(model, prompt, pool)
        if recs:
            table[f"{model} {prompt}"] = {"model": model, "prompt": prompt, "recs": recs}
    for kind in ("empty", "wrong", "ami"):
        table[f"baseline {kind}"] = {"model": kind, "prompt": "baseline",
                                     "recs": baseline_records(kind, pool, teacher)}
    for label, row in table.items():
        c = {**cfg, "word_score": False} if label == "baseline ami" else cfg
        row["complete"] = len(row["recs"]) == len(pool)
        row["per_meeting"] = [score(row["recs"][m], m, c) if m in row["recs"] else None for m in pool]
        have = [r for r in row["per_meeting"] if r is not None]
        row["point"] = pooled(have) if have else {}
        row["n"] = len(have)
        if draws and row["complete"]:
            row["boot"] = boot(row["per_meeting"], draws, BOOT_KEYS)
    return table


def gate_table(table, teacher_label):
    base = table[teacher_label]
    out = {}
    for label, row in table.items():
        if label == teacher_label or row["prompt"] == "baseline" or "boot" not in row or "boot" not in base:
            continue
        lines = {}
        for crit, margin, end in GATE:
            d = diff(row["boot"][crit], base["boot"][crit])
            lo, hi = interval(d)
            point = (row["point"][crit] - base["point"][crit]) if row["point"][crit] is not None \
                and base["point"][crit] is not None else None
            lines[crit] = {"diff": point, "lo": lo, "hi": hi, "verdict": verdict(lo, hi, margin, end)}
        checks_all = all(lines[c]["verdict"] == "match" for c in ("R1", "R2", "R3", "R4"))
        lo, hi = interval(diff(row["boot"]["R2x"], base["boot"]["R2x"]))
        info = {"R2x": {"diff": row["point"]["R2x"] - base["point"]["R2x"], "lo": lo, "hi": hi,
                        "verdict": verdict(lo, hi, -0.10, "lower")}}
        out[label] = {"lines": lines, "matches": all(v["verdict"] == "match" for v in lines.values()),
                      "matches_on_checks": checks_all, "info": info}
    return out


def sweep(pool, rows, teacher):
    """Point estimates under every SWEEP config, for how far the ranking moves."""
    out = []
    for cfg in SWEEP:
        t = evaluate(cfg, pool, rows, teacher)
        out.append({"config": config_name(cfg),
                    "rows": {l: {k: t[l]["point"].get(k) for k in ("item_f1", "R5", "R5_kp", "R10", "R11", "R8")}
                             for l in t if t[l]["n"]}})
    return out


def fmt(v, d=2):
    return "—" if v is None else f"{v:.{d}f}"


def ci(row, k, d=2):
    if "boot" not in row:
        return fmt(row["point"].get(k), d) + ("*" if row["point"].get(k) is not None else "")
    lo, hi = interval(row["boot"][k])
    return f"{fmt(row['point'].get(k), d)} [{fmt(lo, d)}, {fmt(hi, d)}]"


def render(results):
    lines = []
    for name, res in results["configs"].items():
        t, g = res["table"], res["gate"]
        lines += [f"## Scores at {name} (`{config_name(res['cfg'])}`)", "",
                  "Point value [95% bootstrap interval], 40 meetings; * = row incomplete, no interval.", "",
                  "| Row | n | R1 Format | R2 Safety | R2 without N1 | R3 No loops | R4 Surface grounding | R5 Support "
                  "(KP / items) | Item F1 | R6 Decisions P/R | R7 Actions P/R | R8 Owners | R9 Open Qs P/R | "
                  "R10 Topics | R11 Misplaced | Think leak |", "|" + "---|" * 16]
        for label, row in t.items():
            p = row["point"]
            if not p:
                continue
            lines.append(" | ".join([
                f"| `{label}`", str(row["n"]), ci(row, "R1"), ci(row, "R2"), ci(row, "R2x"), ci(row, "R3"), ci(row, "R4"),
                f"{ci(row, 'R5')} ({fmt(p['R5_kp'])} / {fmt(p['R5_items'])})", ci(row, "item_f1"),
                f"{fmt(p['R6_p'])} / {fmt(p['R6_r'])}", f"{fmt(p['R7_p'])} / {fmt(p['R7_r'])}", ci(row, "R8"),
                f"{fmt(p['R9_p'])} / {fmt(p['R9_r'])}", ci(row, "R10"), ci(row, "R11"), f"{fmt(p['think'])} |"]))
        lines += ["", f"### Against the 12B (§8) at {name}", "",
                  "Candidate − 12B, point [95% interval of the paired difference]. Anchored lines (R5, Item F1, "
                  "R10, R11) are uncalibrated and don't gate (§6.1) until your labels exist.", "",
                  "| Row | " + " | ".join(c for c, _, _ in GATE) + " | Checks R1–R4 | All lines | "
                  "R2 without N1 (info) |", "|" + "---|" * (len(GATE) + 4)]
        for label, v in g.items():
            cells = [f"{fmt(x['diff'])} [{fmt(x['lo'])}, {fmt(x['hi'])}] **{x['verdict']}**"
                     for x in [v["lines"][c] for c, _, _ in GATE] + [v["info"]["R2x"]]]
            lines.append(f"| `{label}` | " + " | ".join(cells[:-1]) +
                         f" | {'match' if v['matches_on_checks'] else 'no'} | {'match' if v['matches'] else 'no'} | "
                         f"{cells[-1]} |")
        lines.append("")
    lines += ["## Cost (R13)", "",
              "Medians per meeting. First-call memory is the first Test meeting; highest is over every call, with "
              "Ollama's runner reset whenever it passed 13 GB (step 2's Test calls had no reset).", "",
              "| Row | Download | Wall s | Prompt tok/s | Gen tok/s | Tokens out | Tokens per visible word | "
              "Memory first / highest | Cut off | Empty |",
              "|---|---|---|---|---|---|---|---|---|---|"]
    sizes = results.get("sizes", {})
    for label, c in results["cost"].items():
        if not c:
            continue
        size = sizes.get(label.split()[0])
        lines.append(f"| `{label}` | {fmt(size / 1e9, 1) + ' GB' if size else '—'} | {fmt(c['wall_s'], 0)} | "
                     f"{fmt(c['prompt_tps'], 0)} | {fmt(c['gen_tps'], 1)} | {fmt(c['gen_tokens'], 0)} | "
                     f"{fmt(c['tokens_per_word'], 1)} | "
                     f"{fmt((c['memory_first'] or 0) / 1e9, 1)} / {fmt(c['memory_max'] / 1e9, 1)} GB | {c['truncated']} | "
                     f"{c['empty']} |")
    lines += ["", "## Meetings failing each check rule", "", "| Row | Failing rules |", "|---|---|"]
    for label, rules in results["rules"].items():
        lines.append(f"| `{label}` | {', '.join(f'{r} {n}' for r, n in rules.items()) or 'none'} |")
    if results.get("sweep"):
        lines += ["", f"## Item F1 across the {len(results['sweep'])}-config sweep", "",
                  "Rank 1 is the highest Item F1 among model rows (baselines left out) under each config. "
                  "\"Beats qwen\" and \"within 0.05 of the 12B\" count configs.", "",
                  "| Row | Median Item F1 | Min–max | Median rank | Rank range | Beats qwen3.5:4b | Within 0.05 of 12B |",
                  "|---|---|---|---|---|---|---|"]
        for label, v in sweep_summary(results["sweep"]).items():
            lines.append(f"| `{label}` | {fmt(v['median'])} | {fmt(v['min'])}–{fmt(v['max'])} | {v['median_rank']:g} | "
                         f"{v['rank_min']}–{v['rank_max']} | {v['beats_qwen']}/{v['n']} | {v['near_12b']}/{v['n']} |")
    return "\n".join(lines) + "\n"


def sweep_summary(sw):
    models = [l for l in sw[0]["rows"] if not l.startswith("baseline")]
    out = {}
    for label in models:
        vals, ranks, beats, near = [], [], 0, 0
        for c in sw:
            rows = {l: v for l, v in c["rows"].items() if l in models and v["item_f1"] is not None}
            if label not in rows:
                continue
            order = sorted(rows, key=lambda l: -rows[l]["item_f1"])
            v = rows[label]["item_f1"]
            vals.append(v)
            ranks.append(order.index(label) + 1)
            beats += v > rows.get("qwen3.5:4b teacher", {}).get("item_f1", 1)
            near += v >= rows.get("gemma4:12b-mlx teacher", {}).get("item_f1", 0) - 0.05
        if vals:
            out[label] = {"median": statistics.median(vals), "min": min(vals), "max": max(vals),
                          "median_rank": statistics.median(ranks), "rank_min": min(ranks), "rank_max": max(ranks),
                          "beats_qwen": beats, "near_12b": near, "n": len(vals)}
    return dict(sorted(out.items(), key=lambda kv: kv[1]["median_rank"]))


def report(do_sweep=True):
    rows, teacher = model_rows()
    pool = eval_meetings(("test", "reserve"))
    draws = resamples(len(pool))
    configs = {"the starting guess": START}
    best = proxy_best()
    if best:
        configs["the Dev proxy's best config"] = best
    cal, calibrated = thresholds()
    if calibrated:
        configs = {"your calibrated thresholds": cal, **configs}
    from scoreboard import model_sizes
    results = {"meetings": pool, "configs": {}, "sizes": model_sizes()}
    for name, cfg in configs.items():
        t = evaluate(cfg, pool, rows, teacher, draws)
        results["configs"][name] = {"cfg": cfg, "table": t, "gate": gate_table(t, f"{teacher} teacher")}
    first = next(iter(results["configs"].values()))["table"]
    results["cost"] = {label: cost(row["recs"], pool) for label, row in first.items() if row["prompt"] != "baseline"}
    results["rules"] = {label: dict(Counter(r for x in row["per_meeting"] if x for r in x["rules"]).most_common())
                        for label, row in first.items()}
    if do_sweep:
        results["sweep"] = sweep(pool, rows, teacher)
    OUT.mkdir(parents=True, exist_ok=True)
    slim = {"meetings": pool, "cost": results["cost"], "rules": results["rules"], "sweep": results.get("sweep"),
            "configs": {n: {"cfg": c["cfg"], "gate": c["gate"],
                            "rows": {l: {"n": r["n"], "complete": r["complete"], "point": r["point"],
                                         "interval": {k: interval(r["boot"][k]) for k in BOOT_KEYS} if "boot" in r else None,
                                         "per_meeting": dict(zip(pool, r["per_meeting"]))}
                                     for l, r in c["table"].items()}}
                        for n, c in results["configs"].items()}}
    (OUT / "scores.json").write_text(json.dumps(slim, indent=1, ensure_ascii=False, default=str) + "\n")
    text = render(results)
    (OUT / "report.md").write_text(text)
    print(text)
    return results


# ---------- calibration: your labels (§5) ----------

LABELS = LAB / "labels" / "dev.jsonl"
LABEL_MODELS = ("gemma4:12b-mlx", "qwen3.5:4b")
PER_KIND = 60


def label_questions():
    """60 "same item?" and 60 "supported?" questions from the Dev notes: half at
    random, half near the starting guess's thresholds, seed 0."""
    dev = eval_meetings(("dev",))
    match_pool, support_pool = [], []
    for model in LABEL_MODELS:
        for m, rec in sorted(records(model, "teacher", dev).items()):
            sc = scored(rec, m)
            tops, _, _ = sc.scores(START["window"])
            for bi, b in enumerate(sc.bullets):
                top = tops[bi][0][1] if tops[bi] else 0.0
                support_pool.append({"kind": "support", "model": model, "meeting": m, "bullet": bi,
                                     "section": b["section"], "text": b["text"], "start_score": top})
                for ki, item in enumerate(sc.mt.key["items"]):
                    if b["section"] == SECTION_OF[item["type"]]:
                        match_pool.append({"kind": "match", "model": model, "meeting": m, "bullet": bi, "item": ki,
                                           "section": b["section"], "text": b["text"], "item_text": item["text"],
                                           "start_score": match_score(sc, START, bi, ki)})
    rng = random.Random(0)
    chosen = []
    for pool_, tau in ((match_pool, START["tau_match"]), (support_pool, START["tau_support"])):
        rand = rng.sample(pool_, min(PER_KIND // 2, len(pool_)))
        rest = [q for q in pool_ if q not in rand]
        near = sorted(rest, key=lambda q: (abs(q["start_score"] - tau), rng.random()))[:PER_KIND // 2]
        chosen += [{**q, "sample": "random"} for q in rand] + [{**q, "sample": "near"} for q in near]
    rng.shuffle(chosen)
    for q in chosen:
        q["id"] = stable_hash(json.dumps({k: q[k] for k in ("kind", "model", "meeting", "text")} | {"item": q.get("item")}))
    return chosen


def turns_text(mt, units, window, n=3):
    idx = mt.index(window)
    out = []
    for u in units[:n]:
        unit = idx.units[u]
        mm, ss = divmod(int(unit["start"]), 60)
        out.append(f"    [{mm:02d}:{ss:02d}] {unit['text'][:300]}")
    return "\n".join(out)


def label():
    """Ask each question in the terminal: y, n, s (skip) or q (quit). Resumes."""
    done = set()
    if LABELS.exists():
        done = {json.loads(l)["id"] for l in LABELS.read_text().splitlines() if l.strip()}
    questions = [q for q in label_questions() if q["id"] not in done]
    LABELS.parent.mkdir(parents=True, exist_ok=True)
    print(f"{len(done)} labelled, {len(questions)} to go. y = yes, n = no, s = skip, q = quit.\n")
    for i, q in enumerate(questions, 1):
        mt = meeting(q["meeting"])
        rec = records(q["model"], "teacher", [q["meeting"]])[q["meeting"]]
        d = mt.index(START["window"]).scores(q["text"])
        mine = sorted(d, key=lambda u: -d[u])
        print(f"--- {i}/{len(questions)}  {q['meeting']}  {q['section']}")
        print(f"  Bullet: {q['text']}")
        print("  Its best-matching turns:\n" + turns_text(mt, mine, START["window"]))
        if q["kind"] == "match":
            item = mt.key["items"][q["item"]]
            linked = [i for i, a in enumerate(mt.acts) if a["id"] in {x["id"] for x in item["acts"]}]
            print(f"  AMI {item['type']}: {item['text']}")
            print("  Turns AMI links it to:\n" + "\n".join(
                f"    [{int(mt.acts[i]['start']) // 60:02d}:{int(mt.acts[i]['start']) % 60:02d}] {mt.acts[i]['text'][:300]}"
                for i in linked[:3]) if linked else "  (no linked turns)")
            prompt = "  Same item? "
        else:
            prompt = "  Do these turns say what the bullet says? "
        while (a := input(prompt).strip().lower()) not in ("y", "n", "s", "q"):
            pass
        if a == "q":
            break
        with LABELS.open("a") as f:
            f.write(json.dumps({**{k: q[k] for k in ("id", "kind", "model", "meeting", "bullet", "sample", "text")},
                                "item": q.get("item"), "answer": a}, ensure_ascii=False) + "\n")


CAL_GRID = [{"mode": mode, "window": win, "tau_support": ts, "tau_match": tm, "w": w, "word_score": True}
            for mode in ("global", "local") for win in (1, 3, "60s")
            for ts in [x / 100 for x in range(10, 61, 5)]
            for tm in [x / 100 for x in range(10, 71, 5)] for w in (0, 5, 10, 20, 30, 60)]


def calibrate():
    """Pick thresholds on your labels, with 5-fold cross-validated accuracy, and
    freeze them in rubric-thresholds.json."""
    labels = [json.loads(l) for l in LABELS.read_text().splitlines() if l.strip()]
    labels = [l for l in labels if l["answer"] in ("y", "n")]
    match = [l for l in labels if l["kind"] == "match"]
    support = [l for l in labels if l["kind"] == "support"]

    def sc_of(l):
        return scored(records(l["model"], "teacher", [l["meeting"]])[l["meeting"]], l["meeting"])

    def predict(l, cfg):
        sc = sc_of(l)
        if l["kind"] == "match":
            return match_score(sc, cfg, l["bullet"], l["item"]) >= cfg["tau_match"]
        tops, _, _ = sc.scores(cfg["window"])
        return bool(tops[l["bullet"]]) and tops[l["bullet"]][0][1] >= cfg["tau_support"]

    def f1_of(ls, cfg):
        tp = sum(predict(l, cfg) and l["answer"] == "y" for l in ls)
        fp = sum(predict(l, cfg) and l["answer"] == "n" for l in ls)
        fn = sum(not predict(l, cfg) and l["answer"] == "y" for l in ls)
        return 2 * tp / max(1, 2 * tp + fp + fn)

    def grid(kind):
        # τ_support only matters for support, and for matching in global mode.
        seen, out = set(), []
        for c in CAL_GRID:
            k = (c["mode"], c["window"], c["tau_match"], c["w"], c["tau_support"] if c["mode"] == "global" else None) \
                if kind == "match" else (c["window"], c["tau_support"])
            if k not in seen:
                seen.add(k)
                out.append(c)
        return out

    def tune(ls, kind, window=None):
        return max((c for c in grid(kind) if window is None or c["window"] == window), key=lambda c: f1_of(ls, c))

    def cross_validate(ls, kind):
        rng = random.Random(0)
        order = ls[:]
        rng.shuffle(order)
        pairs = []
        for fold in range(5):
            test = order[fold::5]
            train = [l for l in order if l not in test]
            cfg = tune(train, kind, None if kind == "match" else best_match["window"])
            pairs += [(predict(l, cfg), l["answer"] == "y") for l in test]
        draws = resamples(len(pairs))
        def pr(ps):
            tp = sum(p and a for p, a in ps)
            return tp / max(1, sum(p for p, _ in ps)), tp / max(1, sum(a for _, a in ps))
        p, r = pr(pairs)
        boot_ = [pr([pairs[i] for i in d]) for d in draws[:2000]]
        return {"precision": p, "recall": r, "precision_ci": interval([b[0] for b in boot_]),
                "recall_ci": interval([b[1] for b in boot_]), "n": len(pairs)}

    # One unit window serves both: matching picks it, support tunes τ_support on it.
    best_match = tune(match, "match")
    best_support = tune(support, "support", best_match["window"])
    frozen = {"mode": best_match["mode"], "window": best_match["window"], "tau_match": best_match["tau_match"],
              "w": best_match["w"], "tau_support": best_support["tau_support"], "word_score": True,
              "accuracy": {"match": cross_validate(match, "match"), "support": cross_validate(support, "support")},
              "labels": len(labels)}
    THRESHOLDS.write_text(json.dumps(frozen, indent=2) + "\n")
    print(json.dumps(frozen, indent=2))
    ok = all(frozen["accuracy"][k][x] >= 0.85 for k in ("match", "support") for x in ("precision", "recall"))
    print("Matcher accuracy (§6.1):", "passes" if ok else "misses 0.85; anchored criteria stay ungated")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("report")
    r.add_argument("--no-sweep", action="store_true")
    sub.add_parser("proxy")
    sub.add_parser("label")
    sub.add_parser("calibrate")
    args = ap.parse_args()
    if args.cmd == "report":
        report(not args.no_sweep)
    else:
        {"proxy": proxy, "label": label, "calibrate": calibrate}[args.cmd]()


if __name__ == "__main__":
    main()
