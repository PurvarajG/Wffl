"""Mutation tests for the rubric eval (rubric-spec.md §6.2).

Code plants one known fault in a good note and checks that the target
criterion gets strictly worse. Good notes: the six samples and the 12B's Dev
notes (its Test notes stand in while Dev isn't run yet). Check criteria must
catch 100% of their mutations, anchored criteria at least 95%, under the
config being tested (the starting guess, or RUBRIC_CONFIG=proxy for the Dev
proxy's best).

    python3 -I tools/model-lab/test_rubric.py          unittest, plus catch rates
"""
import json
import os
import random
import re
import sys
import unittest
from pathlib import Path

LAB = Path(__file__).resolve().parent
sys.path.insert(0, str(LAB))  # -I leaves the script's folder off the path
import answer_keys  # noqa: E402
import rubric as R  # noqa: E402
from checks import NONE, parse, run_checks  # noqa: E402

ROLES = ["Project Manager", "Industrial Designer", "User Interface Designer", "Marketing Expert"]
SEED = 0


def cfg():
    if os.environ.get("RUBRIC_CONFIG") == "proxy" and R.proxy_best():
        return R.proxy_best()
    return R.START


def good_notes():
    """[(meeting, record)]: the six samples, then the 12B's Dev (or Test) notes."""
    out = []
    manifest = json.loads((R.SAMPLES / "manifest.json").read_text())
    for s in manifest["samples"]:
        out.append((s["meeting"], {"notes": (R.SAMPLES / f"{s['meeting']}.md").read_text(), "done_reason": "stop"}))
    for split in ("dev", "test"):
        recs = R.records("gemma4:12b-mlx", "teacher", R.eval_meetings((split,)))
        if len(recs) >= 10:
            out += sorted(recs.items())
            return out, split
    return out, "samples only"


def rebuild(sections):
    return "\n\n".join(f"## {h}\n" + "\n".join(lines) for h, lines in sections) + "\n"


def edit(notes, fn):
    sections, _ = parse(notes)
    sections = [(h, list(lines)) for h, lines in sections]
    if fn(dict(sections)) is False:
        return None
    return rebuild(sections)


# ---------- mutations: (name, target, apply(notes, meeting) -> new notes or None) ----------

def swap_owner(notes, m):
    """Swap a matched action's owner to another role that speaks in the meeting."""
    sc = R.scored({"notes": notes}, m)
    hits, _ = R.assign(sc, cfg())
    items = sc.mt.key["items"]
    for bi, ki in hits:
        if items[ki]["type"] == "action" and items[ki]["owners"] and sc.bullets[bi]["owner"]:
            owner = sc.bullets[bi]["owner"]
            if not set(items[ki]["owners"]) <= set(owner.split(" and ")):
                continue  # already wrong; swapping can't make it worse
            other = next(r for r in ROLES if r not in items[ki]["owners"])
            text = sc.bullets[bi]["text"]
            return notes.replace(f"- [ ] {text} — {owner}", f"- [ ] {text} — {other}", 1)
    return None


def insert_foreign_decision(notes, m):
    pool = sorted(answer_keys.all_meetings())
    others = [x for x in pool if x[:2] != m[:2] and x[-1] != m[-1]]
    rng = random.Random(f"{SEED}{m}")
    for x in rng.sample(others, len(others)):
        key, _ = answer_keys.load(x, answer_keys.all_meetings()[x])
        decisions = [i["text"] for i in key["items"] if i["type"] == "decision"]
        if decisions:
            def fn(s):
                s["Decisions"][:] = [l for l in s["Decisions"] if l != NONE] + [f"- {decisions[0]}"]
            return edit(notes, fn)
    return None


def move_decision(notes, m):
    """Move a matched decision bullet into Key Points."""
    sc = R.scored({"notes": notes}, m)
    hits, _ = R.assign(sc, cfg())
    items = sc.mt.key["items"]
    for bi, ki in hits:
        if items[ki]["type"] == "decision":
            line = f"- {sc.bullets[bi]['text']}"
            def fn(s):
                s["Decisions"].remove(line)
                if not s["Decisions"]:
                    s["Decisions"].append(NONE)
                s["Key Points"].append(line)
            return edit(notes, fn)
    return None


def delete_matched(kind):
    def apply(notes, m):
        sc = R.scored({"notes": notes}, m)
        hits, _ = R.assign(sc, cfg())
        for bi, ki in hits:
            if sc.mt.key["items"][ki]["type"] == kind:
                b = sc.bullets[bi]
                section = R.SECTION_OF[kind]
                def fn(s):
                    for line in s[section]:
                        if line.startswith("- ") and b["text"] in line:
                            s[section].remove(line)
                            break
                    if not s[section]:
                        s[section].append(NONE)
                return edit(notes, fn)
        return None
    return apply


def change_number(notes, m):
    """Change a number that's grounded now, so the fault is a new one."""
    failing = {msg.split(": ", 1)[1] for r, msg in run_checks(notes, R.meeting(m).transcript, "meeting", R.refs())
               if r == "G2"}
    lines = notes.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("## "):
            continue
        for n in re.finditer(r"\d+(?:[.,]\d+)*", line):
            if n.group() not in failing:
                lines[i] = line[:n.start()] + "9137" + line[n.end():]
                return "\n".join(lines)
    return None


def add_name(notes, m):
    def fn(s):
        s["Key Points"].append("- Zebulon Quarrington reviewed the remote control budget.")
    return edit(notes, fn)


def add_bold(notes, m):
    return re.sub(r"^- (?!\[)", "- **Note:** ", notes, count=1, flags=re.M)


def add_parentheses(notes, m):
    def fn(s):
        s["Key Points"][0] = s["Key Points"][0] + " (see above)"
    return edit(notes, fn)


def add_preamble(notes, m):
    return "Here are the meeting notes.\n\n" + notes


def add_gloss(notes, m):
    def fn(s):
        s["Key Points"].append("- The team planned some seva (service) for later.")
    return edit(notes, fn)


def repeat_bullet(notes, m):
    def fn(s):
        line = s["Key Points"][0]
        s["Key Points"] += [line, line]
    return edit(notes, fn)


def none_recorded(notes, m):
    def fn(s):
        for h in ("Decisions", "Action Items", "Open Questions"):
            s[h][:] = [NONE]
    return edit(notes, fn)


MUTATIONS = [
    ("swap owner", "R8", swap_owner),
    ("foreign decision", "R6 precision", insert_foreign_decision),
    ("decision into Key Points", "R11", move_decision),
    ("delete decision", "R6 recall", delete_matched("decision")),
    ("delete action", "R7 recall", delete_matched("action")),
    ("delete open question", "R9 recall", delete_matched("problem")),
    ("change a number", "R4", change_number),
    ("add a name", "R4", add_name),
    ("add bold", "R1", add_bold),
    ("add parentheses", "R1", add_parentheses),
    ("add a preamble", "R1", add_preamble),
    ("add a gloss", "R1", add_gloss),
    ("repeat a bullet", "R3", repeat_bullet),
    ("all None recorded", "recall to 0", none_recorded),
]
CHECK_TARGETS = {"R1", "R3", "R4"}


def worse(target, before, after):
    """Strictly worse on the target, from one meeting's counts."""
    if target in ("R1", "R4"):
        return after["fail_counts"][target] > before["fail_counts"][target]
    if target == "R3":
        return after["loops"] > before["loops"]
    if target == "R8":
        return after["own_agree"] < before["own_agree"]
    if target == "R6 precision":
        p = lambda c: c["m_decision"] / c["b_decision"] if c["b_decision"] else 1.0
        return p(after) < p(before)
    if target == "R11":
        return after["misplaced"] > before["misplaced"]
    kind = {"R6 recall": "decision", "R7 recall": "action", "R9 recall": "problem"}.get(target)
    if kind:
        return after[f"m_{kind}"] < before[f"m_{kind}"]
    if target == "recall to 0":
        if not any(before[f"m_{k}"] for k in ("decision", "action", "problem")):
            return None  # nothing matched before, so nothing to lose
        return all(after[f"m_{k}"] == 0 for k in ("decision", "action", "problem"))
    raise ValueError(target)


def catch_rates():
    notes, source = good_notes()
    c = cfg()
    rates = {}
    for name, target, apply in MUTATIONS:
        caught = tried = 0
        missed = []
        for m, record in notes:
            new = apply(record["notes"], m)
            if new is None or new == record["notes"]:
                continue
            before = R.score(record, m, c)
            after = R.score({"notes": new, "done_reason": "stop"}, m, c)
            hit = worse(target, before, after)
            if hit is None:
                continue
            tried += 1
            if hit:
                caught += 1
            else:
                missed.append(m)
        rates[name] = {"target": target, "tried": tried, "caught": caught, "missed": missed}
    return rates, source


class MutationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rates, cls.source = catch_rates()

    def test_check_criteria_catch_every_mutation(self):
        for name, r in self.rates.items():
            if r["target"] in CHECK_TARGETS and r["tried"]:
                self.assertEqual(r["caught"], r["tried"], f"{name}: missed on {r['missed']}")

    def test_anchored_criteria_catch_95_percent(self):
        caught = sum(r["caught"] for r in self.rates.values() if r["target"] not in CHECK_TARGETS)
        tried = sum(r["tried"] for r in self.rates.values() if r["target"] not in CHECK_TARGETS)
        self.assertGreaterEqual(caught / max(1, tried), 0.95)


def main():
    rates, source = catch_rates()
    print(f"Config {R.config_name(cfg())}; good notes: six samples + the 12B's {source} notes")
    print("| Mutation | Target | Tried | Caught | Rate |\n|---|---|---|---|---|")
    for name, r in rates.items():
        rate = f"{r['caught'] / r['tried']:.0%}" if r["tried"] else "—"
        print(f"| {name} | {r['target']} | {r['tried']} | {r['caught']} | {rate} |")
    for kind in ("check", "anchored"):
        sel = [r for r in rates.values() if (r["target"] in CHECK_TARGETS) == (kind == "check")]
        t, c = sum(r["tried"] for r in sel), sum(r["caught"] for r in sel)
        print(f"{kind}: {c}/{t} = {c / max(1, t):.1%}")
    R.OUT.mkdir(parents=True, exist_ok=True)
    (R.OUT / f"mutations-{os.environ.get('RUBRIC_CONFIG', 'start')}.json").write_text(
        json.dumps({"config": R.config_name(cfg()), "source": source, "rates": rates}, indent=1) + "\n")


if __name__ == "__main__":
    if sys.argv[1:] == ["--rates"]:
        main()
    else:
        sys.argv = sys.argv[:1]
        unittest.main(verbosity=2, exit=False)
        main()
